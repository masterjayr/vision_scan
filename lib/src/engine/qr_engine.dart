import 'package:vision_scan/src/engine/qr_isolate.dart';

import '../ffi/native_bindings.dart';
import 'dart:typed_data';

class QrEngine {
  static const int _minIntervalMs = 250;
  static int _lastRunMs = 0;
  static QrIsolate? _isolate;

  static Future<void> init() async {
    _isolate ??= await QrIsolate.spawn();
  }

  static String? decodeQRCode(Uint8List grayBytes, int width, int height) {
    return NativeBindings.decodeQR(grayBytes, width, height);
  }

  static Future<String?> decodeFromGray(
    Uint8List grayBytes,
    int width,
    int height,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;

    if (now - _lastRunMs < _minIntervalMs) {
      return Future.value(null);
    }
    _lastRunMs = now;

    return _isolate!.decode(grayBytes, width, height);
  }

  static void dispose() {
    _isolate?.dispose();
    _isolate = null;
  }
}
