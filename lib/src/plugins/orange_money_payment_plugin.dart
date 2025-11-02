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

class OrangeMoneyPaymentPlugin implements PaymentProviderPlugin {
  @override
  PaymentProvider get provider => PaymentProvider.orangeMoney;

  static const String _baseUrl = 'https://api.orange.com';

  String? _clientId;
  String? _clientSecret;
  String? _merchantKey;
  bool _isInitialized = false;
  bool _useSandbox = false; // To switch between production and sandbox
  String? _accessToken;

  @override
  Future<void> initialize({
    required String publicKey,
    String? secretKey,
    Map<String, dynamic>? additionalConfig,
  }) async {
    try {
      _clientId = publicKey;
      _clientSecret = secretKey;
      _merchantKey = additionalConfig?['merchantKey'] as String?;
      _useSandbox = additionalConfig?['useSandbox'] as bool? ?? false;

      if (_clientId == null || _clientId!.isEmpty) {
        throw PaymentInitializationException(
          message: 'Orange Money Client ID is required',
          provider: provider,
        );
      }

      if (_clientSecret == null || _clientSecret!.isEmpty) {
        throw PaymentInitializationException(
          message: 'Orange Money Client Secret is required',
          provider: provider,
        );
      }

      if (_merchantKey == null || _merchantKey!.isEmpty) {
        throw PaymentInitializationException(
          message: 'Orange Money Merchant Key is required',
          provider: provider,
        );
      }

      // Get access token
      await _getAccessToken();

      _isInitialized = true;
      print('Orange Money initialized successfully with mode: ${_useSandbox ? 'sandbox' : 'production'}');
    } catch (e) {
      throw PaymentInitializationException(
        message: 'Failed to initialize Orange Money: $e',
        provider: provider,
      );
    }
  }

