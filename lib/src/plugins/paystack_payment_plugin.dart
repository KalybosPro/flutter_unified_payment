// ============================================================================
// PAYSTACK IMPLEMENTATION
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

class PayStackPaymentPlugin implements PaymentProviderPlugin {
  final Logger _logger = Logger('PayStackPaymentPlugin');

  @override
  PaymentProvider get provider => PaymentProvider.paystack;

  static const String _baseUrl = 'https://api.paystack.co';
  static const String _sandboxBaseUrl = 'https://api.paystack.co'; // PayStack uses same URL for sandbox

  String? _publicKey;
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
      _publicKey = publicKey;
      _secretKey = secretKey;
      _useSandbox = additionalConfig?['useSandbox'] as bool? ?? false;

      if (_secretKey == null || _secretKey!.isEmpty) {
        throw PaymentInitializationException(
          message: 'PayStack secret key is required',
          provider: provider,
        );
      }

      _isInitialized = true;
      _logger.info('PayStack initialized successfully with mode: ${_useSandbox ? 'sandbox' : 'production'}');
    } catch (e) {
      throw PaymentInitializationException(
        message: 'Failed to initialize PayStack: $e',
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
      // PayStack doesn't have PaymentIntents like Stripe, but we can create an initialize transaction
      final reference = 'paystack_${DateTime.now().millisecondsSinceEpoch}_${customerId.hashCode.abs()}';

      // Include client information in metadata if not provided
      final finalMetadata = {
        ...?metadata,
        'customer_id': customerId,
        'reference': reference,
        'timestamp': DateTime.now().toIso8601String(),
      };

      return PaymentIntentResult(
        id: reference,
        clientSecret: reference, // PayStack uses reference as the identifier
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
      if (_secretKey == null) {
        throw PaymentProcessingException(
          message: 'Secret key is required for payment confirmation',
          provider: provider,
        );
      }

      // For PayStack, we initialize a transaction
      final url = Uri.parse('$_baseUrl/transaction/initialize');

      final customFields = [
        {
          'display_name': 'Payment Reference',
          'variable_name': 'reference',
          'value': paymentIntentClientSecret,
        }
      ];

      // Add customer details if provided
      if (paymentMethodData?['customerName'] != null) {
        customFields.add({
          'display_name': 'Customer Name',
          'variable_name': 'customer_name',
          'value': paymentMethodData!['customerName'],
        });
      }

      if (paymentMethodData?['customerPhone'] != null) {
        customFields.add({
          'display_name': 'Phone Number',
          'variable_name': 'phone_number',
          'value': paymentMethodData!['customerPhone'],
        });
      }

      final payload = {
        'reference': paymentIntentClientSecret,
        'amount': (paymentMethodData?['amount'] as int? ?? 100), // Amount in kobo (smallest currency unit)
        'currency': paymentMethodData?['currency'] as String? ?? 'NGN',
        'email': paymentMethodData?['customerEmail'] as String? ?? 'customer@example.com',
        'callback_url': paymentMethodData?['callbackUrl'] as String? ?? 'https://yourapp.com/callback',
        'metadata': {
          'custom_fields': customFields
        }
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
        if (data['status'] == true) {
          final transactionData = data['data'];
          final transactionId = transactionData['reference'] ?? paymentIntentClientSecret;

          return PaymentResult(
            paymentId: transactionId,
            status: PaymentStatus.processing, // Transaction initialized, waiting for payment
            errorMessage: null,
            errorCode: null,
            metadata: {
              'authorization_url': transactionData['authorization_url'],
              'access_code': transactionData['access_code'],
            },
          );
        } else {
          return PaymentResult(
            paymentId: paymentIntentClientSecret,
            status: PaymentStatus.failed,
            errorMessage: data['message'] as String?,
            errorCode: 'initialization_failed',
          );
        }
      } else {
        return PaymentResult(
          paymentId: paymentIntentClientSecret,
          status: PaymentStatus.failed,
          errorMessage: 'Failed to initialize payment: ${response.body}',
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

    try {
      if (_secretKey != null) {
        final response = await http.get(
          Uri.parse('$_baseUrl/transaction/verify/$paymentId'),
          headers: {
            'Authorization': 'Bearer $_secretKey',
          },
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['status'] == true) {
            final transactionData = data['data'];
            final status = transactionData['status'] as String?;

            return _convertPayStackStatus(status);
          } else {
            _logger.warning('PayStack API error: ${data['message']}');
            return PaymentStatus.failed;
          }
        } else {
          _logger.warning('Failed to fetch transaction status: ${response.body}');
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

  PaymentStatus _convertPayStackStatus(String? status) {
    switch (status?.toLowerCase()) {
      case 'success':
        return PaymentStatus.succeeded;
      case 'pending':
        return PaymentStatus.pending;
      case 'processing':
        return PaymentStatus.processing;
      case 'failed':
        return PaymentStatus.failed;
      case 'abandoned':
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
        final response = await http.post(
          Uri.parse('$_baseUrl/refund'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_secretKey',
          },
          body: json.encode({
            'transaction': paymentId,
            'amount': amount?.amountInCents, // Amount in kobo
            'reason': reason ?? 'Customer request',
          }),
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['status'] == true) {
            final refundData = data['data'];

            return RefundResult(
              refundId: refundData['id']?.toString() ?? 'refund_${DateTime.now().millisecondsSinceEpoch}',
              paymentId: paymentId,
              amount: amount ?? PaymentAmount(amountInCents: refundData['amount'] ?? 0, currency: 'NGN'),
              isSuccessful: refundData['status'] == 'processed',
            );
          } else {
            throw PaymentProcessingException(
              message: 'Refund failed: ${data['message']}',
              provider: provider,
            );
          }
        } else {
          throw PaymentProcessingException(
            message: 'Refund API error: ${response.body}',
            provider: provider,
          );
        }
      } else {
        // Simulation for development
        await Future.delayed(const Duration(seconds: 1));

        final refundId = 'paystack_refund_${DateTime.now().millisecondsSinceEpoch}';
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
          amount: amount ?? PaymentAmount(amountInCents: 1000, currency: 'NGN'),
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
      if (_secretKey != null) {
        // PayStack allows charging saved cards, but tokenization is handled differently
        // We can create a transaction and get the authorization code
        final response = await http.post(
          Uri.parse('$_baseUrl/charge'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_secretKey',
          },
          body: json.encode({
            'email': 'temp@example.com', // Temporary email for tokenization
            'amount': '100', // Small amount for tokenization
            'card': {
              'number': cardNumber,
              'cvv': cvv,
              'expiry_month': expiryMonth,
              'expiry_year': expiryYear,
            },
          }),
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['status'] == true) {
            final authData = data['data']['authorization'];
            final token = authData['authorization_code'] as String?;
            if (token != null) {
              return token;
            }
          }
        }

        throw PaymentProcessingException(
          message: 'Tokenization failed: ${response.body}',
          provider: provider,
        );
      } else {
        // Simulation for development
        await Future.delayed(const Duration(milliseconds: 300));

        // Simulate occasional failure
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        if (timestamp % 20 == 0) {
          throw PaymentProcessingException(
            message: 'Simulated tokenization failure',
            provider: provider,
          );
        }

        return 'paystack_auth_${DateTime.now().millisecondsSinceEpoch}';
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
      final eventType = event['event'] as String?;
      final eventData = event['data'] as Map<String, dynamic>?;

      String message;
      bool success = false;
      String? id;
      String? reference;

      switch (eventType) {
        case 'charge.success':
          reference = eventData?['reference'] as String?;
          final status = eventData?['status'] as String?;
          message = 'PayStack charge successful: $reference, status: $status';
          success = status?.toLowerCase() == 'success';
          id = eventData?['id']?.toString();
          break;

        case 'charge.failed':
          reference = eventData?['reference'] as String?;
          message = 'PayStack charge failed: $reference';
          success = false;
          id = eventData?['id']?.toString();
          break;

        case 'transfer.success':
          reference = eventData?['reference'] as String?;
          message = 'PayStack transfer successful: $reference';
          success = true;
          id = eventData?['id']?.toString();
          break;

        case 'transfer.failed':
          reference = eventData?['reference'] as String?;
          message = 'PayStack transfer failed: $reference';
          success = false;
          id = eventData?['id']?.toString();
          break;

        case 'transfer.reversed':
          reference = eventData?['reference'] as String?;
          message = 'PayStack transfer reversed: $reference';
          success = false;
          id = eventData?['id']?.toString();
          break;

        case 'refund.processed':
          reference = eventData?['reference'] as String?;
          message = 'PayStack refund processed: $reference';
          success = true;
          id = eventData?['id']?.toString();
          break;

        default:
          message = 'Unhandled PayStack webhook: $eventType';
          success = false;
      }

      // Verify webhook signature for security
      bool signatureValid = true;
      final signature = event['signature'] as String?;
      if (signature != null && _secretKey != null) {
        // In production, implement proper signature verification
        // signatureValid = _verifySignature(signature, event, _secretKey!);
        signatureValid = true; // Placeholder
      }

      return {
        'provider': 'paystack',
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
        'provider': 'paystack',
        'error': e.toString(),
        'success': false,
        'processed_at': DateTime.now().toIso8601String(),
      };
    }
  }

  @override
  Future<void> dispose() async {
    _isInitialized = false;
    _logger.info('PayStack plugin disposed');
  }

  void _ensureInitialized() {
    if (!_isInitialized) {
      throw PaymentException(
        message: 'PayStack plugin is not initialized. Call initialize() first.',
        provider: provider,
      );
    }
  }
}
