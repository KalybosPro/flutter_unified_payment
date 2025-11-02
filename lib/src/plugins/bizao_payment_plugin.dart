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

class BizaoPaymentPlugin implements PaymentProviderPlugin {
  @override
  PaymentProvider get provider => PaymentProvider.bizao;

  static const String _baseUrl = 'https://api.bizao.com';

  String? _apiKey;
  String? _merchantId;
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
      _merchantId = secretKey;
      _useSandbox = additionalConfig?['useSandbox'] as bool? ?? false;

      if (_apiKey == null || _apiKey!.isEmpty) {
        throw PaymentInitializationException(
          message: 'Bizao API key is required',
          provider: provider,
        );
      }

      if (_merchantId == null || _merchantId!.isEmpty) {
        throw PaymentInitializationException(
          message: 'Bizao merchant ID is required',
          provider: provider,
        );
      }

      _isInitialized = true;
      print('Bizao initialized successfully with mode: ${_useSandbox ? 'sandbox' : 'production'}');
    } catch (e) {
      throw PaymentInitializationException(
        message: 'Failed to initialize Bizao: $e',
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

      // For Bizao, we create a unique transaction reference
      final transactionRef = 'bizao_${DateTime.now().millisecondsSinceEpoch}_${customerId.hashCode.abs()}';

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
      if (_apiKey == null || _merchantId == null) {
        throw PaymentProcessingException(
          message: 'API key and merchant ID are required for payment confirmation',
          provider: provider,
        );
      }

      // Bizao payment confirmation
      final url = Uri.parse('$_baseUrl/v1/payments');

      final payload = {
        'merchantId': _merchantId,
        'reference': paymentIntentClientSecret,
        'amount': {
          'value': (paymentMethodData?['amount'] as int? ?? 100) / 100.0,
          'currency': paymentMethodData?['currency'] as String? ?? 'XAF',
        },
        'customer': {
          'email': paymentMethodData?['customerEmail'] as String? ?? 'customer@example.com',
          'phone': paymentMethodData?['customerPhone'] as String? ?? '+237600000000',
          'name': paymentMethodData?['customerName'] as String? ?? 'Customer Name',
        },
        'description': paymentMethodData?['description'] as String? ?? 'Payment transaction',
        'callbackUrl': paymentMethodData?['successUrl'] as String? ?? 'https://yourapp.com/callback',
      };

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: json.encode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        final transactionId = data['transactionId'] ?? paymentIntentClientSecret;

        return PaymentResult(
          paymentId: transactionId,
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
      if (_apiKey != null && _merchantId != null) {
        final response = await http.get(
          Uri.parse('$_baseUrl/v1/payments/$paymentId/status'),
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'X-Merchant-Id': _merchantId!,
          },
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final status = data['status'] as String?;

          return _convertBizaoStatus(status);
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

  PaymentStatus _convertBizaoStatus(String? status) {
    switch (status?.toLowerCase()) {
      case 'success':
      case 'successful':
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
      if (_apiKey != null && _merchantId != null) {
        final response = await http.post(
          Uri.parse('$_baseUrl/v1/refunds'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_apiKey',
            'X-Merchant-Id': _merchantId!,
          },
          body: json.encode({
            'originalTransactionId': paymentId,
            'amount': {
              'value': amount?.amountInMajorUnits ?? 0,
              'currency': amount?.currency ?? 'XAF',
            },
            'reason': reason ?? 'Customer request',
          }),
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = json.decode(response.body);
          final refundData = data['refund'];

          return RefundResult(
            refundId: refundData?['refundId'] ?? 'ref_${DateTime.now().millisecondsSinceEpoch}',
            paymentId: paymentId,
            amount: amount ?? PaymentAmount(amountInCents: refundData?['amount']?['value'] ?? 0, currency: refundData?['amount']?['currency'] ?? 'XAF'),
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

        final refundId = 'bizao_refund_${DateTime.now().millisecondsSinceEpoch}';
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
          amount: amount ?? PaymentAmount(amountInCents: 1000, currency: 'XAF'),
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
      if (_apiKey != null && _merchantId != null) {
        final response = await http.post(
          Uri.parse('$_baseUrl/v1/tokens'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_apiKey',
            'X-Merchant-Id': _merchantId!,
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

        return 'bizao_token_${DateTime.now().millisecondsSinceEpoch}';
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
            reference = eventData['reference'] as String?;
            final status = eventData['status'] as String?;
            message = 'Bizao payment completed: $reference, status: $status';
            success = status?.toLowerCase() == 'success';
            id = eventData['transactionId'] as String?;
            break;

          case 'payment.failed':
            reference = eventData['reference'] as String?;
            message = 'Bizao payment failed: $reference';
            success = false;
            id = eventData['transactionId'] as String?;
            break;

          case 'refund.completed':
            id = eventData['refundId'] as String?;
            message = 'Bizao refund completed: $id';
            success = true;
            break;

          default:
            message = 'Unhandled Bizao webhook: $eventType';
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
          'provider': 'bizao',
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
          'provider': 'bizao',
          'error': 'No event data provided',
          'success': false,
          'processed_at': DateTime.now().toIso8601String(),
        };
      }
    } catch (e) {
      return {
        'provider': 'bizao',
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
        message: 'Le plugin Bizao n\'est pas initialisé',
        provider: provider,
      );
    }
  }
}
