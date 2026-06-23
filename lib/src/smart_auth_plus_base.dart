import 'dart:async';
import 'package:flutter/services.dart';

import 'models/auth_exception.dart';
import 'models/sms_result.dart';
import 'models/phone_hint_result.dart';

/// SmartAuthPlus gives you a clean, stream-based interface to Android's
/// SMS User Consent, SMS Retriever, Phone Number Hint, and App Signature APIs.
///
/// Typical usage:
/// ```dart
/// final auth = SmartAuthPlus();
///
/// // Listen for an OTP SMS
/// final subscription = auth.smsUserConsentStream().listen((result) {
///   switch (result) {
///     case SmsReceived(:final message): print('Got SMS: $message');
///     case SmsCanceled(:final reason): print('Canceled: $reason');
///     case SmsError(:final code, :final message): print('Error $code: $message');
///   }
/// });
///
/// // Start listening on Android
/// await auth.startSmsUserConsent();
///
/// // Don't forget to cancel the subscription and dispose when done.
/// subscription.cancel();
/// auth.dispose();
/// ```
class SmartAuthPlus {
  static const _channel = MethodChannel('smart_auth_plus');
  static const _smsEventChannel = EventChannel('smart_auth_plus/sms_events');
  static const _phoneHintEventChannel =
      EventChannel('smart_auth_plus/phone_hint_events');

  // ─── Internal stream controllers ───────────────────────────────────────────

  StreamController<SmsResult>? _smsController;
  StreamController<PhoneHintResult>? _phoneHintController;

  StreamSubscription<dynamic>? _smsPlatformSub;
  StreamSubscription<dynamic>? _phoneHintPlatformSub;

  // ─── SMS User Consent ───────────────────────────────────────────────────────

  /// Returns a broadcast [Stream] of [SmsResult] events.
  ///
  /// Subscribe before calling [startSmsUserConsent]. The stream emits one
  /// event (received / canceled / error) and then closes automatically.
  ///
  /// The optional [senderPhoneNumber] filters consent requests to messages
  /// from that number only (5- to 15-digit string).
  Stream<SmsResult> smsUserConsentStream() {
    _disposeSmsController();
    _smsController = StreamController<SmsResult>.broadcast();

    _smsPlatformSub = _smsEventChannel
        .receiveBroadcastStream({'type': 'userConsent'})
        .listen(
          (event) => _handleSmsEvent(event as Map<dynamic, dynamic>),
          onError: (Object e) {
            _smsController?.addError(
              _convertError(e),
            );
            _disposeSmsController();
          },
          onDone: _disposeSmsController,
          cancelOnError: true,
        );

    return _smsController!.stream;
  }

  /// Returns a broadcast [Stream] of [SmsResult] events using the
  /// SMS Retriever API (no user dialog, but SMS must contain your app hash).
  Stream<SmsResult> smsRetrieverStream() {
    _disposeSmsController();
    _smsController = StreamController<SmsResult>.broadcast();

    _smsPlatformSub = _smsEventChannel
        .receiveBroadcastStream({'type': 'retriever'})
        .listen(
          (event) => _handleSmsEvent(event as Map<dynamic, dynamic>),
          onError: (Object e) {
            _smsController?.addError(_convertError(e));
            _disposeSmsController();
          },
          onDone: _disposeSmsController,
          cancelOnError: true,
        );

    return _smsController!.stream;
  }

