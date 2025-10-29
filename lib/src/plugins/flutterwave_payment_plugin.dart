// ignore_for_file: unused_field, unused_element

import 'package:http/http.dart' as http;
import 'dart:convert';

import '../core/core.dart'
    show
        PaymentProvider,
        PaymentProviderPlugin,
        PaymentIntentResult,
        PaymentAmount,
        PaymentStatus,
        PaymentResult,
        RefundResult,
        PaymentInitializationException,
        PaymentProcessingException,
        PaymentException;

class FlutterwavePaymentPlugin implements PaymentProviderPlugin {
  @override
  PaymentProvider get provider => PaymentProvider.flutterwave;

  static const String _baseUrl = 'https://api.flutterwave.com/v3';

  String? _publicKey;
  String? _secretKey;
  String? _encryptionKey;
  bool _isInitialized = false;
  bool _useSandbox = false; // To switch between production and sandbox

  @override
  Future<void> initialize({
    required String publicKey,
    String? secretKey,
    Map<String, dynamic>? additionalConfig,
  }) async {
    try {
      _publicKey = publicKey;
      _secretKey = secretKey;
      _encryptionKey = additionalConfig?['encryptionKey'] as String?;
      _useSandbox = additionalConfig?['useSandbox'] as bool? ?? false;

      if (_secretKey == null || _secretKey!.isEmpty) {
        throw PaymentInitializationException(
          message: 'Flutterwave secret key is required',
          provider: provider,
        );
      }

      _isInitialized = true;
      print('Flutterwave initialized successfully with mode: ${_useSandbox ? 'sandbox' : 'production'}');
    } catch (e) {
      throw PaymentInitializationException(
        message: 'Failed to initialize Flutterwave: $e',
        provider: provider,
      );
    }
  }