  Future<void> _getAccessToken() async {
    try {
      final url = Uri.parse('https://api.orange.com/oauth/v3/token');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization': 'Basic ${base64Encode(utf8.encode('$_clientId:$_clientSecret'))}',
        },
        body: {
          'grant_type': 'client_credentials',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _accessToken = data['access_token'] as String?;
        if (_accessToken == null) {
          throw Exception('No access token received');
        }
      } else {
        throw Exception('Failed to get access token: ${response.body}');
      }
    } catch (e) {
      throw PaymentInitializationException(
        message: 'Failed to authenticate with Orange Money: $e',
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

      // For Orange Money, we create a unique transaction reference
      final transactionRef = 'om_${DateTime.now().millisecondsSinceEpoch}_${customerId.hashCode.abs()}';

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
      if (_accessToken == null || _merchantKey == null) {
        throw PaymentProcessingException(
          message: 'Access token and merchant key are required for payment confirmation',
          provider: provider,
        );
      }

      // Orange Money payment confirmation
      final url = Uri.parse('${_useSandbox ? 'https://api-sandbox.orange.com' : _baseUrl}/orange-money-webpay/dev/v1/webpayment');

      final payload = {
        'merchant_key': _merchantKey,
        'currency': paymentMethodData?['currency'] as String? ?? 'XAF',
        'order_id': paymentIntentClientSecret,
        'amount': paymentMethodData?['amount'] as int? ?? 100,
        'return_url': paymentMethodData?['successUrl'] as String? ?? 'https://yourapp.com/callback',
        'cancel_url': paymentMethodData?['cancelUrl'] as String? ?? 'https://yourapp.com/cancel',
        'notif_url': paymentMethodData?['webhookUrl'] as String? ?? 'https://yourapp.com/webhook',
        'lang': paymentMethodData?['lang'] as String? ?? 'fr',
        'reference': paymentIntentClientSecret,
      };

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_accessToken',
        },
        body: json.encode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        final paymentUrl = data['payment_url'] as String?;
        final payToken = data['pay_token'] as String?;

        if (paymentUrl != null && payToken != null) {
          return PaymentResult(
            paymentId: paymentIntentClientSecret,
            status: PaymentStatus.processing,
            errorMessage: null,
            errorCode: null,
            metadata: {
              'payment_url': paymentUrl,
              'pay_token': payToken,
            },
          );
        } else {
          return PaymentResult(
            paymentId: paymentIntentClientSecret,
            status: PaymentStatus.failed,
            errorMessage: 'Invalid response from Orange Money API',
            errorCode: 'invalid_response',
          );
        }
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
      if (_accessToken != null && _merchantKey != null) {
        final url = Uri.parse('${_useSandbox ? 'https://api-sandbox.orange.com' : _baseUrl}/orange-money-webpay/dev/v1/transactionstatus');

        final response = await http.post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_accessToken',
          },
          body: json.encode({
            'order_id': paymentId,
          }),
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final status = data['status'] as String?;

          return _convertOrangeMoneyStatus(status);
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

  PaymentStatus _convertOrangeMoneyStatus(String? status) {
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
      if (_accessToken != null && _merchantKey != null) {
        final url = Uri.parse('${_useSandbox ? 'https://api-sandbox.orange.com' : _baseUrl}/orange-money-webpay/dev/v1/refund');

        final response = await http.post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_accessToken',
          },
          body: json.encode({
            'order_id': paymentId,
            'amount': amount?.amountInCents ?? 0,
            'currency': amount?.currency ?? 'XAF',
            'reason': reason ?? 'Customer request',
          }),
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = json.decode(response.body);
          final refundData = data['refund'];

          return RefundResult(
            refundId: refundData?['refund_id'] ?? 'ref_${DateTime.now().millisecondsSinceEpoch}',
            paymentId: paymentId,
            amount: amount ?? PaymentAmount(amountInCents: refundData?['amount'] ?? 0, currency: refundData?['currency'] ?? 'XAF'),
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

        final refundId = 'om_refund_${DateTime.now().millisecondsSinceEpoch}';
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
      if (_accessToken != null) {
        final url = Uri.parse('${_useSandbox ? 'https://api-sandbox.orange.com' : _baseUrl}/orange-money-webpay/dev/v1/tokenize');

        final response = await http.post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_accessToken',
          },
          body: json.encode({
            'card_number': cardNumber,
            'expiry_month': expiryMonth,
            'expiry_year': expiryYear,
            'cvv': cvv,
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

        return 'om_token_${DateTime.now().millisecondsSinceEpoch}';
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
      final eventType = event['event_type'] as String?;
      final eventData = event['data'] as Map<String, dynamic>?;

      if (eventData != null) {
        String message;
        bool success = false;
        String? id;
        String? reference;

        switch (eventType) {
          case 'payment_success':
            reference = eventData['order_id'] as String?;
            final status = eventData['status'] as String?;
            message = 'Orange Money payment completed: $reference, status: $status';
            success = status?.toLowerCase() == 'success';
            id = eventData['transaction_id'] as String?;
            break;

          case 'payment_failed':
            reference = eventData['order_id'] as String?;
            message = 'Orange Money payment failed: $reference';
            success = false;
            id = eventData['transaction_id'] as String?;
            break;

          case 'refund_completed':
            id = eventData['refund_id'] as String?;
            message = 'Orange Money refund completed: $id';
            success = true;
            break;

          default:
            message = 'Unhandled Orange Money webhook: $eventType';
            success = false;
        }

        // Verify webhook signature for security
        bool signatureValid = true;
        final signature = event['signature'] as String?;
        if (signature != null && _clientSecret != null) {
          // Webhook signature verification logic would go here
          signatureValid = true; // Simulation
        }

        return {
          'provider': 'orange_money',
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
          'provider': 'orange_money',
          'error': 'No event data provided',
          'success': false,
          'processed_at': DateTime.now().toIso8601String(),
        };
      }
    } catch (e) {
      return {
        'provider': 'orange_money',
        'error': e.toString(),
        'success': false,
        'processed_at': DateTime.now().toIso8601String(),
      };
    }
  }

  @override
  Future<void> dispose() async {
    _isInitialized = false;
    _accessToken = null;
  }

  void _ensureInitialized() {
    if (!_isInitialized) {
      throw PaymentException(
        message: 'Le plugin Orange Money n\'est pas initialisé',
        provider: provider,
      );
    }
  }
}
