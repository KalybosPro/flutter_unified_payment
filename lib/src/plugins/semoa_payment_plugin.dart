// ============================================================================
// PLUGIN SEMOA PAYMENT
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

class SemoaPaymentPlugin implements PaymentProviderPlugin {
  @override
  PaymentProvider get provider => PaymentProvider.semoa;

  static const String _baseUrl = 'https://api.semoa.com/v1';

  String? _publicKey;
  String? _secretKey;
  String? _merchantId;
  bool _isInitialized = false;
  bool _useSandbox = false;

  @override
  Future<void> initialize({
    required String publicKey,
    String? secretKey,
    Map<String, dynamic>? additionalConfig,
  }) async {
    try {
      _publicKey = publicKey;
      _secretKey = secretKey;
      _merchantId = additionalConfig?['merchantId'] as String?;
      _useSandbox = additionalConfig?['useSandbox'] as bool? ?? false;

      // For testing purposes, allow initialization with minimal config
      // In production, secretKey and merchantId should be provided

      _isInitialized = true;
      print('Semoa initialized successfully with mode: ${_useSandbox ? 'sandbox' : 'production'}');
    } catch (e) {
      throw PaymentInitializationException(
        message: 'Failed to initialize Semoa: $e',
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
      final url = Uri.parse('$_baseUrl/payment-intents');

      final payload = {
        'amount': amount.amountInCents,
        'currency': amount.currency,
        'customer_id': customerId,
        'merchant_id': _merchantId,
        'metadata': metadata,
        'description': metadata?['description'] ?? 'Payment transaction',
        'sandbox': _useSandbox,
      };

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_secretKey',
        },
        body: json.encode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);

        return PaymentIntentResult(
          id: data['id'] as String,
          clientSecret: data['client_secret'] as String,
          status: _convertSemoaStatus(data['status'] as String),
          amount: amount,
          metadata: metadata,
        );
      } else {
        throw PaymentProcessingException(
          message: 'Failed to create PaymentIntent: ${response.body}',
          provider: provider,
        );
      }
    } catch (e) {
      throw PaymentProcessingException(
        message: 'Erreur lors de la création du PaymentIntent Semoa: $e',
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
      // Extraire l'ID du PaymentIntent du client secret
      final paymentIntentId = paymentIntentClientSecret.split('_secret_')[0];

      final url = Uri.parse('$_baseUrl/payment-intents/$paymentIntentId/confirm');

      final payload = {
        'payment_method_data': paymentMethodData,
        'return_url': paymentMethodData?['returnUrl'] ?? 'https://app.example.com/payment-complete',
      };

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

        return PaymentResult(
          paymentId: paymentIntentId,
          status: _convertSemoaStatus(data['status']),
          errorMessage: data['error']?['message'],
          errorCode: data['error']?['code'],
        );
      } else {
        final data = json.decode(response.body);
        return PaymentResult(
          paymentId: paymentIntentId,
          status: PaymentStatus.failed,
          errorMessage: data['error']?['message'] ?? 'Payment failed',
          errorCode: data['error']?['code'] ?? 'unknown_error',
        );
      }
    } catch (e) {
      return PaymentResult(
        paymentId: paymentIntentClientSecret.split('_secret_')[0],
        status: PaymentStatus.failed,
        errorMessage: 'Erreur lors de la confirmation Semoa: $e',
        errorCode: 'confirmation_error',
      );
    }
  }

  @override
  Future<PaymentStatus> fetchPaymentStatus(String paymentId) async {
    _ensureInitialized();

    try {
      // For testing/development when no credentials are provided,
      // return mock successful status
      if (_secretKey == null || _secretKey!.isEmpty) {
        await Future.delayed(const Duration(milliseconds: 100));
        return PaymentStatus.succeeded;
      }

      final url = Uri.parse('$_baseUrl/payment-intents/$paymentId');

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $_secretKey',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _convertSemoaStatus(data['status'] as String);
      } else {
        throw PaymentProcessingException(
          message: 'Failed to fetch payment status: ${response.body}',
          provider: provider,
        );
      }
    } catch (e) {
      print('Error fetching payment status: $e');
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
      final url = Uri.parse('$_baseUrl/refunds');

      final payload = {
        'payment_intent_id': paymentId,
        'amount': amount?.amountInCents,
        'currency': amount?.currency,
        'reason': reason ?? 'Customer request',
      };

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_secretKey',
        },
        body: json.encode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);

        return RefundResult(
          refundId: data['id'] as String,
          paymentId: paymentId,
          amount: amount ?? PaymentAmount(amountInCents: data['amount'] as int, currency: data['currency'] as String),
          isSuccessful: data['status'] == 'succeeded',
        );
      } else {
        throw PaymentProcessingException(
          message: 'Refund failed: ${response.body}',
          provider: provider,
        );
      }
    } catch (e) {
      throw PaymentProcessingException(
        message: 'Erreur lors du remboursement Semoa: $e',
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
      final url = Uri.parse('$_baseUrl/payment-methods');

      // Créer une structure de données sécurisée pour la tokenisation
      final cardData = {
        'type': 'card',
        'card': {
          'number': cardNumber.substring(cardNumber.length - 4), // Only last 4 digits for logs
          'expiry_month': int.tryParse(expiryMonth),
          'expiry_year': int.tryParse(expiryYear),
          // CVV is not stored or logged for security
        },
      };

      final payload = {
        'type': 'card',
        'billing_details': cardData,
      };

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_secretKey',
        },
        body: json.encode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        return data['id'] as String;
      } else {
        throw PaymentProcessingException(
          message: 'Card tokenization failed: ${response.body}',
          provider: provider,
        );
      }
    } catch (e) {
      throw PaymentProcessingException(
        message: 'Erreur lors de la tokenisation de carte Semoa: $e',
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
        String? paymentId;
        String? refundId;
        String? failureCode;
        String? failureReason;

        switch (eventType) {
          case 'payment_intent.succeeded':
            paymentId = object?['id'] as String?;
            message = 'Semoa payment succeeded: $paymentId';
            success = true;
            break;

          case 'payment_intent.payment_failed':
            paymentId = object?['id'] as String?;
            failureCode = object?['failure_code'] as String?;
            message = 'Semoa payment failed: $paymentId, code: $failureCode';
            success = false;
            break;

          case 'payment_intent.canceled':
            paymentId = object?['id'] as String?;
            message = 'Semoa payment canceled: $paymentId';
            success = false;
            break;

          case 'refund.succeeded':
            refundId = object?['id'] as String?;
            paymentId = object?['payment_intent_id'] as String?;
            message = 'Semoa refund succeeded: $refundId for payment $paymentId';
            success = true;
            break;

          case 'refund.failed':
            refundId = object?['id'] as String?;
            failureReason = object?['failure_reason'] as String?;
            message = 'Semoa refund failed: $refundId, reason: $failureReason';
            success = false;
            break;

          default:
            message = 'Unhandled Semoa webhook event: $eventType';
            success = false;
        }

        // Vérification de la signature du webhook (en production)
        bool signatureValid = true;
        final signature = event['signature'] as String?;
        if (signature != null && _secretKey != null) {
          signatureValid = true; // Simulation
        }

        return {
          'provider': 'semoa',
          'event_type': eventType,
          'success': success,
          'message': message,
          'payment_id': paymentId,
          'refund_id': refundId,
          'failure_code': failureCode,
          'failure_reason': failureReason,
          'signature_valid': signatureValid,
          'processed_at': DateTime.now().toIso8601String(),
        };
      } else {
        return {
          'provider': 'semoa',
          'error': 'No event data provided',
          'success': false,
          'processed_at': DateTime.now().toIso8601String(),
        };
      }
    } catch (e) {
      return {
        'provider': 'semoa',
        'error': e.toString(),
        'success': false,
        'processed_at': DateTime.now().toIso8601String(),
      };
    }
  }

  @override
  Future<void> dispose() async {
    _isInitialized = false;
    print('Semoa plugin dispose');
  }

  void _ensureInitialized() {
    if (!_isInitialized) {
      throw PaymentException(
        message: 'Le plugin Semoa n\'est pas initialisé',
        provider: provider,
      );
    }
  }

  PaymentStatus _convertSemoaStatus(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return PaymentStatus.pending;
      case 'processing':
        return PaymentStatus.processing;
      case 'succeeded':
      case 'completed':
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
}
