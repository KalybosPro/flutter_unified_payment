// ============================================================================
// UNIFIED PAYMENT CLIENT
// ============================================================================

import 'core/core.dart' as core;
import 'plugins/plugins.dart';

class PaymentClient {
  final core.PaymentProvider provider;
  late final core.PaymentProviderPlugin _plugin;

  PaymentClient({required this.provider}) {
    _plugin = _resolvePlugin(provider);
  }

  /// Resolves the appropriate plugin according to the provider
  core.PaymentProviderPlugin _resolvePlugin(core.PaymentProvider provider) {
    switch (provider) {
      case core.PaymentProvider.stripe:
        return StripePaymentPlugin();
      case core.PaymentProvider.flutterwave:
        return FlutterwavePaymentPlugin();
      case core.PaymentProvider.flooz:
        return FloozPaymentPlugin();
      case core.PaymentProvider.mixxByYas:
        return MixxByYasPaymentPlugin();
      case core.PaymentProvider.paygate:
        return PayGatePaymentPlugin();
      case core.PaymentProvider.cinetpay:
        return CinetPayPaymentPlugin();
      case core.PaymentProvider.semoa:
        return SemoaPaymentPlugin();
      default:
        throw UnimplementedError('Provider ${provider.displayName} not implemented');
    }
  }

  /// Initializes the client
  Future<void> initialize({
    required String publicKey,
    String? secretKey,
    Map<String, dynamic>? additionalConfig,
  }) async {
    await _plugin.initialize(
      publicKey: publicKey,
      secretKey: secretKey,
      additionalConfig: additionalConfig,
    );
  }

  /// Creates a payment intent
  Future<core.PaymentIntentResult> createPaymentIntent({
    required core.PaymentAmount amount,
    required String customerId,
    Map<String, dynamic>? metadata,
  }) async {
    return await _plugin.createPaymentIntent(
      amount: amount,
      customerId: customerId,
      metadata: metadata,
    );
  }

  /// Confirms the payment
  Future<core.PaymentResult> confirmPayment({
    required String paymentIntentClientSecret,
    Map<String, dynamic>? paymentMethodData,
  }) async {
    return await _plugin.confirmPayment(
      paymentIntentClientSecret: paymentIntentClientSecret,
      paymentMethodData: paymentMethodData,
    );
  }

  /// Retrieves the status of a payment
  Future<core.PaymentStatus> fetchPaymentStatus(String paymentId) async {
    return await _plugin.fetchPaymentStatus(paymentId);
  }

  /// Refunds a payment
  Future<core.RefundResult> refundPayment({
    required String paymentId,
    core.PaymentAmount? amount,
    String? reason,
  }) async {
    return await _plugin.refundPayment(
      paymentId: paymentId,
      amount: amount,
      reason: reason,
    );
  }

  /// Tokenizes a card
  Future<String> tokenizeCard({
    required String cardNumber,
    required String expiryMonth,
    required String expiryYear,
    required String cvv,
  }) async {
    return await _plugin.tokenizeCard(
      cardNumber: cardNumber,
      expiryMonth: expiryMonth,
      expiryYear: expiryYear,
      cvv: cvv,
    );
  }

  /// Releases the resources
  Future<void> dispose() async {
    await _plugin.dispose();
  }

  /// Retrieves the provider's metadata
  core.PaymentProvider get currentProvider => provider;
  bool get supports3DS => provider.supports3DS;
  bool get requiresClientSecret => provider.requiresClientSecret;
}
