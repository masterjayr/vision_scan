import 'package:flutter_test/flutter_test.dart';
import 'package:vision_scan/vision_scan.dart';
import 'package:vision_scan/vision_scan_platform_interface.dart';
import 'package:vision_scan/vision_scan_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockVisionScanPlatform
    with MockPlatformInterfaceMixin
    implements VisionScanPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final VisionScanPlatform initialPlatform = VisionScanPlatform.instance;

  test('$MethodChannelVisionScan is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelVisionScan>());
  });
}
