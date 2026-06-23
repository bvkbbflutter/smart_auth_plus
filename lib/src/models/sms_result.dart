/// Represents the outcome of an SMS retrieval attempt (User Consent or Retriever).
sealed class SmsResult {
  const SmsResult();
}

/// The SMS was successfully retrieved.
final class SmsReceived extends SmsResult {
  /// The full SMS message body.
  final String message;

  const SmsReceived(this.message);

  @override
  String toString() => 'SmsReceived(message: $message)';
}

/// The user dismissed the consent dialog, or the retriever timed out.
final class SmsCanceled extends SmsResult {
  /// Optional reason provided by the platform.
  final String? reason;

  const SmsCanceled({this.reason});

  @override
  String toString() => 'SmsCanceled(reason: $reason)';
}

/// An error occurred while setting up or waiting for the SMS.
final class SmsError extends SmsResult {
  final String code;
  final String message;

  const SmsError({required this.code, required this.message});

  @override
  String toString() => 'SmsError(code: $code, message: $message)';
}