  /// Starts the SMS User Consent listener on Android.
  ///
  /// [senderPhoneNumber] – optional E.164 or short-code filter.
  /// [timeout] – how long to wait for the SMS (default 5 minutes, max 5 min).
  ///
  /// Throws [AuthException] if Google Play Services is unavailable or
  /// no activity is attached.
  Future<void> startSmsUserConsent({
    String? senderPhoneNumber,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    try {
      await _channel.invokeMethod<void>('startSmsUserConsent', {
        'senderPhoneNumber': senderPhoneNumber,
        'timeoutSeconds': timeout.inSeconds.clamp(0, 300),
      });
    } on PlatformException catch (e) {
      throw AuthException(
        code: e.code,
        message: e.message ?? 'Unknown error',
        details: e.details,
      );
    }
  }

  /// Starts the SMS Retriever listener on Android.
  ///
  /// Your SMS must end with the 11-character app hash (get it via
  /// [getAppSignature]). No user dialog is shown.
  ///
  /// Throws [AuthException] on failure.
  Future<void> startSmsRetriever() async {
    try {
      await _channel.invokeMethod<void>('startSmsRetriever');
    } on PlatformException catch (e) {
      throw AuthException(
        code: e.code,
        message: e.message ?? 'Unknown error',
        details: e.details,
      );
    }
  }

  /// Cancels any active SMS listener (User Consent or Retriever).
  Future<void> cancelSmsListener() async {
    try {
      await _channel.invokeMethod<void>('cancelSmsListener');
    } on PlatformException catch (e) {
      throw AuthException(
        code: e.code,
        message: e.message ?? 'Unknown error',
        details: e.details,
      );
    } finally {
      _disposeSmsController();
    }
  }

  // ─── Phone Number Hint ──────────────────────────────────────────────────────

  /// Returns a broadcast [Stream] of [PhoneHintResult] events.
  ///
  /// Subscribe before calling [requestPhoneNumberHint]. The stream emits one
  /// event (selected / canceled / error) then closes.
  Stream<PhoneHintResult> phoneHintStream() {
    _disposePhoneHintController();
    _phoneHintController = StreamController<PhoneHintResult>.broadcast();

    _phoneHintPlatformSub = _phoneHintEventChannel
        .receiveBroadcastStream()
        .listen(
          (event) =>
              _handlePhoneHintEvent(event as Map<dynamic, dynamic>),
          onError: (Object e) {
            _phoneHintController?.addError(_convertError(e));
            _disposePhoneHintController();
          },
          onDone: _disposePhoneHintController,
          cancelOnError: true,
        );

    return _phoneHintController!.stream;
  }

  /// Shows the system phone number hint picker.
  ///
  /// [title] and [subtitle] are shown inside the picker sheet.
  ///
  /// Throws [AuthException] on failure.
  Future<void> requestPhoneNumberHint({
    String title = 'Select phone number',
    String subtitle = 'Choose a number for verification',
  }) async {
    try {
      await _channel.invokeMethod<void>('requestPhoneNumberHint', {
        'title': title,
        'subtitle': subtitle,
      });
    } on PlatformException catch (e) {
      throw AuthException(
        code: e.code,
        message: e.message ?? 'Unknown error',
        details: e.details,
      );
    }
  }

  // ─── App Signature ──────────────────────────────────────────────────────────

  /// Returns the 11-character SMS retriever hash for the current app/signing key.
  ///
  /// Call this once during development, then hard-code the result in your
  /// SMS template. Never call it in production flows – it is slow and
  /// the hash never changes for the same app + keystore combination.
  ///
  /// Returns `null` if the hash cannot be computed.
  Future<String?> getAppSignature() async {
    try {
      return await _channel.invokeMethod<String>('getAppSignature');
    } on PlatformException catch (e) {
      throw AuthException(
        code: e.code,
        message: e.message ?? 'Unknown error',
        details: e.details,
      );
    }
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  void _handleSmsEvent(Map<dynamic, dynamic> event) {
    final type = event['type'] as String?;
    switch (type) {
      case 'received':
        _smsController?.add(SmsReceived(event['message'] as String));
        _disposeSmsController();
      case 'canceled':
        _smsController
            ?.add(SmsCanceled(reason: event['reason'] as String?));
        _disposeSmsController();
      case 'error':
        _smsController?.add(SmsError(
          code: event['code'] as String? ?? 'UNKNOWN',
          message: event['message'] as String? ?? 'Unknown error',
        ));
        _disposeSmsController();
      default:
        // Unknown event type – ignore.
        break;
    }
  }

  void _handlePhoneHintEvent(Map<dynamic, dynamic> event) {
    final type = event['type'] as String?;
    switch (type) {
      case 'selected':
        _phoneHintController
            ?.add(PhoneHintSelected(event['phoneNumber'] as String));
        _disposePhoneHintController();
      case 'canceled':
        _phoneHintController
            ?.add(PhoneHintCanceled(reason: event['reason'] as String?));
        _disposePhoneHintController();
      case 'error':
        _phoneHintController?.add(PhoneHintError(
          code: event['code'] as String? ?? 'UNKNOWN',
          message: event['message'] as String? ?? 'Unknown error',
        ));
        _disposePhoneHintController();
      default:
        break;
    }
  }

  AuthException _convertError(Object e) {
    if (e is PlatformException) {
      return AuthException(
          code: e.code, message: e.message ?? 'Unknown error');
    }
    return AuthException(code: 'UNKNOWN', message: e.toString());
  }

  void _disposeSmsController() {
    _smsPlatformSub?.cancel();
    _smsPlatformSub = null;
    _smsController?.close();
    _smsController = null;
  }

  void _disposePhoneHintController() {
    _phoneHintPlatformSub?.cancel();
    _phoneHintPlatformSub = null;
    _phoneHintController?.close();
    _phoneHintController = null;
  }

  /// Release all resources. Call this in your widget's [dispose] method.
  void dispose() {
    _disposeSmsController();
    _disposePhoneHintController();
  }
}
