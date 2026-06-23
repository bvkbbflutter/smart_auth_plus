/// Represents the outcome of a Phone Number Hint request.
sealed class PhoneHintResult {
  const PhoneHintResult();
}

/// The user selected a phone number from the hint picker.
final class PhoneHintSelected extends PhoneHintResult {
  /// The selected phone number (E.164 format where possible, e.g. +919876543210).
  final String phoneNumber;

  const PhoneHintSelected(this.phoneNumber);

  @override
  String toString() => 'PhoneHintSelected(phoneNumber: $phoneNumber)';
}

/// The user dismissed the hint picker without selecting a number.
final class PhoneHintCanceled extends PhoneHintResult {
  final String? reason;

  const PhoneHintCanceled({this.reason});

  @override
  String toString() => 'PhoneHintCanceled(reason: $reason)';
}

/// An error occurred while requesting the phone number hint.
final class PhoneHintError extends PhoneHintResult {
  final String code;
  final String message;

  const PhoneHintError({required this.code, required this.message});

  @override
  String toString() => 'PhoneHintError(code: $code, message: $message)';
}
