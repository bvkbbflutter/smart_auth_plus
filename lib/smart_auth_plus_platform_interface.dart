import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'smart_auth_plus_method_channel.dart';

abstract class SmartAuthPlusPlatform extends PlatformInterface {
  /// Constructs a SmartAuthPlusPlatform.
  SmartAuthPlusPlatform() : super(token: _token);

  static final Object _token = Object();

  static SmartAuthPlusPlatform _instance = MethodChannelSmartAuthPlus();

  /// The default instance of [SmartAuthPlusPlatform] to use.
  ///
  /// Defaults to [MethodChannelSmartAuthPlus].
  static SmartAuthPlusPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [SmartAuthPlusPlatform] when
  /// they register themselves.
  static set instance(SmartAuthPlusPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
