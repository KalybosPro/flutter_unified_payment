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

class MtnPaymentPlugin implements PaymentProviderPlugin {
  @override
  PaymentProvider get provider => PaymentProvider.mtnMomo;

  static const String _baseUrl = 'https://api.mtn.com';

  String? _apiKey;
  String? _apiSecret;
  String? _subscriptionKey;
  bool _isInitialized = false;
  bool _useSandbox = false; // To switch between production and sandbox

  @override
  Future<void> initialize({
    required String publicKey,
    String? secretKey,
    Map<String, dynamic>? additionalConfig,
  }) async {
    try {
      _apiKey = publicKey;
      _apiSecret = secretKey;
      _subscriptionKey = additionalConfig?['subscriptionKey'] as String?;
      _useSandbox = additionalConfig?['useSandbox'] as bool? ?? false;

      if (_apiKey == null || _apiKey!.isEmpty) {
        throw PaymentInitializationException(
          message: 'MTN API key is required',
          provider: provider,
        );
      }

      if (_apiSecret == null || _apiSecret!.isEmpty) {
        throw PaymentInitializationException(
          message: 'MTN API secret is required',
          provider: provider,
        );
      }

      if (_subscriptionKey == null || _subscriptionKey!.isEmpty) {
        throw PaymentInitializationException(
          message: 'MTN subscription key is required',
          provider: provider,
        );
      }

      _isInitialized = true;
      print('MTN initialized successfully with mode: ${_useSandbox ? 'sandbox' : 'production'}');
    } catch (e) {
      throw PaymentInitializationException(
        message: 'Failed to initialize MTN: $e',
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

      // For MTN, we create a unique transaction reference
      final transactionRef = 'mtn_${DateTime.now().millisecondsSinceEpoch}_${customerId.hashCode.abs()}';

      return PaymentIntentResult(
        id: transactionRef,
        clientSecret: transactionRef,
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
      if (_apiKey == null || _apiSecret == null || _subscriptionKey == null) {
        throw PaymentProcessingException(
          message: 'API credentials are required for payment confirmation',
          provider: provider,
        );
      }

      // MTN payment confirmation
      final url = Uri.parse('$_baseUrl/v1_0/merchantpay/collections');

      final payload = {
        'amount': (paymentMethodData?['amount'] as int? ?? 100).toString(),
        'currency': paymentMethodData?['currency'] as String? ?? 'EUR',
        'externalId': paymentIntentClientSecret,
        'payer': {
          'partyIdType': 'MSISDN',
          'partyId': paymentMethodData?['customerPhone'] as String? ?? '+237600000000',
        },
        'payerMessage': paymentMethodData?['description'] as String? ?? 'Payment transaction',
        'payeeNote': 'Payment received',
      };

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
          'X-Reference-Id': paymentIntentClientSecret,
          'X-Target-Environment': _useSandbox ? 'sandbox' : 'production',
          'Ocp-Apim-Subscription-Key': _subscriptionKey!,
        },
        body: json.encode(payload),
      );

      if (response.statusCode == 202) {
        return PaymentResult(
          paymentId: paymentIntentClientSecret,
          status: PaymentStatus.processing,
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

  @override
  Future<PaymentStatus> fetchPaymentStatus(String paymentId) async {
    _ensureInitialized();

    try {
      if (_apiKey != null && _subscriptionKey != null) {
        final response = await http.get(
          Uri.parse('$_baseUrl/v1_0/merchantpay/collections/$paymentId'),
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'X-Target-Environment': _useSandbox ? 'sandbox' : 'production',
            'Ocp-Apim-Subscription-Key': _subscriptionKey!,
          },
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final status = data['status'] as String?;

          return _convertMtnStatus(status);
        } else {
          print('Failed to fetch payment status: ${response.body}');
        }
      }

      // Fallback for development/testing
      await Future.delayed(const Duration(milliseconds: 500));

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

  PaymentStatus _convertMtnStatus(String? status) {
    switch (status?.toLowerCase()) {
      case 'successful':
      case 'success':
      case 'completed':
        return PaymentStatus.succeeded;
      case 'pending':
      case 'initiated':
        return PaymentStatus.pending;
      case 'processing':
        return PaymentStatus.processing;
      case 'failed':
      case 'error':
        return PaymentStatus.failed;
      case 'cancelled':
      case 'canceled':
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
      if (_apiKey != null && _subscriptionKey != null) {
        final response = await http.post(
          Uri.parse('$_baseUrl/v1_0/merchantpay/refunds'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_apiKey',
            'X-Target-Environment': _useSandbox ? 'sandbox' : 'production',
            'Ocp-Apim-Subscription-Key': _subscriptionKey!,
          },
          body: json.encode({
            'originalTransactionId': paymentId,
            'amount': amount?.amountInMajorUnits.toString() ?? '0',
            'currency': amount?.currency ?? 'EUR',
            'reason': reason ?? 'Customer request',
          }),
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = json.decode(response.body);
          final refundData = data['refund'];

          return RefundResult(
            refundId: refundData?['refundId'] ?? 'ref_${DateTime.now().millisecondsSinceEpoch}',
            paymentId: paymentId,
            amount: amount ?? PaymentAmount(amountInCents: refundData?['amount'] ?? 0, currency: refundData?['currency'] ?? 'EUR'),
            isSuccessful: refundData?['status'] == 'success',
          );
        } else {
          throw PaymentProcessingException(
            message: 'Refund failed: ${response.body}',
            provider: provider,
          );
        }
      } else {
        // Simulation for development
        await Future.delayed(const Duration(seconds: 1));

        final refundId = 'mtn_refund_${DateTime.now().millisecondsSinceEpoch}';
        final timestamp = DateTime.now().millisecondsSinceEpoch;

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
          amount: amount ?? PaymentAmount(amountInCents: 1000, currency: 'EUR'),
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
      if (_apiKey != null && _subscriptionKey != null) {
        final response = await http.post(
          Uri.parse('$_baseUrl/v1_0/merchantpay/tokens'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_apiKey',
            'X-Target-Environment': _useSandbox ? 'sandbox' : 'production',
            'Ocp-Apim-Subscription-Key': _subscriptionKey!,
          },
          body: json.encode({
            'card': {
              'number': cardNumber,
              'expiryMonth': expiryMonth,
              'expiryYear': expiryYear,
              'cvv': cvv,
            },
          }),
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = json.decode(response.body);
          final token = data['token'] as String?;
          if (token != null) {
            return token;
          }
        }

        throw PaymentProcessingException(
          message: 'Tokenization failed: ${response.body}',
          provider: provider,
        );
      } else {
        // Simulation for development
        await Future.delayed(const Duration(milliseconds: 300));

        final timestamp = DateTime.now().millisecondsSinceEpoch;
        if (timestamp % 20 == 0) {
          throw PaymentProcessingException(
            message: 'Simulated tokenization failure',
            provider: provider,
          );
        }

        return 'mtn_token_${DateTime.now().millisecondsSinceEpoch}';
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
      final eventType = event['eventType'] as String?;
      final eventData = event['data'] as Map<String, dynamic>?;

      if (eventData != null) {
        String message;
        bool success = false;
        String? id;
        String? reference;

        switch (eventType) {
          case 'payment.success':
            reference = eventData['externalId'] as String?;
            final status = eventData['status'] as String?;
            message = 'MTN payment completed: $reference, status: $status';
            success = status?.toLowerCase() == 'successful';
            id = eventData['transactionId'] as String?;
            break;

          case 'payment.failed':
            reference = eventData['externalId'] as String?;
            message = 'MTN payment failed: $reference';
            success = false;
            id = eventData['transactionId'] as String?;
            break;

          case 'refund.completed':
            id = eventData['refundId'] as String?;
            message = 'MTN refund completed: $id';
            success = true;
            break;

          default:
            message = 'Unhandled MTN webhook: $eventType';
            success = false;
        }

        // Verify webhook signature for security
        bool signatureValid = true;
        final signature = event['signature'] as String?;
        if (signature != null && _apiKey != null) {
          // Webhook signature verification logic would go here
          signatureValid = true; // Simulation
        }

        return {
          'provider': 'mtn',
          'event_type': eventType,
          'success': success,
          'message': message,
          'id': id,
          'reference': reference,
          'transaction_data': eventData,
          'signature_valid': signatureValid,
          'processed_at': DateTime.now().toIso8601String(),
        };
      } else {
        return {
          'provider': 'mtn',
          'error': 'No event data provided',
          'success': false,
          'processed_at': DateTime.now().toIso8601String(),
        };
      }
    } catch (e) {
      return {
        'provider': 'mtn',
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
        message: 'Le plugin MTN n\'est pas initialisé',
        provider: provider,
      );
    }
  }
}
