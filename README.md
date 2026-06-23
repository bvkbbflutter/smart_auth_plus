# smart_auth_plus

A Flutter plugin for Android that wraps Google Play Services' SMS and phone-number authentication APIs with a clean, stream-based Dart API.

## Preview

![Flutter Phone Field](https://raw.githubusercontent.com/bvkbbflutter/flutter_phone_field_plus/main/assets/images/smart_auth_plus.png)

## Features

| Feature | API used | Permission needed? |
|---|---|---|
| **SMS User Consent** | `SmsRetriever.startSmsUserConsent` | ❌ None |
| **SMS Retriever** | `SmsRetriever.startSmsRetriever` | ❌ None |
| **Phone Number Hint** | `Credentials.getHintPickerIntent` | ❌ None |
| **App Signature Hash** | Custom SHA-256 helper | ❌ None |

All results are exposed as **sealed classes** via **Streams** – no callbacks, no futures, easy `switch` pattern matching.

---

## Installation

```yaml
dependencies:
  smart_auth_plus: ^0.0.1
```

---

## Quick Start

```dart
import 'package:smart_auth_plus/smart_auth_plus.dart';

final auth = SmartAuthPlus();

// Always subscribe BEFORE calling start*
final sub = auth.smsUserConsentStream().listen((result) {
  switch (result) {
    case SmsReceived(:final message):
      print('Got SMS: $message');
      // Extract OTP from message here
    case SmsCanceled(:final reason):
      print('Canceled: $reason');
    case SmsError(:final code, :final message):
      print('Error $code: $message');
  }
});

await auth.startSmsUserConsent();

// When done:
sub.cancel();
auth.dispose();
```

---

## API Reference

### SmartAuthPlus

#### SMS User Consent

```dart
// 1. Subscribe
Stream<SmsResult> smsUserConsentStream()

// 2. Start
Future<void> startSmsUserConsent({
  String? senderPhoneNumber,   // optional filter
  Duration timeout = const Duration(minutes: 5),
})
```

#### SMS Retriever (automatic, no dialog)

Your SMS **must** end with the 11-character hash from `getAppSignature()`.

```dart
// SMS format: "Your OTP is 123456\n\nFA+9qCX9VSu"

Stream<SmsResult> smsRetrieverStream()
Future<void> startSmsRetriever()
```

#### Cancel

```dart
Future<void> cancelSmsListener()
```

#### Phone Number Hint

```dart
Stream<PhoneHintResult> phoneHintStream()

Future<void> requestPhoneNumberHint({
  String title = 'Select phone number',
  String subtitle = 'Choose a number for verification',
})
```

#### App Signature Hash

```dart
// Call once during development; never in production
Future<String?> getAppSignature()
```

#### Dispose

```dart
void dispose()  // Call in widget dispose()
```

---

## Result Types

### SmsResult (sealed)

```dart
switch (result) {
  case SmsReceived(:final message):  // Full SMS body
  case SmsCanceled(:final reason):   // User dismissed or timeout
  case SmsError(:final code, :final message): // Platform error
}
```

### PhoneHintResult (sealed)

```dart
switch (result) {
  case PhoneHintSelected(:final phoneNumber): // E.164 number
  case PhoneHintCanceled(:final reason):
  case PhoneHintError(:final code, :final message):
}
```

---

## SMS Retriever – App Signature

1. Run your app in debug, tap **Get Hash** (or call `getAppSignature()`).
2. Note the 11-character result, e.g. `FA+9qCX9VSu`.
3. Append it to every OTP SMS your server sends:

```
Your OTP code is 123456

FA+9qCX9VSu
```

> ⚠️ The hash differs between debug and release builds. Generate one for each keystore.

---

## Requirements

- Flutter ≥ 3.10
- Dart ≥ 3.0
- Android minSdk 21
- Google Play Services on device

---

## License

BSD-3-Clause
