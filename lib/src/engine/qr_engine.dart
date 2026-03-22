import 'dart:io';

import 'package:vision_scan/src/engine/qr_isolate.dart';
import 'package:vision_scan/src/models/final_capture_result.dart';
import 'package:vision_scan/src/models/frame_detection_result.dart';

import '../ffi/native_bindings.dart';
import 'dart:typed_data';

class QrEngine {
  // No throttle on detect — we want every frame to update the overlay.
  // Throttle only applies to the standalone decode helper (rarely used).
  static const int _decodeMinIntervalMs = 60;
  static int _lastDecodeMs = 0;

  // Guard against queuing up multiple detect calls simultaneously.
  // If the isolate is still working on the previous frame we drop the new one
  // instead of piling up a backlog.
  static bool _detectInFlight = false;

  static QrIsolate? _isolate;

  static Future<void> init() async {
    _isolate ??= await QrIsolate.spawn();
  }

  static bool get isReady => _isolate != null;

  static String? decodeQRCode(Uint8List grayBytes, int width, int height) {
    return NativeBindings.decodeQR(grayBytes, width, height);
  }

  static int windowsPrint() {
    return NativeBindings.pingWindows();
  }

  static int windowsOpenCvTest() {
    return NativeBindings.opencvTestWindows();
  }

  static int windowsZxingTest() {
    return NativeBindings.zxingTestWindows();
  }

  /// Decode-only: gray buffer → first successful QR string ([VSScanResult] / [scan_qr_from_gray]).
  static Future<String?> scanFromGray(
    Uint8List gray,
    int width,
    int height,
  ) async {
    if (_isolate == null) return null;
    return _isolate!.scanFromGray(gray, width, height);
  }

  /// Windows-only: native OpenCV window, first successful decode (Esc cancels).
  static Future<String?> scanWindows() async {
    if (!Platform.isWindows) return null;
    return Future(() => NativeBindings.scanWindows());
  }

  /// Windows-only: opens native camera, preview + box + stabilize, returns same type as captureFromGray.
  static Future<FinalCaptureResult?> captureFromCameraWindows() async {
    if (!Platform.isWindows) return null;
    final r = await Future(() => NativeBindings.captureFromCameraWindows());
    if (r == null) return null;
    return FinalCaptureResult(
      success: r.success,
      decoded: r.decoded,
      text: r.text,
      corners: r.corners,
      croppedJpeg: r.croppedJpeg.toList(),
      frameJpeg: r.frameJpeg.toList(),
    );
  }

  /// Sends gray frame to the isolate for detection.
  /// Returns null if the isolate is busy (previous frame still processing) or
  /// not yet initialised — the caller should just skip that frame silently.
  static Future<FrameDetectionResult?> detectFromGray(
    Uint8List gray,
    int width,
    int height,
  ) async {
    if (_isolate == null) return null;

    // Drop frame instead of queuing — keeps overlay latency at one-frame-behind
    // rather than growing a backlog during fast movement.
    if (_detectInFlight) return null;

    _detectInFlight = true;
    try {
      final r = await _isolate!.detect(gray, width, height);
      if (r == null) return null;

      return FrameDetectionResult(
        detected: r.detected,
        decoded: r.decoded,
        text: r.text,
        corners: r.corners,
      );
    } finally {
      _detectInFlight = false;
    }
  }

  static Future<FinalCaptureResult?> captureFromGray(
    Uint8List gray,
    int width,
    int height,
  ) async {
    if (_isolate == null) return null;

    final r = await _isolate!.capture(gray, width, height);
    if (r == null) return null;

    return FinalCaptureResult(
      success: r.success,
      decoded: r.decoded,
      text: r.text,
      corners: r.corners,
      croppedJpeg: r.croppedJpeg,
      frameJpeg: r.frameJpeg,
    );
  }

  static Future<String?> decodeFromGray(
    Uint8List grayBytes,
    int width,
    int height,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastDecodeMs < _decodeMinIntervalMs) return Future.value(null);
    _lastDecodeMs = now;

    return _isolate!.decode(grayBytes, width, height);
  }

  static void dispose() {
    _isolate?.dispose();
    _isolate = null;
  }
}
