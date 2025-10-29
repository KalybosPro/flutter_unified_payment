// ============================================================================
// MODÈLES DE DONNÉES
// ============================================================================

class PaymentAmount {
  final int amountInCents;
  final String currency;

  PaymentAmount({
    required this.amountInCents,
    required this.currency,
  });

  double get amountInMajorUnits => amountInCents / 100.0;

  Map<String, dynamic> toJson() => {
        'amount': amountInCents,
        'currency': currency,
      };
}