// ============================================================================
// KLARNA IMPLEMENTATION
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

class KlarnaPaymentPlugin implements PaymentProviderPlugin {
  final Logger _logger = Logger('KlarnaPaymentPlugin');

  @override
  PaymentProvider get provider => PaymentProvider.klarna;

  static const String _baseUrl = 'https://api.klarna.com';
  static const String _sandboxBaseUrl = 'https://api.playground.klarna.com';

  String? _username;
  String? _password;
  bool _isInitialized = false;
  bool _useSandbox = false;

  @override
  Future<void> initialize({
    required String publicKey,
    String? secretKey,
    Map<String, dynamic>? additionalConfig,
  }) async {
    try {
      _username = publicKey; // Klarna uses username/password for authentication
      _password = secretKey;
      _useSandbox = additionalConfig?['useSandbox'] as bool? ?? false;

      if (_username == null || _username!.isEmpty || _password == null || _password!.isEmpty) {
        throw PaymentInitializationException(
          message: 'Klarna username and password are required',
          provider: provider,
        );
      }

      _isInitialized = true;
      _logger.info('Klarna initialized successfully with mode: ${_useSandbox ? 'sandbox' : 'production'}');
    } catch (e) {
      throw PaymentInitializationException(
        message: 'Failed to initialize Klarna: $e',
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
      final orderId = 'klarna_${DateTime.now().millisecondsSinceEpoch}_${customerId.hashCode.abs()}';

      // Include client information in metadata if not provided
      final finalMetadata = {
        ...?metadata,
        'customer_id': customerId,
        'order_id': orderId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      return PaymentIntentResult(
        id: orderId,
        clientSecret: orderId,
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

    try {
      if (_username == null || _password == null) {
        throw PaymentProcessingException(
          message: 'Username and password are required for payment confirmation',
          provider: provider,
        );
      }

      final baseUrl = _useSandbox ? _sandboxBaseUrl : _baseUrl;
      final url = Uri.parse('$baseUrl/payments/v1/sessions');

      // Prepare order lines
      final orderLines = paymentMethodData?['orderLines'] as List<dynamic>? ?? [
        {
          'name': 'Payment',
          'quantity': 1,
          'unit_price': paymentMethodData?['amount'] ?? 10000, // Amount in minor units
          'total_amount': paymentMethodData?['amount'] ?? 10000,
          'tax_rate': 0,
          'total_tax_amount': 0,
        }
      ];

      final payload = {
        'purchase_country': paymentMethodData?['purchaseCountry'] ?? 'US',
        'purchase_currency': paymentMethodData?['currency'] ?? 'USD',
        'locale': paymentMethodData?['locale'] ?? 'en-US',
        'order_amount': paymentMethodData?['amount'] ?? 10000,
        'order_tax_amount': 0,
        'order_lines': orderLines,
        'merchant_urls': {
          'terms': paymentMethodData?['termsUrl'] ?? 'https://example.com/terms',
          'checkout': paymentMethodData?['checkoutUrl'] ?? 'https://example.com/checkout',
          'confirmation': paymentMethodData?['confirmationUrl'] ?? 'https://example.com/confirmation',
          'push': paymentMethodData?['pushUrl'] ?? 'https://example.com/push',
        },
        'merchant_reference1': paymentIntentClientSecret,
        'customer': {
          'date_of_birth': paymentMethodData?['dateOfBirth'],
          'gender': paymentMethodData?['gender'],
          'organization_entity_type': paymentMethodData?['organizationEntityType'],
          'organization_registration_id': paymentMethodData?['organizationRegistrationId'],
          'type': paymentMethodData?['customerType'] ?? 'person',
        },
        'billing_address': {
          'given_name': paymentMethodData?['billingGivenName'] ?? 'John',
          'family_name': paymentMethodData?['billingFamilyName'] ?? 'Doe',
          'email': paymentMethodData?['billingEmail'] ?? 'john.doe@example.com',
          'street_address': paymentMethodData?['billingStreetAddress'] ?? '123 Main St',
          'postal_code': paymentMethodData?['billingPostalCode'] ?? '12345',
          'city': paymentMethodData?['billingCity'] ?? 'New York',
          'country': paymentMethodData?['billingCountry'] ?? 'US',
        },
      };

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Basic ${base64Encode(utf8.encode('$_username:$_password'))}',
        },
        body: json.encode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        final sessionId = data['session_id'] as String?;

        return PaymentResult(
          paymentId: sessionId ?? paymentIntentClientSecret,
          status: PaymentStatus.processing,
          errorMessage: null,
          errorCode: null,
          metadata: {
            'session_id': sessionId,
            'client_token': data['client_token'],
            'payment_method_categories': data['payment_method_categories'],
          },
        );
      } else {
        return PaymentResult(
          paymentId: paymentIntentClientSecret,
          status: PaymentStatus.failed,
          errorMessage: 'Failed to create Klarna session: ${response.body}',
          errorCode: 'session_creation_failed',
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

    try {
      if (_username != null && _password != null) {
        final baseUrl = _useSandbox ? _sandboxBaseUrl : _baseUrl;
        final response = await http.get(
          Uri.parse('$baseUrl/payments/v1/authorizations/$paymentId'),
          headers: {
            'Authorization': 'Basic ${base64Encode(utf8.encode('$_username:$_password'))}',
          },
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final status = data['order_status'] as String?;
          return _convertKlarnaStatus(status);
        } else {
          _logger.warning('Failed to fetch Klarna order status: ${response.body}');
          return PaymentStatus.failed;
        }
      }

      // Fallback for development/tests
      await Future.delayed(const Duration(milliseconds: 500));

      // Simulate different statuses for demonstration
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

  PaymentStatus _convertKlarnaStatus(String? status) {
    switch (status?.toLowerCase()) {
      case 'authorized':
        return PaymentStatus.succeeded;
      case 'pending':
        return PaymentStatus.pending;
      case 'processing':
        return PaymentStatus.processing;
      case 'cancelled':
        return PaymentStatus.canceled;
      case 'expired':
        return PaymentStatus.failed;
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
      if (_username != null && _password != null) {
        final baseUrl = _useSandbox ? _sandboxBaseUrl : _baseUrl;
        final response = await http.post(
          Uri.parse('$baseUrl/ordermanagement/v2/orders/$paymentId/refunds'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Basic ${base64Encode(utf8.encode('$_username:$_password'))}',
          },
          body: json.encode({
            'refunded_amount': amount?.amountInCents ?? 10000,
            'description': reason ?? 'Customer refund',
          }),
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = json.decode(response.body);
          final refundId = data['refund_id'] as String?;

          return RefundResult(
            refundId: refundId ?? 'klarna_refund_${DateTime.now().millisecondsSinceEpoch}',
            paymentId: paymentId,
            amount: amount ?? PaymentAmount(amountInCents: 10000, currency: 'USD'),
            isSuccessful: true,
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

        final refundId = 'klarna_refund_${DateTime.now().millisecondsSinceEpoch}';
        final timestamp = DateTime.now().millisecondsSinceEpoch;

        // Simulate occasional failure
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
          amount: amount ?? PaymentAmount(amountInCents: 10000, currency: 'USD'),
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
    // Klarna doesn't typically tokenize cards directly as it's primarily a BNPL service
    // This method is not applicable for Klarna
    throw PaymentProcessingException(
      message: 'Card tokenization is not supported by Klarna',
      provider: provider,
    );
  }

  @override
  Future<Map<String, dynamic>> handleWebhookEvent(Map<String, dynamic> event) async {
    try {
      final eventType = event['event_type'] as String?;
      final orderId = event['order_id'] as String?;

      String message;
      bool success = false;
      String? id;
      String? reference;

      switch (eventType) {
        case 'ORDER_AUTHORIZED':
          reference = orderId;
          message = 'Klarna order authorized: $orderId';
          success = true;
          id = orderId;
          break;

        case 'ORDER_CANCELLED':
          reference = orderId;
          message = 'Klarna order cancelled: $orderId';
          success = false;
          id = orderId;
          break;

        case 'FRAUD_RISK_ACCEPTED':
          reference = orderId;
          message = 'Klarna fraud risk accepted: $orderId';
          success = true;
          id = orderId;
          break;

        case 'FRAUD_RISK_REJECTED':
          reference = orderId;
          message = 'Klarna fraud risk rejected: $orderId';
          success = false;
          id = orderId;
          break;

        case 'FRAUD_RISK_UNKNOWN':
          reference = orderId;
          message = 'Klarna fraud risk unknown: $orderId';
          success = false;
          id = orderId;
          break;

        default:
          message = 'Unhandled Klarna webhook: $eventType';
          success = false;
      }

      return {
        'provider': 'klarna',
        'event_type': eventType,
        'success': success,
        'message': message,
        'id': id,
        'reference': reference,
        'event_data': event,
        'processed_at': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {
        'provider': 'klarna',
        'error': e.toString(),
        'success': false,
        'processed_at': DateTime.now().toIso8601String(),
      };
    }
  }

  @override
  Future<void> dispose() async {
    _isInitialized = false;
    _logger.info('Klarna plugin disposed');
  }

  void _ensureInitialized() {
    if (!_isInitialized) {
      throw PaymentException(
        message: 'Klarna plugin is not initialized. Call initialize() first.',
        provider: provider,
      );
    }
  }
}
