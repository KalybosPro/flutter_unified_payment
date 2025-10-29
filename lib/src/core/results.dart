import 'core.dart' show PaymentAmount, PaymentStatus;

class PaymentIntentResult {
  final String id;
  final String clientSecret;
  final PaymentStatus status;
  final PaymentAmount amount;
  final Map<String, dynamic>? metadata;

  PaymentIntentResult({
    required this.id,
    required this.clientSecret,
    required this.status,
    required this.amount,
    this.metadata,
  });
}

class PaymentResult {
  final String paymentId;
  final PaymentStatus status;
  final String? errorMessage;
  final String? errorCode;
  final Map<String, dynamic>? metadata;

  PaymentResult({
    required this.paymentId,
    required this.status,
    this.errorMessage,
    this.errorCode,
    this.metadata,
  });

  bool get isSuccessful => status == PaymentStatus.succeeded;
  bool get requiresAction => status == PaymentStatus.requiresAction;
  bool get hasFailed => status == PaymentStatus.failed;
}

class RefundResult {
  final String refundId;
  final String paymentId;
  final PaymentAmount amount;
  final bool isSuccessful;
  final String? errorMessage;

  RefundResult({
    required this.refundId,
    required this.paymentId,
    required this.amount,
    required this.isSuccessful,
    this.errorMessage,
  });
}
