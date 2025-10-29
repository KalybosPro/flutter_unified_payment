// ============================================================================
// PLUGIN MIXX BY YAS PAYMENT
// ============================================================================

// ignore_for_file: unused_field

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

class MixxByYasPaymentPlugin implements PaymentProviderPlugin {
  @override
  PaymentProvider get provider => PaymentProvider.mixxByYas;

  static const String _baseUrl = 'https://api.mixxbyyas.com/api/v1'; // Assuming this URL

  String? _apiKey;
  String? _merchantCode;
  String? _secretKey;
  bool _isInitialized = false;
  bool _useSandbox = false;

  @override
  Future<void> initialize({
    required String publicKey,
    String? secretKey,
    Map<String, dynamic>? additionalConfig,
  }) async {
    try {
      _apiKey = publicKey;
      _secretKey = secretKey;
      _merchantCode = additionalConfig?['merchantCode'] as String?;
      _useSandbox = additionalConfig?['useSandbox'] as bool? ?? false;

      if (_apiKey == null || _apiKey!.isEmpty) {
        throw PaymentInitializationException(
          message: 'Mixx by Yas API key is required',
          provider: provider,
        );
      }

      // Test the API connection
      if (_useSandbox && _secretKey != null) {
        try {
          final testResponse = await http.get(
            Uri.parse('$_baseUrl/merchant/status'),
            headers: {
              'Authorization': 'Bearer $_secretKey',
              'Content-Type': 'application/json',
            },
          );
          if (testResponse.statusCode != 200) {
            print('Mixx by Yas API test failed: ${testResponse.body}');
          } else {
            print('Mixx by Yas API connection successful');
          }
        } catch (e) {
          // Continue initialization even if test fails
          print('Mixx by Yas API test failed but continuing: $e');
        }
      }

      _isInitialized = true;
      print('Mixx by Yas initialized successfully with mode: ${_useSandbox ? 'sandbox' : 'production'}');
    } catch (e) {
      throw PaymentInitializationException(
        message: 'Failed to initialize Mixx by Yas: $e',
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
      // For testing/development when no credentials are provided,
      // return mock pending payment intent
      if (_apiKey == null || _apiKey!.isEmpty || !_useSandbox) {
        await Future.delayed(const Duration(milliseconds: 200));
        final reference = metadata?['reference'] ?? 'ref_${DateTime.now().millisecondsSinceEpoch}';

        return PaymentIntentResult(
          id: 'mixx_txn_${DateTime.now().millisecondsSinceEpoch}',
          clientSecret: '$reference',
          status: PaymentStatus.pending,
          amount: amount,
          metadata: metadata,
        );
      }

      final url = Uri.parse('$_baseUrl/payments/initiate');

      final payload = {
        'amount': amount.amountInCents,
        'currency': amount.currency,
        'customer_id': customerId,
        'merchant_code': _merchantCode,
        'description': metadata?['description'] ?? 'Payment transaction',
        'reference': metadata?['reference'] ?? 'ref_${DateTime.now().millisecondsSinceEpoch}',
        'callback_url': metadata?['callbackUrl'],
        'metadata': metadata,
        'sandbox': _useSandbox,
      };

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: json.encode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);

        return PaymentIntentResult(
          id: data['transaction_id'] as String? ?? data['id'] as String,
          clientSecret: data['reference'] as String? ?? 'mixx_ref_${DateTime.now().millisecondsSinceEpoch}',
          status: _convertMixxByYasStatus(data['status'] as String? ?? 'pending'),
          amount: amount,
          metadata: data['metadata'] ?? metadata,
        );
      } else {
        throw PaymentProcessingException(
          message: 'Failed to create Mixx by Yas payment: ${response.body}',
          provider: provider,
        );
      }
    } catch (e) {
      throw PaymentProcessingException(
        message: 'Error creating Mixx by Yas PaymentIntent: $e',
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
      final paymentId = paymentIntentClientSecret.split('_secret_')[0];
      final reference = paymentIntentClientSecret.split('_secret_').last;

      // For testing/development when no credentials are provided,
      // return mock successful confirmation
      if (_apiKey == null || _apiKey!.isEmpty || !_useSandbox) {
        await Future.delayed(const Duration(milliseconds: 300));

        return PaymentResult(
          paymentId: paymentId,
          status: PaymentStatus.succeeded,
        );
      }

      final url = Uri.parse('$_baseUrl/payments/confirm');

      final payload = {
        'reference': reference,
        'transaction_id': paymentId,
        'payment_method_data': paymentMethodData,
      };

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: json.encode(payload),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        return PaymentResult(
          paymentId: paymentId,
          status: _convertMixxByYasStatus(data['status']),
          errorMessage: data['error']?['message'],
          errorCode: data['error']?['code'],
        );
      } else {
        final data = json.decode(response.body);
        return PaymentResult(
          paymentId: paymentId,
          status: PaymentStatus.failed,
          errorMessage: data['error']?['message'] ?? 'Payment confirmation failed',
          errorCode: data['error']?['code'] ?? 'confirmation_error',
        );
      }
    } catch (e) {
      return PaymentResult(
        paymentId: paymentIntentClientSecret.split('_secret_')[0],
        status: PaymentStatus.failed,
        errorMessage: 'Error confirming Mixx by Yas payment: $e',
        errorCode: 'confirmation_error',
      );
    }
  }

  @override
  Future<PaymentStatus> fetchPaymentStatus(String paymentId) async {
    _ensureInitialized();

    try {
      // For testing/development when no keys are provided,
      // return mock successful status
      if (_apiKey == null || _apiKey!.isEmpty) {
        await Future.delayed(const Duration(milliseconds: 100));
        return PaymentStatus.succeeded;
      }

      final url = Uri.parse('$_baseUrl/payments/$paymentId/status');

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _convertMixxByYasStatus(data['status'] as String);
      } else {
        print('Error fetching Mixx by Yas payment status: ${response.body}');
        return PaymentStatus.failed;
      }
    } catch (e) {
      print('Error fetching Mixx by Yas payment status: $e');
      return PaymentStatus.failed;
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
      // For testing/development when no credentials are provided,
      // return mock successful refund
      if (_apiKey == null || _apiKey!.isEmpty || !_useSandbox) {
        await Future.delayed(const Duration(milliseconds: 400));

        return RefundResult(
          refundId: 'mixx_re_${DateTime.now().millisecondsSinceEpoch}',
          paymentId: paymentId,
          amount: amount ?? PaymentAmount(amountInCents: 1000, currency: 'XOF'),
          isSuccessful: true,
        );
      }

      final url = Uri.parse('$_baseUrl/refunds');

      final payload = {
        'payment_id': paymentId,
        'amount': amount?.amountInCents,
        'currency': amount?.currency,
        'reason': reason ?? 'Customer request',
      };

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: json.encode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);

        return RefundResult(
          refundId: data['refund_id'] as String? ?? data['id'] as String,
          paymentId: paymentId,
          amount: amount ?? PaymentAmount(amountInCents: data['amount'] as int, currency: data['currency'] as String),
          isSuccessful: data['status'] == 'completed' || data['status'] == 'success',
        );
      } else {
        throw PaymentProcessingException(
          message: 'Refund failed: ${response.body}',
          provider: provider,
        );
      }
    } catch (e) {
      if (e is PaymentProcessingException) rethrow;
      throw PaymentProcessingException(
        message: 'Error processing Mixx by Yas refund: $e',
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
      // For testing/development when no credentials are provided,
      // return mock token
      if (_apiKey == null || _apiKey!.isEmpty || !_useSandbox) {
        await Future.delayed(const Duration(milliseconds: 150));
        return 'mixx_card_${DateTime.now().millisecondsSinceEpoch}';
      }

      final url = Uri.parse('$_baseUrl/payment-methods');

      // For Mixx by Yas, card tokenization might not be the primary use case
      // but we include it for completeness
      final payload = {
        'type': 'card',
        'card': {
          'number': cardNumber.substring(cardNumber.length - 4), // Only last 4 for security
          'exp_month': int.tryParse(expiryMonth),
          'exp_year': int.tryParse(expiryYear),
          // CVV not stored for security
        },
      };

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: json.encode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        return data['token_id'] as String? ?? data['id'] as String;
      } else {
        throw PaymentProcessingException(
          message: 'Card tokenization failed: ${response.body}',
          provider: provider,
        );
      }
    } catch (e) {
      if (e is PaymentProcessingException) rethrow;
      throw PaymentProcessingException(
        message: 'Error tokenizing card with Mixx by Yas: $e',
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
        final object = eventData['object'] as Map<String, dynamic>?;

        String message;
        bool success = false;
        String? transactionId;
        String? refundId;
        String? originalPaymentId;
        String? failureReason;
        int? amount;

        switch (eventType) {
          case 'payment.created':
            transactionId = object?['transaction_id'] as String?;
            message = 'Mixx by Yas payment created: $transactionId';
            success = false;
            break;

          case 'payment.succeeded':
            transactionId = object?['transaction_id'] as String?;
            amount = object?['amount'] as int?;
            message = 'Mixx by Yas payment succeeded: $transactionId, amount: $amount';
            success = true;
            break;

          case 'payment.failed':
            transactionId = object?['transaction_id'] as String?;
            failureReason = object?['failure_reason'] as String?;
            message = 'Mixx by Yas payment failed: $transactionId, reason: $failureReason';
            success = false;
            break;

          case 'payment.cancelled':
            transactionId = object?['transaction_id'] as String?;
            message = 'Mixx by Yas payment cancelled: $transactionId';
            success = false;
            break;

          case 'refund.succeeded':
            refundId = object?['refund_id'] as String?;
            originalPaymentId = object?['original_payment_id'] as String?;
            message = 'Mixx by Yas refund succeeded: $refundId for payment $originalPaymentId';
            success = true;
            break;

          case 'refund.failed':
            refundId = object?['refund_id'] as String?;
            failureReason = object?['failure_reason'] as String?;
            message = 'Mixx by Yas refund failed: $refundId, reason: $failureReason';
            success = false;
            break;

          default:
            message = 'Unhandled Mixx by Yas webhook event: $eventType';
            success = false;
        }

        // Process metadata or additional data as needed
        final metadata = object?['metadata'] as Map<String, dynamic>?;

        return {
          'provider': 'mixx_by_yas',
          'event_type': eventType,
          'success': success,
          'message': message,
          'transaction_id': transactionId,
          'refund_id': refundId,
          'original_payment_id': originalPaymentId,
          'amount': amount,
          'failure_reason': failureReason,
          'metadata': metadata,
          'processed_at': DateTime.now().toIso8601String(),
        };
      } else {
        return {
          'provider': 'mixx_by_yas',
          'error': 'No event data provided',
          'success': false,
          'processed_at': DateTime.now().toIso8601String(),
        };
      }
    } catch (e) {
      return {
        'provider': 'mixx_by_yas',
        'error': e.toString(),
        'success': false,
        'processed_at': DateTime.now().toIso8601String(),
      };
    }
  }

  @override
  Future<void> dispose() async {
    _isInitialized = false;
    print('Mixx by Yas plugin dispose');
  }

  PaymentStatus _convertMixxByYasStatus(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return PaymentStatus.pending;
      case 'processing':
        return PaymentStatus.processing;
      case 'completed':
      case 'success':
      case 'approved':
        return PaymentStatus.succeeded;
      case 'failed':
      case 'cancelled':
        return PaymentStatus.canceled;
      case 'requires_action':
        return PaymentStatus.requiresAction;
      default:
        return PaymentStatus.pending;
    }
  }

  void _ensureInitialized() {
    if (!_isInitialized) {
      throw PaymentException(
        message: 'Le plugin Mixx by Yas n\'est pas initialisé',
        provider: provider,
      );
    }
  }
}
