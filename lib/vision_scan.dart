import 'dart:typed_data';

import 'package:vision_scan/src/camera/qr_scanner_view.dart';
import 'package:vision_scan/src/engine/qr_engine.dart';
import 'package:flutter/material.dart';

class VisionScan {
  String? decodeQRCode(Uint8List grayBytes, int width, int height) {
    return QrEngine.decodeQRCode(grayBytes, width, height);
  }

  Widget buildQRScanner({required void Function(String result) onDetect}) {
    return QrScannerView(onDetect: onDetect);
  }
}
