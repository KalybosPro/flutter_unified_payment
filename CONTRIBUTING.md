# Contributing to Flutter Unified Payment

We welcome contributions to Flutter Unified Payment! This document provides guidelines and information for contributors.

## 📋 Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [How to Contribute](#how-to-contribute)
- [Development Guidelines](#development-guidelines)
- [Testing](#testing)
- [Documentation](#documentation)
- [Submitting Changes](#submitting-changes)

## 🤝 Code of Conduct

This project follows our [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you agree to uphold this code.

## 🚀 Getting Started

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/your-username/flutter_unified_payment.git
   cd flutter_unified_payment
   ```
3. **Set up your development environment** (see below)
4. **Create a new branch** for your contribution:
   ```bash
   git checkout -b feature/your-feature-name
   ```

## 🛠️ Development Setup

### Prerequisites

- **Flutter SDK**: >= 3.9.2
- **Dart SDK**: Included with Flutter
- **Git**: For version control

### Installation Steps

1. **Install Flutter**:
   ```bash
   # Follow the official Flutter installation guide:
   # https://flutter.dev/docs/get-started/install
   flutter doctor
   ```

2. **Clone and setup**:
   ```bash
   git clone https://github.com/your-username/flutter_unified_payment.git
   cd flutter_unified_payment

   # Copy environment configuration
   cp .env.example .env
   # Edit .env with your test credentials
   ```

3. **Install dependencies**:
   ```bash
   flutter pub get
   cd example && flutter pub get && cd ..
   ```

4. **Verify setup**:
   ```bash
   flutter analyze
   flutter test
   ```

### Environment Configuration

Create a `.env` file from `.env.example` and add your test credentials:

```bash
cp .env.example .env
# Edit .env with appropriate test values
```

## 🤝 How to Contribute

### Types of Contributions

- **🐛 Bug fixes**: Fix existing issues
- **✨ New features**: Add new functionality
- **📚 Documentation**: Improve docs, examples, tutorials
- **🧪 Tests**: Add new tests or improve existing ones
- **⚡ Performance**: Performance improvements
- **🔧 Maintenance**: Code refactoring, dependency updates

### Finding Issues

1. Check [GitHub Issues](https://github.com/KalybosPro/flutter_unified_payment/issues) for open tasks
2. Look for issues labeled `good first issue` or `help wanted`
3. Comment on issues to express interest in working on them

### Adding a New Payment Provider

1. **Create the plugin class**:
   ```dart
   class NewProviderPaymentPlugin implements PaymentProviderPlugin {
     // Implement all required methods
   }
   ```

2. **Add to exports** in `lib/src/plugins/plugins.dart`

3. **Update enums and extensions** in `lib/src/core/extensions/extensions.dart`

4. **Register in PaymentClient** constructor

5. **Add comprehensive tests**

## 📝 Development Guidelines

### Code Style

- Follow [Flutter's Effective Dart](https://dart.dev/effective-dart) guidelines
- Use `flutter analyze` and `flutter format` before committing
- Maximum line length: 120 characters
- Use meaningful variable and method names

### Commit Messages

Use conventional commit format:

```bash
type(scope): description

[optional body]

[optional footer]
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation
- `style`: Code style changes
- `refactor`: Code refactoring
- `test`: Adding tests
- `chore`: Maintenance

**Examples**:
```bash
feat(stripe): add Apple Pay support
fix(cinetpay): resolve webhook signature validation
docs(readme): update installation instructions
test(payment): add integration tests for refunds
```

### Branch Naming

Use descriptive branch names:

```bash
feature/add-apple-pay-support
fix/cinetpay-webhook-validation
docs/update-api-reference
```

### Pull Request Guidelines

- **Title**: Clear, descriptive title following commit convention
- **Description**: Explain what changes and why
- **Tests**: Include tests for new functionality
- **Documentation**: Update docs if needed
- **Breaking changes**: Clearly document any breaking changes

## 🧪 Testing

### Running Tests

```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/payment_client_test.dart

# Run with coverage
flutter test --coverage

# Run example app tests
cd example && flutter test
```

### Test Requirements

- **Unit tests** for all new functionality
- **Integration tests** for payment flows
- **Mock external dependencies** (APIs, network calls)
- **Test edge cases** and error handling
- **Minimum 80% code coverage** for new code

### Test Structure

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PaymentClient', () {
    late PaymentClient client;

    setUp(() {
      client = PaymentClient(provider: PaymentProvider.stripe);
    });

    test('should initialize correctly', () async {
      await client.initialize(publicKey: 'test_key');
      expect(client.currentProvider, PaymentProvider.stripe);
    });

    test('should handle errors gracefully', () async {
      expect(
        () => client.createPaymentIntent(amount: null, customerId: ''),
        throwsA(isA<PaymentException>()),
      );
    });
  });
}
```

## 📚 Documentation

### Documentation Requirements

- **README.md**: Clear installation and usage instructions
- **API documentation**: All public APIs documented with `///`
- **Code comments**: Complex logic explained
- **Examples**: Working examples in `/example` directory
- **CHANGELOG.md**: Track changes and versions

### Generating Documentation

```bash
# Generate API docs
flutter pub run dartdoc

# Format code
flutter format .

# Analyze code
flutter analyze
```

### Example Documentation

```dart
/// Creates a payment intent for processing payments.
///
/// This method initializes a payment transaction that can be confirmed
/// later using the returned client secret.
///
/// **Parameters:**
/// - [amount]: The payment amount including currency
/// - [customerId]: Unique identifier for the customer
/// - [metadata]: Optional additional data for the transaction
///
/// **Returns:** A [PaymentIntentResult] containing the intent details
///
/// **Throws:**
/// - [PaymentException] if initialization failed
/// - [PaymentProcessingException] if the request fails
///
/// **Example:**
/// ```dart
/// final intent = await client.createPaymentIntent(
///   amount: PaymentAmount(amountInCents: 5000, currency: 'USD'),
///   customerId: 'customer_123',
/// );
/// ```
Future<PaymentIntentResult> createPaymentIntent({
  required PaymentAmount amount,
  required String customerId,
  Map<String, dynamic>? metadata,
}) async {
  // Implementation...
}
```

## 🔄 Submitting Changes

### Step-by-Step Process

1. **Ensure your code is ready**:
   ```bash
   flutter analyze
   flutter test
   flutter format .
   ```

2. **Update documentation** if needed

3. **Commit your changes**:
   ```bash
   git add .
   git commit -m "feat(provider): add new feature"
   ```

4. **Push to your fork**:
   ```bash
   git push origin feature/your-feature-name
   ```

5. **Create a Pull Request**:
   - Use clear, descriptive title
   - Fill out the PR template
   - Reference related issues
   - Request review from maintainers

### Pull Request Template

Please use this template for your PR:

```markdown
## Description
Brief description of the changes made.

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] Manual testing completed

## Checklist
- [ ] Code follows project style guidelines
- [ ] Documentation updated
- [ ] Tests pass locally
- [ ] All CI checks pass

## Additional Notes
Any additional information or context.
```

### Code Review Process

1. **Automated checks** (CI/CD): Linting, testing, formatting
2. **Peer review**: Usually 1-2 reviewers
3. **Feedback and iteration**: Address review comments
4. **Approval and merge**: Maintainers approve and merge

### Releasing

Maintainers handle releases following semantic versioning. Contributors are credited in CHANGELOG.md.

## 🆘 Getting Help

### Resources

- **Issues**: https://github.com/KalybosPro/flutter_unified_payment/issues
- **Discussions**: https://github.com/KalybosPro/flutter_unified_payment/discussions
- **Documentation**: https://pub.dev/packages/flutter_unified_payment
- **Flutter Discord**: Ask in #help channel

### Common Issues

**Tests failing**: Ensure you have test dependencies and proper environment setup.

**Analyzer errors**: Run `flutter format .` and `flutter analyze --fix` to auto-fix issues.

**No response from maintainers**: Be patient, maintainers are volunteers and may have other commitments.

## 🎉 Recognition

Contributors are recognized through:
- GitHub contributor statistics
- CHANGELOG.md credits
- Mention in releases

Thank you for contributing to Flutter Unified Payment! 🚀
