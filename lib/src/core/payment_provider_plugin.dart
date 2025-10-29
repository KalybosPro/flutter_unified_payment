// ============================================================================
// PLUGINS INTERFACE
// ============================================================================

import 'core.dart'
    show
        PaymentProvider,
        PaymentAmount,
        PaymentIntentResult,
        PaymentResult,
        PaymentStatus,
        RefundResult;

abstract class PaymentProviderPlugin {
  PaymentProvider get provider;

  /// Initializes the plugin with the necessary API keys
  Future<void> initialize({
    required String publicKey,
    String? secretKey,
    Map<String, dynamic>? additionalConfig,
  });

  /// Creates a payment intent
  Future<PaymentIntentResult> createPaymentIntent({
    required PaymentAmount amount,
    required String customerId,
    Map<String, dynamic>? metadata,
  });

  /// Confirms and processes the payment
  Future<PaymentResult> confirmPayment({
    required String paymentIntentClientSecret,
    Map<String, dynamic>? paymentMethodData,
  });

  /// Retrieves the status of a payment
  Future<PaymentStatus> fetchPaymentStatus(String paymentId);

  /// Refunds a payment
  Future<RefundResult> refundPayment({
    required String paymentId,
    PaymentAmount? amount, // If null, full refund
    String? reason,
  });

  /// Tokenizes a card (for reuse)
  Future<String> tokenizeCard({
    required String cardNumber,
    required String expiryMonth,
    required String expiryYear,
    required String cvv,
  });

  /// Handles webhooks (usually on server side)
  Future<Map<String, dynamic>> handleWebhookEvent(Map<String, dynamic> event);

  /// Releases the resources
  Future<void> dispose();
}
