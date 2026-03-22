import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:vision_scan/src/camera/qr_scanner_view.dart';
import 'package:vision_scan/src/camera/simple_qr_scan_page.dart';
import 'package:vision_scan/src/engine/qr_engine.dart';
import 'package:vision_scan/src/models/final_capture_paths_result.dart';
import 'package:vision_scan/src/models/final_capture_result.dart';

export 'package:vision_scan/src/models/final_capture_paths_result.dart';
export 'package:vision_scan/src/models/final_capture_result.dart';

class VisionScan {
  String? decodeQRCode(Uint8List grayBytes, int width, int height) {
    return QrEngine.decodeQRCode(grayBytes, width, height);
  }

  int windowsPrint() {
    return QrEngine.windowsPrint();
  }

  int windowsOpenCvTest() {
    return QrEngine.windowsOpenCvTest();
  }

  int windowsZxingTest() {
    return QrEngine.windowsZxingTest();
  }

  /// Windows-only: opens native camera window, detects QR, draws box, when stable returns same type as buildQRScanner final capture.
  Future<FinalCaptureResult?> buildQRScannerWindows() async {
    if (!Platform.isWindows) return null;
    return QrEngine.captureFromCameraWindows();
  }

  /// Windows-only: native camera + decode first QR string ([scan_qr_windows] / [VSScanResult]).
  Future<String?> scanWindows() async {
    if (!Platform.isWindows) return null;
    return QrEngine.scanWindows();
  }

  /// Android / iOS: Flutter camera → gray → [scan_qr_from_gray]. Returns decoded text or null if dismissed.
  Future<String?> scan(BuildContext context) async {
    if (Platform.isWindows) return null;
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const SimpleQrScanPage()),
    );
  }

  Widget buildQRScanner({
    required void Function(String result) onDetect,
    bool stopOnDetect = false,
    void Function(FinalCapturePathsResult result)? onFinalCapturePaths,
    void Function(FinalCaptureResult result)? onFinalCapture,
  }) {
    return QrScannerView(
      onDetect: onDetect,
      stopOnDetect: stopOnDetect,
      onFinalCapturePaths: onFinalCapturePaths,
      onFinalCapture: onFinalCapture,
    );
  }
}
