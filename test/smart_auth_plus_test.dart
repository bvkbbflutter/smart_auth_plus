import 'package:flutter_test/flutter_test.dart';
import 'package:smart_auth_plus/smart_auth_plus.dart';
import 'package:smart_auth_plus/smart_auth_plus_platform_interface.dart';
import 'package:smart_auth_plus/smart_auth_plus_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockSmartAuthPlusPlatform
    with MockPlatformInterfaceMixin
    implements SmartAuthPlusPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final SmartAuthPlusPlatform initialPlatform = SmartAuthPlusPlatform.instance;

  test('$MethodChannelSmartAuthPlus is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelSmartAuthPlus>());
  });

  test('getPlatformVersion', () async {
    SmartAuthPlus smartAuthPlusPlugin = SmartAuthPlus();
    MockSmartAuthPlusPlatform fakePlatform = MockSmartAuthPlusPlatform();
    SmartAuthPlusPlatform.instance = fakePlatform;

    // expect(await smartAuthPlusPlugin.getPlatformVersion(), '42');
  });
}
