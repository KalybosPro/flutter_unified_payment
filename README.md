# Flutter Unified Payment System

A unified payment system for Flutter that allows easy integration of multiple payment providers into your mobile application.

[![Pub Version](https://img.shields.io/pub/v/flutter_unified_payment)](https://pub.dev/packages/flutter_unified_payment)

## 🎯 Description

This library provides a unified interface for integrating multiple payment providers into Flutter applications. It supports both international payment solutions (Stripe, PayPal) and African payments (Flutterwave, MTN Money, Orange Money, Flooz, CinetPay, etc.).

### ✨ Key Features

- **Unified API**: Single interface for all payment providers
- **Multi-provider support**: Stripe, Flutterwave, PayGate, Flooz, CinetPay, Semoa, Mixx by Yas
- **Enhanced security**: Secure API key and token management
- **State management**: Complete payment status tracking
- **Webhook support**: Automatic payment notification processing
- **Extensible architecture**: Easy addition of new providers

## 🚀 Installation

Add this line to your `pubspec.yaml` file:

```yaml
dependencies:
  flutter_unified_payment: ^0.0.1
```

Then run:
```bash
flutter pub get
```

### Additional Dependencies

The library requires certain dependencies based on the providers used:

```yaml
dependencies:
  http: ^1.2.0
  flutter_stripe: ^10.0.0  # Only for Stripe
```

## 📋 Requirements

### Android
- **minSdkVersion**: 21
- **Permissions**:
  ```xml
  <!-- android/app/src/main/AndroidManifest.xml -->
  <uses-permission android:name="android.permission.INTERNET" />
  <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
  ```

### iOS
- **iOS 11.0** minimum
- In `ios/Runner/Info.plist`:
  ```xml
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
  </dict>
  ```

## 🔧 Basic Usage

### 1. Import

```dart
import 'package:flutter_unified_payment/flutter_unified_payment.dart';
```

### 2. Client Initialization

```dart
// Example with Stripe
final paymentClient = PaymentClient(provider: PaymentProvider.stripe);

// Initialize with API keys
await paymentClient.initialize(
  publicKey: 'pk_test_xxxxx',
  secretKey: 'sk_test_xxxxx',
  additionalConfig: {
    'backendUrl': 'https://your-backend.com/api',
  },
);
```

### 3. Create Payment Intent

```dart
final paymentIntent = await paymentClient.createPaymentIntent(
  amount: PaymentAmount(amountInCents: 5000, currency: 'USD'), // $50.00
  customerId: 'customer_123',
  metadata: {
    'order_id': 'order_456',
    'description': 'Product purchase',
  },
);

print('Intent created: ${paymentIntent.id}');
```

### 4. Confirm Payment

```dart
final result = await paymentClient.confirmPayment(
  paymentIntentClientSecret: paymentIntent.clientSecret,
  paymentMethodData: {
    'type': 'card',
    'card': {
      'number': '4242424242424242',
      'exp_month': 12,
      'exp_year': 2025,
      'cvc': '123',
    },
  },
);

if (result.isSuccessful) {
  print('✅ Payment successful: ${result.paymentId}');
} else {
  print('❌ Payment failed: ${result.errorMessage}');
}
```

## 🎨 Complete Examples

### Payment with Stripe

```dart
import 'package:flutter_unified_payment/flutter_unified_payment.dart';

class StripePaymentService {
  late final PaymentClient _client;

  Future<void> initialize() async {
    _client = PaymentClient(provider: PaymentProvider.stripe);

    await _client.initialize(
      publicKey: 'pk_test_your_public_key',
      secretKey: 'sk_test_your_secret_key',
      additionalConfig: {
        'backendUrl': 'https://api.yourserver.com',
      },
    );
  }

  Future<PaymentResult> processPayment({
    required int amountInCents,
    required String customerId,
  }) async {
    try {
      // 1. Create payment intent
      final intent = await _client.createPaymentIntent(
        amount: PaymentAmount(amountInCents: amountInCents, currency: 'USD'),
        customerId: customerId,
      );

      // 2. Confirm with card data
      final result = await _client.confirmPayment(
        paymentIntentClientSecret: intent.clientSecret,
        paymentMethodData: {
          'type': 'card',
          // Here you would collect user's card data
        },
      );

      return result;
    } catch (e) {
      return PaymentResult(
        paymentId: 'error',
        status: PaymentStatus.failed,
        errorMessage: e.toString(),
      );
    }
  }
}
```

### African Mobile Payment (Flooz)

```dart
class AfricanPaymentService {
  late final PaymentClient _floozClient;

  Future<void> initializeFlooz() async {
    _floozClient = PaymentClient(provider: PaymentProvider.flooz);

    await _floozClient.initialize(
      publicKey: 'flooz_api_key',
      secretKey: 'flooz_secret_key',
      additionalConfig: {
        'merchantCode': 'YOUR_MERCHANT_CODE',
        'useSandbox': true, // For testing
      },
    );
  }

  Future<PaymentResult> processFloozPayment({
    required int amountInCents,
    required String customerPhone,
  }) async {
    final intent = await _floozClient.createPaymentIntent(
      amount: PaymentAmount(amountInCents: amountInCents, currency: 'XOF'),
      customerId: customerPhone,
      metadata: {
        'payment_method': 'mobile_money',
        'phone': customerPhone,
        'region': 'senegal',
      },
    );

    // Confirmation may require user validation
    final result = await _floozClient.confirmPayment(
      paymentIntentClientSecret: intent.clientSecret,
    );

    return result;
  }
}
```

## 📚 API Reference

### PaymentClient

Main class for interacting with payment providers.

#### Constructor
```dart
PaymentClient({required PaymentProvider provider})
```

#### Main Methods

##### initialize()
Initializes the client with API keys.

```dart
Future<void> initialize({
  required String publicKey,
  String? secretKey,
  Map<String, dynamic>? additionalConfig,
})
```

##### createPaymentIntent()
Creates a payment intent.

```dart
Future<PaymentIntentResult> createPaymentIntent({
  required PaymentAmount amount,
  required String customerId,
  Map<String, dynamic>? metadata,
})
```

##### confirmPayment()
Confirms and processes the payment.

```dart
Future<PaymentResult> confirmPayment({
  required String paymentIntentClientSecret,
  Map<String, dynamic>? paymentMethodData,
})
```

##### fetchPaymentStatus()
Retrieves payment status.

```dart
Future<PaymentStatus> fetchPaymentStatus(String paymentId)
```

##### refundPayment()
Refunds a payment.

```dart
Future<RefundResult> refundPayment({
  required String paymentId,
  PaymentAmount? amount,
  String? reason,
})
```

##### tokenizeCard()
Tokenizes a card for future use.

```dart
Future<String> tokenizeCard({
  required String cardNumber,
  required String expiryMonth,
  required String expiryYear,
  required String cvv,
})
```

### Data Classes

#### PaymentAmount
Represents a payment amount.

```dart
PaymentAmount({
  required int amountInCents,
  required String currency,
});

double get amountInMajorUnits => amountInCents / 100.0;
```

#### PaymentIntentResult
Result of a payment intent creation.

```dart
class PaymentIntentResult {
  final String id;
  final String clientSecret;
  final PaymentStatus status;
  final PaymentAmount amount;
  final Map<String, dynamic>? metadata;
}
```

#### PaymentResult
Result of a payment operation.

```dart
class PaymentResult {
  final String paymentId;
  final PaymentStatus status;
  final String? errorMessage;
  final String? errorCode;
  final Map<String, dynamic>? metadata;

  bool get isSuccessful => status == PaymentStatus.succeeded;
  bool get requiresAction => status == PaymentStatus.requiresAction;
  bool get hasFailed => status == PaymentStatus.failed;
}
```

### Enums

#### PaymentProvider
```dart
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
}
```

#### PaymentStatus
```dart
enum PaymentStatus {
  pending,
  processing,
  succeeded,
  failed,
  canceled,
  requiresAction,
}
```

## 🔒 Security and Best Practices

### API Key Management

1. **Never store keys in source code**
2. **Use environment variables** or a secret management service
3. **Secret keys should never be in mobile client**

```dart
// ❌ BAD
await client.initialize(
  publicKey: 'pk_test_123456789',
  secretKey: 'sk_test_987654321',
);

// ✅ GOOD
await client.initialize(
  publicKey: const String.fromEnvironment('STRIPE_PUBLIC_KEY'),
  secretKey: null, // Manage only on server side
);
```

### Recommended Server-Side Security

For maximum security with Stripe:

```dart
// Server side (Node.js/Express)
app.post('/create-payment-intent', async (req, res) => {
  const { amount, currency, customerId, metadata } = req.body;

  const paymentIntent = await stripe.paymentIntents.create({
    amount,
    currency,
    customer: customerId,
    metadata,
  });

  res.json({
    id: paymentIntent.id,
    client_secret: paymentIntent.client_secret,
  });
});
```

### Error Handling

```dart
try {
  final result = await paymentClient.confirmPayment(
    paymentIntentClientSecret: intent.clientSecret,
  );

  if (result.hasFailed) {
    // Show error to user
    showErrorDialog(result.errorMessage ?? 'Payment failed');
  }
} on PaymentException catch (e) {
  print('Payment error: ${e.message}');
} on PaymentProcessingException catch (e) {
  print('Processing error: ${e.message}');
}
```

## 🏗️ Technical Architecture

### Architecture Diagram

```
┌─────────────────┐    ┌──────────────────┐
│   PaymentClient │───▶│ PaymentProvider  │
│                 │    │      Plugin      │
└─────────────────┘    └──────────────────┘
                                │
                ┌───────────────┼───────────────┐
                │               │               │
        ┌───────▼─────┐ ┌───────▼─────┐ ┌───────▼─────┐
        │ Stripe      │ │ Flutterwave │ │ Flooz       │
        │ Plugin      │ │ Plugin      │ │ Plugin      │
        └─────────────┘ └─────────────┘ └─────────────┘
```

### Interfaces and Abstractions

#### PaymentProviderPlugin

Common interface implemented by all plugins:

```dart
abstract class PaymentProviderPlugin {
  PaymentProvider get provider;

  Future<void> initialize({
    required String publicKey,
    String? secretKey,
    Map<String, dynamic>? additionalConfig,
  });

  Future<PaymentIntentResult> createPaymentIntent({
    required PaymentAmount amount,
    required String customerId,
    Map<String, dynamic>? metadata,
  });

  Future<PaymentResult> confirmPayment({
    required String paymentIntentClientSecret,
    Map<String, dynamic>? paymentMethodData,
  });

  Future<PaymentStatus> fetchPaymentStatus(String paymentId);
  Future<RefundResult> refundPayment({
    required String paymentId,
    PaymentAmount? amount,
    String? reason,
  });

  Future<String> tokenizeCard({
    required String cardNumber,
    required String expiryMonth,
    required String expiryYear,
    required String cvv,
  });

  Future<void> handleWebhookEvent(Map<String, dynamic> event);
  Future<void> dispose();
}
```

## 🧪 Testing

### Unit Tests

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_payment/flutter_unified_payment.dart';

void main() {
  group('PaymentClient', () {
    test('should initialize Stripe client', () async {
      final client = PaymentClient(provider: PaymentProvider.stripe);

      await client.initialize(
        publicKey: 'pk_test_mock_key',
        secretKey: 'sk_test_mock_key',
      );

      expect(client.currentProvider, PaymentProvider.stripe);
      expect(client.supports3DS, true);
    });
  });
}
```

### Integration Tests

See the `example/` directory for complete integration examples.

## 🌍 Provider Support

| Provider | Status | 3DS | Client Secret | Region |
|----------|--------|-----|---------------|---------|
| Stripe | ✅ Prod | ✅ | ✅ | Global |
| Flutterwave | ✅ Prod | ✅ | ✅ | Africa |
| Flooz | ✅ Dev | ❌ | ❌ | Togo, Senegal, ... |
| Mixx by Yas | ✅ Dev | ❌ | ❌ | Togo, Guinea, .. |
| PayGate | ✅ Dev | ❌ | ❌ | Africa |
| CinetPay | ✅ Dev | ❌ | ❌ | Africa |
| Semoa | ✅ Dev | ❌ | ❌ | Africa |

## 📱 Complete Example Application

See the `example/` directory for a complete Flutter application demonstrating the use of all supported providers.

```bash
cd example
flutter run
```

## 🤝 Contributing

Contributions are welcome! To contribute:

1. Fork the project
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Adding a New Provider

To add a new payment provider:

1. Create a class implementing `PaymentProviderPlugin`
2. Add the provider to the `PaymentProvider` enum
3. Implement required methods
4. Add extensions in `extensions.dart`
5. Update `_resolvePlugin()` in `PaymentClient`

## 📄 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for more details.

## 📞 Support

- 📧 Email: kalyboskokou1@gmail.com
- 💬 Issues: [GitHub Issues](https://github.com/KalybosPro/issues)
- 📖 Documentation: [Pub.dev](https://pub.dev/packages/flutter_unified_payment)

---

Made with ❤️ for the Flutter community
