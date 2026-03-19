import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'vision_scan_platform_interface.dart';

/// An implementation of [VisionScanPlatform] that uses method channels.
class MethodChannelVisionScan extends VisionScanPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('vision_scan');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
