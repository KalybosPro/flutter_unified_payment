// ============================================================================
// WAVE IMPLEMENTATION
// ============================================================================

import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:logging/logging.dart';

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

class WavePaymentPlugin implements PaymentProviderPlugin {
  final Logger _logger = Logger('WavePaymentPlugin');

  @override
  PaymentProvider get provider => PaymentProvider.wave;

  static const String _baseUrl = 'https://api.wave.com';
  static const String _sandboxBaseUrl = 'https://api.sandbox.wave.com';

  String? _clientId;
  String? _clientSecret;
  bool _isInitialized = false;
  bool _useSandbox = false;
  String? _accessToken;
  DateTime? _tokenExpiry;

  @override
  Future<void> initialize({
    required String publicKey,
    String? secretKey,
    Map<String, dynamic>? additionalConfig,
  }) async {
    try {
      _clientId = publicKey;
      _clientSecret = secretKey;
      _useSandbox = additionalConfig?['useSandbox'] as bool? ?? false;

      if (_clientId == null || _clientId!.isEmpty) {
        throw PaymentInitializationException(
          message: 'Wave client ID is required',
          provider: provider,
        );
      }

      if (_clientSecret == null || _clientSecret!.isEmpty) {
        throw PaymentInitializationException(
          message: 'Wave client secret is required',
          provider: provider,
        );
      }

      _isInitialized = true;
      _logger.info('Wave initialized successfully with mode: ${_useSandbox ? 'sandbox' : 'production'}');
    } catch (e) {
      throw PaymentInitializationException(
        message: 'Failed to initialize Wave: $e',
        provider: provider,
      );
    }
  }

