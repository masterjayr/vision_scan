import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'vision_scan_method_channel.dart';

abstract class VisionScanPlatform extends PlatformInterface {
  /// Constructs a VisionScanPlatform.
  VisionScanPlatform() : super(token: _token);

  static final Object _token = Object();

  static VisionScanPlatform _instance = MethodChannelVisionScan();

  /// The default instance of [VisionScanPlatform] to use.
  ///
  /// Defaults to [MethodChannelVisionScan].
  static VisionScanPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [VisionScanPlatform] when
  /// they register themselves.
  static set instance(VisionScanPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
