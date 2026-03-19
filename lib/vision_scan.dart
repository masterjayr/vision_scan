import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:vision_scan/src/camera/qr_scanner_view.dart';
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
