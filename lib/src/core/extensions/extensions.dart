
// Enum of supported payment providers
enum PaymentProvider {
  stripe,
  paypal,
  flutterwave,
  wave,
  mtnMomo,
  orangeMoney,
  flooz,
  mixxByYas,
  paygate,
  cinetpay,
  semoa,
  bizao,
  fedapay,
  paystack,
  klarna,
}

// Extension for provider metadata
extension PaymentProviderMetadata on PaymentProvider {
  bool get supports3DS {
    switch (this) {
      case PaymentProvider.stripe:
      case PaymentProvider.flutterwave:
        return true;
      default:
        return false;
    }
  }

  bool get requiresClientSecret {
    switch (this) {
      case PaymentProvider.stripe:
        return true;
      default:
        return false;
    }
  }

  String get displayName {
    switch (this) {
      case PaymentProvider.stripe:
        return 'Stripe';
      case PaymentProvider.paypal:
        return 'PayPal';
      case PaymentProvider.flutterwave:
        return 'Flutterwave';
      case PaymentProvider.wave:
        return 'Wave';
      case PaymentProvider.mtnMomo:
        return 'MTN Mobile Money';
      case PaymentProvider.orangeMoney:
        return 'Orange Money';
      case PaymentProvider.flooz:
        return 'Flooz';
      case PaymentProvider.mixxByYas:
        return 'Mixx by Yas';
      case PaymentProvider.paygate:
        return 'PayGate';
      case PaymentProvider.cinetpay:
        return 'CinetPay';
      case PaymentProvider.semoa:
        return 'Semoa';
      case PaymentProvider.bizao:
        return 'Bizao';
      case PaymentProvider.fedapay:
        return 'FedaPay';
      case PaymentProvider.paystack:
        return 'PayStack';
      case PaymentProvider.klarna:
        return 'Klarna';
    }
  }
}



enum PaymentStatus {
  pending,
  processing,
  succeeded,
  failed,
  canceled,
  requiresAction,
}
