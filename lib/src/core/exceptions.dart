// ============================================================================
// EXCEPTIONS
// ============================================================================

import 'core.dart' show PaymentProvider;

class PaymentException implements Exception {
  final String message;
  final String? code;
  final PaymentProvider? provider;

  PaymentException({
    required this.message,
    this.code,
    this.provider,
  });

  @override
  String toString() => 'PaymentException: $message (code: $code, provider: $provider)';
}

class PaymentInitializationException extends PaymentException {
  PaymentInitializationException({
    required super.message,
    super.code,
    super.provider,
  });
}

class PaymentProcessingException extends PaymentException {
  PaymentProcessingException({
    required super.message,
    super.code,
    super.provider,
  });
}