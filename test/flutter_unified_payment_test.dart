import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_unified_payment/flutter_unified_payment.dart';

void main() {
  group('PaymentClient Tests', () {
    test('PaymentClient initializes with Stripe', () async {
      final client = PaymentClient(provider: PaymentProvider.stripe);
      await client.initialize(publicKey: 'pk_test_stripe');
      expect(client.currentProvider, PaymentProvider.stripe);
    });

    test('PaymentClient initializes with Flutterwave', () async {
      final client = PaymentClient(provider: PaymentProvider.flutterwave);
      await client.initialize(
        publicKey: 'fw_public_test_key',
        secretKey: 'FLWSECK_TEST-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX-X',
      );
      expect(client.currentProvider, PaymentProvider.flutterwave);
    });

    test('PaymentClient initializes with Flooz', () async {
      final client = PaymentClient(provider: PaymentProvider.flooz);
      await client.initialize(publicKey: 'flooz_test_key');
      expect(client.currentProvider, PaymentProvider.flooz);
    });

    test('PaymentClient initializes with Mixx by Yas', () async {
      final client = PaymentClient(provider: PaymentProvider.mixxByYas);
      await client.initialize(publicKey: 'mixx_test_key');
      expect(client.currentProvider, PaymentProvider.mixxByYas);
    });

    test('PaymentClient initializes with PayGate', () async {
      final client = PaymentClient(provider: PaymentProvider.paygate);
      await client.initialize(
        publicKey: '100001234567890',
        secretKey: 'test_encryption_key_abcdefghijklmnop',
      );
      expect(client.currentProvider, PaymentProvider.paygate);
    });

    test('PaymentClient initializes with CinetPay', () async {
      final client = PaymentClient(provider: PaymentProvider.cinetpay);
      await client.initialize(
        publicKey: 'cinet_api_key_test',
        additionalConfig: {'siteId': '123456'}
      );
      expect(client.currentProvider, PaymentProvider.cinetpay);
    });

    test('PaymentClient initializes with Semoa', () async {
      final client = PaymentClient(provider: PaymentProvider.semoa);
      await client.initialize(publicKey: 'semoa_test_key');
      expect(client.currentProvider, PaymentProvider.semoa);
    });

    test('PaymentClient Stripe backend URL requirement', () async {
      final client = PaymentClient(provider: PaymentProvider.stripe);
      await client.initialize(
        publicKey: 'pk_test_stripe',
        additionalConfig: {'backendUrl': 'https://api.test.com'}, // Mock backend URL
      );

      // Since we don't have a real backend, this demonstrates that
      // the backend URL is required for actual Stripe operations
      expect(
        () async => await client.createPaymentIntent(
          amount: PaymentAmount(amountInCents: 5000, currency: 'USD'),
          customerId: 'cus_123',
        ),
        throwsA(isA<PaymentException>()),
      );
    });

    test('PaymentClient create payment intent for Flooz', () async {
      final client = PaymentClient(provider: PaymentProvider.flooz);
      await client.initialize(publicKey: 'flooz_test_key');

      final intent = await client.createPaymentIntent(
        amount: PaymentAmount(amountInCents: 10000, currency: 'XOF'),
        customerId: 'cus_flooz',
      );

      expect(intent.id, startsWith('flooz_'));
      expect(intent.status, PaymentStatus.pending);
      expect(intent.amount.amountInCents, 10000);
      expect(intent.amount.currency, 'XOF');
    });

    test('PaymentClient throws UnimplementedError for unimplemented provider', () {
      expect(
        () => PaymentClient(provider: PaymentProvider.paypal),
        throwsA(isA<UnimplementedError>()),
      );
    });
  });

  group('Payment Provider Extensions Tests', () {
    test('supports3DS returns correct values', () {
      expect(PaymentProvider.stripe.supports3DS, true);
      expect(PaymentProvider.flutterwave.supports3DS, true);
      expect(PaymentProvider.flooz.supports3DS, false);
      expect(PaymentProvider.paypal.supports3DS, false);
      expect(PaymentProvider.mixxByYas.supports3DS, false);
      expect(PaymentProvider.cinetpay.supports3DS, false);
    });

    test('requiresClientSecret returns correct values', () {
      expect(PaymentProvider.stripe.requiresClientSecret, true);
      expect(PaymentProvider.flutterwave.requiresClientSecret, false);
      expect(PaymentProvider.flooz.requiresClientSecret, false);
      expect(PaymentProvider.paygate.requiresClientSecret, false);
    });

    test('displayName returns correct names', () {
      expect(PaymentProvider.stripe.displayName, 'Stripe');
      expect(PaymentProvider.flutterwave.displayName, 'Flutterwave');
      expect(PaymentProvider.flooz.displayName, 'Flooz');
      expect(PaymentProvider.mixxByYas.displayName, 'Mixx by Yas');
      expect(PaymentProvider.paygate.displayName, 'PayGate');
      expect(PaymentProvider.cinetpay.displayName, 'CinetPay');
      expect(PaymentProvider.semoa.displayName, 'Semoa');
      expect(PaymentProvider.paypal.displayName, 'PayPal');
      expect(PaymentProvider.wave.displayName, 'Wave');
      expect(PaymentProvider.mtnMomo.displayName, 'MTN Mobile Money');
      expect(PaymentProvider.orangeMoney.displayName, 'Orange Money');
    });
  });

  group('Exception Handling Tests', () {
    test('PaymentClient throws exception when plugin not initialized - Stripe', () async {
      final client = PaymentClient(provider: PaymentProvider.stripe);

      expect(
        () async => await client.createPaymentIntent(
          amount: PaymentAmount(amountInCents: 5000, currency: 'USD'),
          customerId: 'cus_123',
        ),
        throwsA(isA<PaymentException>()),
      );
    });

    test('PaymentClient throws exception when plugin not initialized - Flooz', () async {
      final client = PaymentClient(provider: PaymentProvider.flooz);

      expect(
        () async => await client.createPaymentIntent(
          amount: PaymentAmount(amountInCents: 5000, currency: 'XOF'),
          customerId: 'cus_flooz',
        ),
        throwsA(isA<PaymentException>()),
      );
    });
  });

  group('Plugin-Specific Tests', () {
    test('Flooz plugin refund returns correct amount', () async {
      final plugin = FloozPaymentPlugin();
      await plugin.initialize(publicKey: 'flooz_test_key');

      final refund = await plugin.refundPayment(
        paymentId: 'test_payment',
        amount: PaymentAmount(amountInCents: 5000, currency: 'XOF'),
      );

      expect(refund.isSuccessful, true);
      expect(refund.refundId, startsWith('flooz_re_'));
      expect(refund.amount.amountInCents, 5000);
      expect(refund.amount.currency, 'XOF');
    });

    test('PayGate plugin tokenize returns token', () async {
      final plugin = PayGatePaymentPlugin();
      await plugin.initialize(
        publicKey: '100001234567890',
        secretKey: 'test_encryption_key_abcdefghijklmnop',
      );

      final token = await plugin.tokenizeCard(
        cardNumber: '4111111111111111',
        expiryMonth: '12',
        expiryYear: '25',
        cvv: '123',
      );

      expect(token, startsWith('PG_TOKEN_'));
    });

    test('CinetPay plugin handles webhooks', () async {
      final plugin = CinetPayPaymentPlugin();
      await plugin.initialize(
        publicKey: 'cinet_api_key_test',
        additionalConfig: {'siteId': '123456'}
      );

      // Webhook handling doesn't throw
      await plugin.handleWebhookEvent({
        'type': 'payment.succeeded',
        'data': {'id': 'test_payment'},
      });
    });

    test('Semoa plugin fetch status returns succeeded', () async {
      final plugin = SemoaPaymentPlugin();
      await plugin.initialize(publicKey: 'semoa_test_key');

      final status = await plugin.fetchPaymentStatus('test_payment');
      expect(status, PaymentStatus.succeeded);
    });
  });

  group('Plugin Initialization Tests', () {
    test('All plugins initialize correctly', () async {
      final plugins = [
        {'plugin': FloozPaymentPlugin(), 'name': 'Flooz'},
        {'plugin': MixxByYasPaymentPlugin(), 'name': 'Mixx by Yas'},
        {'plugin': PayGatePaymentPlugin(), 'name': 'PayGate'},
        {'plugin': CinetPayPaymentPlugin(), 'name': 'CinetPay'},
        {'plugin': SemoaPaymentPlugin(), 'name': 'Semoa'},
        {'plugin': FlutterwavePaymentPlugin(), 'name': 'Flutterwave'},
        {'plugin': StripePaymentPlugin(), 'name': 'Stripe'},
      ];

      for (final pluginMap in plugins) {
        final plugin = pluginMap['plugin'] as PaymentProviderPlugin;
        final name = pluginMap['name'] as String;

        try {
          // Flutterwave and PayGate need secret keys, others don't
          if (name == 'Flutterwave') {
            await plugin.initialize(
              publicKey: '${name.toLowerCase()}_public_test_key',
              secretKey: 'FLWSECK_TEST-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX-X',
            );
          } else if (name == 'PayGate') {
            await plugin.initialize(
              publicKey: '100001234567890',
              secretKey: 'test_encryption_key_abcdefghijklmnop',
            );
          } else if (name == 'CinetPay') {
            await plugin.initialize(
              publicKey: 'cinet_api_key_test',
              additionalConfig: {'siteId': '123456'}
            );
          } else {
            await plugin.initialize(publicKey: '${name.toLowerCase()}_test_key');
          }
          expect(true, true); // Initialization succeeded
        } catch (e) {
          fail('$name plugin initialization failed: $e');
        }
      }
    });
  });

  group('Payment Status Enum Tests', () {
    test('PaymentStatus values are defined correctly', () {
      expect(PaymentStatus.pending, PaymentStatus.pending);
      expect(PaymentStatus.processing, PaymentStatus.processing);
      expect(PaymentStatus.succeeded, PaymentStatus.succeeded);
      expect(PaymentStatus.failed, PaymentStatus.failed);
      expect(PaymentStatus.canceled, PaymentStatus.canceled);
      expect(PaymentStatus.requiresAction, PaymentStatus.requiresAction);
    });
  });

  group('Payment Amount Tests', () {
    test('PaymentAmount constructor', () {
      final amount = PaymentAmount(amountInCents: 1000, currency: 'USD');
      expect(amount.amountInCents, 1000);
      expect(amount.currency, 'USD');
      expect(amount.amountInMajorUnits, 10.0);
    });
  });
}
