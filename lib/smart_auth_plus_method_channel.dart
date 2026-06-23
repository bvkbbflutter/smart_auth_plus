import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'smart_auth_plus_platform_interface.dart';

/// An implementation of [SmartAuthPlusPlatform] that uses method channels.
class MethodChannelSmartAuthPlus extends SmartAuthPlusPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('smart_auth_plus');

  @override
  Future<String?> getPlatformVersion() async {
    final version =
        await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
