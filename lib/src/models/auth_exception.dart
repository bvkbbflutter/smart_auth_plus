/// Thrown when a plugin method call fails at the platform-channel layer
/// (e.g. Google Play Services not available, activity missing, etc.).
class AuthException implements Exception {
  final String code;
  final String message;
  final Object? details;

  const AuthException({
    required this.code,
    required this.message,
    this.details,
  });

  @override
  String toString() => 'AuthException[$code]: $message';
}
