import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

Uint8List bgraToGray(CameraImage image) {
  final plane = image.planes[0];
  final bytes = plane.bytes;
  final rowStride = plane.bytesPerRow;

  final width = image.width;
  final height = image.height;

  debugPrint(
    "iOS BGRA: width=$width height=$height rowStride=$rowStride expectedRow=${width * 4}",
  );
  final gray = Uint8List(width * height);

  int dst = 0;

  for (int y = 0; y < height; y++) {
    final int rowStart = y * rowStride;

    for (int x = 0; x < width; x++) {
      if (dst >= gray.length) break; // 🔒 HARD SAFETY GUARD

      final int pixelOffset = rowStart + (x * 4);

      final int b = bytes[pixelOffset];
      final int g = bytes[pixelOffset + 1];
      final int r = bytes[pixelOffset + 2];

      gray[dst++] = ((0.299 * r) + (0.587 * g) + (0.114 * b)).toInt();
    }
  }

  return gray;
}
