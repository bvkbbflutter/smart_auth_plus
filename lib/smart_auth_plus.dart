/// SmartAuthPlus - Flutter plugin for Android SMS/Phone authentication APIs.
///
/// Features:
///   - SMS User Consent: prompt user to approve reading a specific SMS.
///   - SMS Retriever: automatically retrieve OTP SMS without READ_SMS permission.
///   - Phone Number Hint: show system picker to select a phone number.
///   - App Signature: generate the 11-char hash for your SMS template.
///
/// All features use a Stream-based API so you can react to results, errors,
/// and cancellations without callbacks or futures.

export 'src/smart_auth_plus_base.dart';
export 'src/models/sms_result.dart';
export 'src/models/phone_hint_result.dart';
export 'src/models/auth_exception.dart';

// class SmartAuthPlus {
//   Future<String?> getPlatformVersion() {
//     return SmartAuthPlusPlatform.instance.getPlatformVersion();
//   }
// }
