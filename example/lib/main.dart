import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_unified_payment/flutter_unified_payment.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  Future<void> initialize() async {
    // Exemple 1: Utilisation avec Stripe
    print('=== EXEMPLE STRIPE ===');
    final stripeClient = PaymentClient(provider: PaymentProvider.stripe);

    try {
      await stripeClient.initialize(
        publicKey: 'pk_test_xxxxx',
        secretKey: 'sk_test_xxxxx',
      );

      final paymentIntent = await stripeClient.createPaymentIntent(
        amount: PaymentAmount(amountInCents: 5000, currency: 'USD'),
        customerId: 'cus_123',
        metadata: {'order_id': '12345'},
      );

      print('PaymentIntent créé: ${paymentIntent.id}');

      final result = await stripeClient.confirmPayment(
        paymentIntentClientSecret: paymentIntent.clientSecret,
      );

      if (result.isSuccessful) {
        print('Paiement réussi: ${result.paymentId}');
      } else {
        print('Paiement échoué: ${result.errorMessage}');
      }
    } catch (e) {
      print('Erreur: $e');
    }

    print('\n=== EXEMPLE FLOOZ ===');
    // Test des nouveaux providers
    final floozClient = PaymentClient(provider: PaymentProvider.flooz);

    await floozClient.initialize(publicKey: 'flooz_public_key');

    final floozIntent = await floozClient.createPaymentIntent(
      amount: PaymentAmount(amountInCents: 5000, currency: 'XOF'),
      customerId: 'cus_789',
    );

    print('Flooz PaymentIntent: ${floozIntent.id}');

    print('\n=== EXEMPLE MIXX BY YAS ===');
    final mixxClient = PaymentClient(provider: PaymentProvider.mixxByYas);

    await mixxClient.initialize(publicKey: 'mixx_public_key');

    final mixxIntent = await mixxClient.createPaymentIntent(
      amount: PaymentAmount(amountInCents: 3000, currency: 'XOF'),
      customerId: 'cus_999',
    );

    print('Mixx by Yas PaymentIntent: ${mixxIntent.id}');

    // Exemple 3: Vérifier les capacités du provider
    print('\n=== MÉTADONNÉES PROVIDERS ===');
    print('Stripe supporte 3DS: ${PaymentProvider.stripe.supports3DS}');
    print('Flooz supporte 3DS: ${PaymentProvider.flooz.supports3DS}');
    print('PayPal nom: ${PaymentProvider.paypal.displayName}');
    print('Flooz nom: ${PaymentProvider.flooz.displayName}');
    print('Semoa nom: ${PaymentProvider.semoa.displayName}');
  }

  @override
  void initState() {
    super.initState();
    unawaited(initialize());
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