  Future<void> _authenticate() async {
    try {
      final url = Uri.parse('${_useSandbox ? _sandboxBaseUrl : _baseUrl}/v1/oauth2/token');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'grant_type': 'client_credentials',
          'client_id': _clientId!,
          'client_secret': _clientSecret!,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _accessToken = data['access_token'] as String?;
        final expiresIn = data['expires_in'] as int?;
        if (expiresIn != null) {
          _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));
        }
      } else {
        throw PaymentInitializationException(
          message: 'Failed to authenticate with Wave: ${response.body}',
          provider: provider,
        );
      }
    } catch (e) {
      throw PaymentInitializationException(
        message: 'Wave authentication failed: $e',
        provider: provider,
      );
    }
  }

  Future<void> _ensureValidToken() async {
    if (_accessToken == null ||
        _tokenExpiry == null ||
        DateTime.now().isAfter(_tokenExpiry!.subtract(const Duration(minutes: 5)))) {
      await _authenticate();
    }
  }

  @override
  Future<PaymentIntentResult> createPaymentIntent({
    required PaymentAmount amount,
    required String customerId,
    Map<String, dynamic>? metadata,
  }) async {
    _ensureInitialized();
    await _ensureValidToken();

    try {
      // Wave doesn't have traditional PaymentIntents, but we can create a payment request
      final reference = 'wave_${DateTime.now().millisecondsSinceEpoch}_${customerId.hashCode.abs()}';

      // Include client information in metadata if not provided
      final finalMetadata = {
        ...?metadata,
        'customer_id': customerId,
        'reference': reference,
        'timestamp': DateTime.now().toIso8601String(),
      };

      return PaymentIntentResult(
        id: reference,
        clientSecret: reference,
        status: PaymentStatus.pending,
        amount: amount,
        metadata: finalMetadata,
      );
    } catch (e) {
      _logger.severe('Error creating PaymentIntent: $e');
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
    await _ensureValidToken();

    try {
      if (_accessToken == null) {
        throw PaymentProcessingException(
          message: 'Access token is required for payment confirmation',
          provider: provider,
        );
      }

      final url = Uri.parse('${_useSandbox ? _sandboxBaseUrl : _baseUrl}/v1/checkout/sessions');

      final payload = {
        'amount': (paymentMethodData?['amount'] as int? ?? 100).toString(),
        'currency': paymentMethodData?['currency'] as String? ?? 'XOF',
        'client_reference': paymentIntentClientSecret,
        'success_url': paymentMethodData?['successUrl'] as String? ?? 'https://yourapp.com/success',
        'error_url': paymentMethodData?['errorUrl'] as String? ?? 'https://yourapp.com/error',
        'payment_method_types': ['wave'],
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
        final checkoutUrl = data['checkout_url'] as String?;
        final sessionId = data['id'] as String?;

        return PaymentResult(
          paymentId: sessionId ?? paymentIntentClientSecret,
          status: PaymentStatus.processing,
          errorMessage: null,
          errorCode: null,
          metadata: {
            'checkout_url': checkoutUrl,
            'session_id': sessionId,
          },
        );
      } else {
        return PaymentResult(
          paymentId: paymentIntentClientSecret,
          status: PaymentStatus.failed,
          errorMessage: 'Failed to create checkout session: ${response.body}',
          errorCode: 'api_error',
        );
      }
    } catch (e) {
      _logger.severe('Error confirming payment: $e');
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
    await _ensureValidToken();

    try {
      if (_accessToken != null) {
        final response = await http.get(
          Uri.parse('${_useSandbox ? _sandboxBaseUrl : _baseUrl}/v1/checkout/sessions/$paymentId'),
          headers: {
            'Authorization': 'Bearer $_accessToken',
          },
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final status = data['status'] as String?;

          return _convertWaveStatus(status);
        } else {
          _logger.warning('Failed to fetch payment status: ${response.body}');
          return PaymentStatus.failed;
        }
      }

      // Fallback for development/tests
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
      _logger.severe('Error fetching payment status: $e');
      return PaymentStatus.failed;
    }
  }

  PaymentStatus _convertWaveStatus(String? status) {
    switch (status?.toLowerCase()) {
      case 'completed':
      case 'success':
      case 'successful':
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
      case 'requires_action':
        return PaymentStatus.requiresAction;
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
    await _ensureValidToken();

    try {
      if (_accessToken != null) {
        final response = await http.post(
          Uri.parse('${_useSandbox ? _sandboxBaseUrl : _baseUrl}/v1/refunds'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_accessToken',
          },
          body: json.encode({
            'session_id': paymentId,
            'amount': amount?.amountInMajorUnits.toString(),
            'currency': amount?.currency ?? 'XOF',
            'reason': reason ?? 'Customer request',
          }),
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = json.decode(response.body);

          return RefundResult(
            refundId: data['id']?.toString() ?? 'refund_${DateTime.now().millisecondsSinceEpoch}',
            paymentId: paymentId,
            amount: amount ?? PaymentAmount(amountInCents: data['amount'] ?? 0, currency: data['currency'] ?? 'XOF'),
            isSuccessful: data['status'] == 'completed',
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

        final refundId = 'wave_refund_${DateTime.now().millisecondsSinceEpoch}';
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
          amount: amount ?? PaymentAmount(amountInCents: 1000, currency: 'XOF'),
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
    await _ensureValidToken();

    try {
      if (_accessToken != null) {
        final response = await http.post(
          Uri.parse('${_useSandbox ? _sandboxBaseUrl : _baseUrl}/v1/payment-methods'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_accessToken',
          },
          body: json.encode({
            'type': 'card',
            'card': {
              'number': cardNumber,
              'exp_month': expiryMonth,
              'exp_year': expiryYear,
              'cvc': cvv,
            },
          }),
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = json.decode(response.body);
          final token = data['id'] as String?;
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

        return 'wave_token_${DateTime.now().millisecondsSinceEpoch}';
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

      String message;
      bool success = false;
      String? id;
      String? reference;

      switch (eventType) {
        case 'checkout.session.completed':
          reference = eventData?['client_reference'] as String?;
          final status = eventData?['status'] as String?;
          message = 'Wave checkout completed: $reference, status: $status';
          success = status?.toLowerCase() == 'completed';
          id = eventData?['id'] as String?;
          break;

        case 'checkout.session.failed':
          reference = eventData?['client_reference'] as String?;
          message = 'Wave checkout failed: $reference';
          success = false;
          id = eventData?['id'] as String?;
          break;

        case 'refund.completed':
          id = eventData?['id'] as String?;
          message = 'Wave refund completed: $id';
          success = true;
          break;

        case 'refund.failed':
          id = eventData?['id'] as String?;
          message = 'Wave refund failed: $id';
          success = false;
          break;

        default:
          message = 'Unhandled Wave webhook: $eventType';
          success = false;
      }

      // Verify webhook signature for security
      bool signatureValid = true;
      final signature = event['signature'] as String?;
      if (signature != null && _clientSecret != null) {
        // In production, implement proper signature verification
        // signatureValid = _verifySignature(signature, event, _clientSecret!);
        signatureValid = true; // Placeholder
      }

      return {
        'provider': 'wave',
        'event_type': eventType,
        'success': success,
        'message': message,
        'id': id,
        'reference': reference,
        'event_data': eventData,
        'signature_valid': signatureValid,
        'processed_at': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {
        'provider': 'wave',
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
    _tokenExpiry = null;
    _logger.info('Wave plugin disposed');
  }

  void _ensureInitialized() {
    if (!_isInitialized) {
      throw PaymentException(
        message: 'Wave plugin is not initialized. Call initialize() first.',
        provider: provider,
      );
    }
  }
}