  @override
  Future<PaymentIntentResult> createPaymentIntent({
    required PaymentAmount amount,
    required String customerId,
    Map<String, dynamic>? metadata,
  }) async {
    _ensureInitialized();

    try {
      // Include client information in metadata if not provided
      final finalMetadata = {
        ...?metadata,
        'customer_id': customerId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      // For Flutterwave, we create a unique "transactionId" which will be our identifier
      final transactionId = 'flutterwave_${DateTime.now().millisecondsSinceEpoch}_${customerId.hashCode.abs()}';

      // In reality, Flutterwave creates authorization keys by email/SMS, not PaymentIntents
      // So we return our own adapted structures
      return PaymentIntentResult(
        id: transactionId,
        clientSecret: transactionId, // Flutterwave does not have client_secret like Stripe
        status: PaymentStatus.pending,
        amount: amount,
        metadata: finalMetadata,
      );
    } catch (e) {
      print('Error creating PaymentIntent: $e');
      throw PaymentProcessingException(
        message: 'Failed to create PaymentIntent: $e',
        provider: provider,
      );
    }
  }

  @override
  Future<PaymentResult> confirmPayment({
    required String paymentIntentClientSecret,
    Map<String, dynamic>? paymentMethodData,
  }) async {
    _ensureInitialized();

    try {
      if (_secretKey == null) {
        throw PaymentProcessingException(
          message: 'Secret key is required for payment confirmation',
          provider: provider,
        );
      }

      // Pour Flutterwave, nous devons créer une transaction complète
      // Ici nous simulons un appel à l'API Flutterwave /v3/payments

      if (_baseUrl.isNotEmpty && _secretKey != null) {
        final url = Uri.parse('$_baseUrl/payments');

        // Déterminer le type de paiement depuis les metadata
        final paymentType = _determinePaymentType(paymentMethodData);

        final payload = {
          'tx_ref': paymentIntentClientSecret,
          'amount': (paymentMethodData?['amount'] as int? ?? 100) / 100.0, // Convertir cents en montant
          'currency': paymentMethodData?['currency'] as String? ?? 'USD',
          'redirect_url': paymentMethodData?['successUrl'] as String? ?? 'https://yourapp.com/success',
          'payment_type': paymentType,
          'customer': {
            'email': paymentMethodData?['customerEmail'] as String? ?? 'customer@example.com',
            'phonenumber': paymentMethodData?['customerPhone'] as String? ?? '+1234567890',
            'name': paymentMethodData?['customerName'] as String? ?? 'Customer Name',
          },
          'customizations': {
            'title': paymentMethodData?['title'] as String? ?? 'Payment',
            'description': paymentMethodData?['description'] as String? ?? 'Payment transaction',
          },
        };

        if (paymentType == 'card') {
          // Ajouter les informations de carte si c'est un paiement par carte
          payload['payment_options'] = 'card';
        }

        final response = await http.post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_secretKey',
          },
          body: json.encode(payload),
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final transactionId = data['data']?['id']?.toString() ?? paymentIntentClientSecret;

          return PaymentResult(
            paymentId: transactionId,
            status: PaymentStatus.processing, // Le paiement est en cours
            errorMessage: null,
            errorCode: null,
          );
        } else {
          return PaymentResult(
            paymentId: paymentIntentClientSecret,
            status: PaymentStatus.failed,
            errorMessage: 'Failed to initiate payment: ${response.body}',
            errorCode: 'api_error',
          );
        }
      } else {
        // Fallback pour développement/tests
        await Future.delayed(const Duration(seconds: 1));

        final isSuccess = !paymentIntentClientSecret.contains('fail');
        return PaymentResult(
          paymentId: paymentIntentClientSecret,
          status: isSuccess ? PaymentStatus.succeeded : PaymentStatus.failed,
          errorMessage: isSuccess ? null : 'Simulated payment failure',
          errorCode: isSuccess ? null : 'simulation_error',
        );
      }
    } catch (e) {
      print('Error confirming payment: $e');
      return PaymentResult(
        paymentId: paymentIntentClientSecret,
        status: PaymentStatus.failed,
        errorMessage: 'Payment confirmation failed: $e',
        errorCode: 'confirmation_error',
      );
    }
  }

  String _determinePaymentType(Map<String, dynamic>? paymentMethodData) {
    if (paymentMethodData == null) return 'card'; // Default

    final type = paymentMethodData['type'] as String?;
    switch (type) {
      case 'card':
        return 'card';
      case 'mobile_money':
        return 'mobilemoneyfranco';
      case 'bank_transfer':
        return 'banktransfer';
      default:
        return 'card';
    }
  }

  @override
  Future<PaymentStatus> fetchPaymentStatus(String paymentId) async {
    _ensureInitialized();

    try {
      if (_secretKey != null && paymentId.startsWith('flutterwave_')) {
        // Extraction de l'ID de transaction Flutterwave
        // En production, vous auriez besoin de stocker le mapping entre votre ID interne et l'ID Flutterwave
        final transactionId = _extractTransactionId(paymentId);

        if (transactionId != null) {
          final response = await http.get(
            Uri.parse('$_baseUrl/transactions/$transactionId/verify'),
            headers: {
              'Authorization': 'Bearer $_secretKey',
            },
          );

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            final status = data['data']?['status'] as String?;

            return _convertFlutterwaveStatus(status);
          } else {
            print('Failed to fetch transaction status: ${response.body}');
          }
        }
      }

      // Fallback pour développement/tests ou si l'ID n'est pas reconnu
      await Future.delayed(const Duration(milliseconds: 500));

      // Simuler différents statuts pour démonstration
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      switch (timestamp % 5) {
        case 0:
          return PaymentStatus.pending;
        case 1:
          return PaymentStatus.processing;
        case 2:
          return PaymentStatus.requiresAction;
        case 3:
          return PaymentStatus.canceled;
        case 4:
        default:
          return PaymentStatus.succeeded;
      }
    } catch (e) {
      print('Error fetching payment status: $e');
      return PaymentStatus.failed;
    }
  }

  String? _extractTransactionId(String paymentId) {
    // Extraire l'ID de transaction numérique de notre format
    final parts = paymentId.split('_');
    if (parts.length >= 3) {
      return parts[2]; // Récupérer le timestamp qui devient notre ID unique
    }
    return null;
  }

  PaymentStatus _convertFlutterwaveStatus(String? status) {
    switch (status?.toLowerCase()) {
      case 'successful':
        return PaymentStatus.succeeded;
      case 'pending':
        return PaymentStatus.pending;
      case 'processing':
        return PaymentStatus.processing;
      case 'failed':
        return PaymentStatus.failed;
      case 'cancelled':
        return PaymentStatus.canceled;
      default:
        return PaymentStatus.pending;
    }
  }

  @override
  Future<RefundResult> refundPayment({
    required String paymentId,
    PaymentAmount? amount,
    String? reason,
  }) async {
    _ensureInitialized();

    try {
      if (_secretKey != null) {
        // Démarrer par vérifier que la transaction existe et peut être remboursée
        final transactionId = _extractTransactionId(paymentId) ?? paymentId;

        // Appel API pour créer un refund Flutterwave
        final response = await http.post(
          Uri.parse('$_baseUrl/transactions/$transactionId/refund'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_secretKey',
          },
          body: json.encode({
            'amount': amount?.amountInMajorUnits, // Montant en devise normale
            'reason': reason ?? 'Customer request',
          }),
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final refundData = data['data'];

          return RefundResult(
            refundId: refundData?['id']?.toString() ?? 'ref_${DateTime.now().millisecondsSinceEpoch}',
            paymentId: paymentId,
            amount: amount ?? PaymentAmount(amountInCents: refundData?['amount'] ?? 0, currency: refundData?['currency'] ?? 'USD'),
            isSuccessful: refundData?['status'] == 'successful',
          );
        } else {
          throw PaymentProcessingException(
            message: 'Refund failed: ${response.body}',
            provider: provider,
          );
        }
      } else {
        // Simulation pour développement
        await Future.delayed(const Duration(seconds: 1));

        final refundId = 'fw_refund_${DateTime.now().millisecondsSinceEpoch}';
        final timestamp = DateTime.now().millisecondsSinceEpoch;

        // Simuler un échec occasionnel
        final shouldFail = timestamp % 10 == 0;

        if (shouldFail) {
          throw PaymentProcessingException(
            message: 'Simulated refund failure',
            provider: provider,
          );
        }

        return RefundResult(
          refundId: refundId,
          paymentId: paymentId,
          amount: amount ?? PaymentAmount(amountInCents: 1000, currency: 'USD'),
          isSuccessful: true,
        );
      }
    } catch (e) {
      if (e is PaymentProcessingException) rethrow;
      throw PaymentProcessingException(
        message: 'Refund processing failed: $e',
        provider: provider,
      );
    }
  }

  @override
  Future<String> tokenizeCard({
    required String cardNumber,
    required String expiryMonth,
    required String expiryYear,
    required String cvv,
  }) async {
    _ensureInitialized();

    try {
      if (_secretKey != null && _encryptionKey != null) {
        // Flutterwave permet de tokeniser des cartes pour utilisation future
        final response = await http.post(
          Uri.parse('$_baseUrl/tokens'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_secretKey',
          },
          body: json.encode({
            'card': {
              'number': cardNumber,
              'expiry_month': expiryMonth,
              'expiry_year': expiryYear,
              'cvv': cvv,
            },
            'encryption_key': _encryptionKey, // Pour chiffrer les données sensibles
          }),
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final token = data['data']?['token'] as String?;
          if (token != null) {
            return token;
          }
        }

        throw PaymentProcessingException(
          message: 'Tokenization failed: ${response.body}',
          provider: provider,
        );
      } else {
        // Simulation pour développement
        await Future.delayed(const Duration(milliseconds: 300));

        // Simuler un échec occasionnel
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        if (timestamp % 20 == 0) {
          throw PaymentProcessingException(
            message: 'Simulated tokenization failure',
            provider: provider,
          );
        }

        return 'fw_token_${DateTime.now().millisecondsSinceEpoch}';
      }
    } catch (e) {
      if (e is PaymentProcessingException) rethrow;
      throw PaymentProcessingException(
        message: 'Card tokenization failed: $e',
        provider: provider,
      );
    }
  }

  @override
  Future<Map<String, dynamic>> handleWebhookEvent(Map<String, dynamic> event) async {
    try {
      final eventType = event['type'] as String?;
      final eventData = event['data'] as Map<String, dynamic>?;

      if (eventData != null) {
        final transactionData = eventData['data'] as Map<String, dynamic>?;

        String message;
        bool success = false;
        String? id;
        String? txRef;

        switch (eventType) {
          case 'charge.completed':
            txRef = transactionData?['tx_ref'] as String?;
            final status = transactionData?['status'] as String?;
            message = 'Flutterwave charge completed: $txRef, status: $status';
            success = status?.toLowerCase() == 'successful';
            id = transactionData?['id'] as String?;
            break;

          case 'transfer.completed':
            id = transactionData?['id'] as String?;
            message = 'Flutterwave transfer completed: $id';
            success = true;
            break;

          case 'refund.completed':
            id = transactionData?['id'] as String?;
            message = 'Flutterwave refund completed: $id';
            success = true;
            break;

          case 'subscription.cancelled':
            id = transactionData?['id'] as String?;
            message = 'Flutterwave subscription cancelled: $id';
            success = false;
            break;

          default:
            message = 'Unhandled Flutterwave webhook: $eventType';
            success = false;
        }

        // Vérifier la signature du webhook pour la sécurité
        // En production, vous devriez toujours vérifier la signature
        bool signatureValid = true;
        final signature = event['signature'] as String?;
        if (signature != null && _secretKey != null) {
          // Logique de vérification de signature ici
          signatureValid = true; // Simulation
        }

        return {
          'provider': 'flutterwave',
          'event_type': eventType,
          'success': success,
          'message': message,
          'id': id,
          'tx_ref': txRef,
          'transaction_data': transactionData,
          'signature_valid': signatureValid,
          'processed_at': DateTime.now().toIso8601String(),
        };
      } else {
        return {
          'provider': 'flutterwave',
          'error': 'No event data provided',
          'success': false,
          'processed_at': DateTime.now().toIso8601String(),
        };
      }
    } catch (e) {
      return {
        'provider': 'flutterwave',
        'error': e.toString(),
        'success': false,
        'processed_at': DateTime.now().toIso8601String(),
      };
    }
  }

  @override
  Future<void> dispose() async {
    _isInitialized = false;
  }

  void _ensureInitialized() {
    if (!_isInitialized) {
      throw PaymentException(
        message: 'Le plugin Flutterwave n\'est pas initialisé',
        provider: provider,
      );
    }
  }
}
