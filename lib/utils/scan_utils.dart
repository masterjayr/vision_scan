import 'dart:ui';

class FittedRect {
  final Size input;
  final Size output;
  final Rect dst;

  const FittedRect(this.input, this.output, this.dst);
}

FittedRect fittedCoverRect(Size input, Size output) {
  final inputAspect = input.width / input.height;
  final outputAspect = output.width / output.height;

  double scale;

  if (outputAspect > inputAspect) {
    scale = output.width / input.width;
  } else {
    scale = output.height / input.height;
  }

  final drawW = input.width * scale;
  final drawH = input.height * scale;

  final left = (output.width - drawW) / 2.0;
  final top = (output.height - drawH) / 2.0;

  return FittedRect(input, output, Rect.fromLTWH(left, top, drawW, drawH));
}

/// Like BoxFit.contain: scale so input fits inside output, centered (letterboxing).
FittedRect fittedContainRect(Size input, Size output) {
  final scaleW = output.width / input.width;
  final scaleH = output.height / input.height;
  final scale = scaleW < scaleH ? scaleW : scaleH;

  final drawW = input.width * scale;
  final drawH = input.height * scale;

  final left = (output.width - drawW) / 2.0;
  final top = (output.height - drawH) / 2.0;

  return FittedRect(input, output, Rect.fromLTWH(left, top, drawW, drawH));
}

/// Scale to fill output height and center horizontally when possible. Use when
/// the camera preview fills height with letterbox on the sides. If filling height
/// would make width exceed the widget, falls back to contain so the rect stays inside.
FittedRect fittedRectFillHeight(Size input, Size output) {
  final scaleH = output.height / input.height;
  final scaleW = output.width / input.width;
  double scale = scaleH;
  double drawW = input.width * scale;
  double drawH = output.height;
  double left = (output.width - drawW) / 2.0;
  double top = 0.0;
  if (drawW > output.width) {
    scale = scaleW < scaleH ? scaleW : scaleH;
    drawW = input.width * scale;
    drawH = input.height * scale;
    left = (output.width - drawW) / 2.0;
    top = (output.height - drawH) / 2.0;
  }
  return FittedRect(input, output, Rect.fromLTWH(left, top, drawW, drawH));
}

/// Transforms a point from raw camera image coordinates to display coordinates.
/// The camera image stream comes in sensor orientation (often landscape).
/// The CameraPreview displays it rotated to match the device. This converts
/// image (x,y) to the coordinate system of what the user actually sees.
Offset imagePointToDisplay({
  required Offset imagePoint,
  required double imageWidth,
  required double imageHeight,
  required int sensorOrientation,
  bool isIOS = false,
}) {
  final x = imagePoint.dx;
  final y = imagePoint.dy;
  final w = imageWidth;
  final h = imageHeight;

  // iOS delivers frames already in portrait orientation — no rotation needed
  if (isIOS) return Offset(x, y);

  switch (sensorOrientation) {
    case 90:
      return Offset(y, w - x);
    case 180:
      return Offset(w - x, h - y);
    case 270:
      return Offset(h - y, x);
    case 0:
    default:
      return Offset(x, y);
  }
}

/// Returns the display dimensions for the rotated preview.
Size displaySizeFromImage({
  required double imageWidth,
  required double imageHeight,
  required int sensorOrientation,
  bool isIOS = false,
}) {
  // iOS frame is already portrait — dimensions are correct as-is
  if (isIOS) return Size(imageWidth, imageHeight);

  if (sensorOrientation == 90 || sensorOrientation == 270) {
    return Size(imageHeight, imageWidth);
  }
  return Size(imageWidth, imageHeight);
}

/// Maps a point from camera image space to widget space.
/// [imageSize] – size of the frame we're detecting in (image.width x image.height).
/// [widgetSize] – size of the overlay/canvas.
/// [sensorOrientation] – camera sensor orientation (0, 90, 180, 270).
/// [previewSize] – optional; when provided, fit uses preview aspect so the overlay
///   matches the preview (avoids slim/stretched box). Point is scaled image→preview when needed.
Offset mapImageToWidget({
  required Offset imagePoint,
  required Size imageSize,
  required Size widgetSize,
  int sensorOrientation = 0,
  Size? previewSize,
  bool isIOS = false,
}) {
  final displayPoint = imagePointToDisplay(
    imagePoint: imagePoint,
    imageWidth: imageSize.width,
    imageHeight: imageSize.height,
    sensorOrientation: sensorOrientation,
    isIOS: isIOS, // ← pass through
  );

  final imageDisplaySize = displaySizeFromImage(
    imageWidth: imageSize.width,
    imageHeight: imageSize.height,
    sensorOrientation: sensorOrientation,
    isIOS: isIOS, // ← pass through
  );

  final Size displaySizeForFit;
  double px;
  double py;

  if (previewSize != null &&
      (previewSize.width != imageSize.width ||
          previewSize.height != imageSize.height)) {
    displaySizeForFit = displaySizeFromImage(
      imageWidth: previewSize.width,
      imageHeight: previewSize.height,
      sensorOrientation: sensorOrientation,
    );
    px = displayPoint.dx * (displaySizeForFit.width / imageDisplaySize.width);
    py = displayPoint.dy * (displaySizeForFit.height / imageDisplaySize.height);
  } else {
    displaySizeForFit = imageDisplaySize;
    px = displayPoint.dx;
    py = displayPoint.dy;
  }

  // Fill height + center width: correct left-right, overlay reaches top and bottom
  final fit = fittedCoverRect(displaySizeForFit, widgetSize);
  final scaleX = fit.dst.width / displaySizeForFit.width;
  final scaleY = fit.dst.height / displaySizeForFit.height;

  return Offset(fit.dst.left + px * scaleX, fit.dst.top + py * scaleY);
}

bool isStableCorners(
  List<Offset> prev,
  List<Offset> cur, {
  double maxAvgDeltaPx = 4.0,
}) {
  if (prev.length != 4 || cur.length != 4) return false;

  double sum = 0;

  for (int i = 0; i < 4; i++) {
    sum += (prev[i] - cur[i]).distance;
  }
  final avg = sum / 4.0;

  return avg <= maxAvgDeltaPx;
}

bool cornersLookValid(List<Offset> c) {
  if (c.length != 4) return false;

  double area = 0;
  for (int i = 0; i < 4; i++) {
    final p1 = c[i];
    final p2 = c[(i + 1) % 4];
    area += (p1.dx * p2.dy) - (p2.dx * p1.dy);
  }
  area = area.abs() / 2.0;

  return area > 2000; // adjust based on resolution.
}

/// Average distance (in same units as points) between previous and current corners.
double averageCornerDelta(List<Offset> previous, List<Offset> current) {
  if (previous.length != 4 || current.length != 4) return 0;
  double sum = 0;
  for (int i = 0; i < 4; i++) {
    sum += (previous[i] - current[i]).distance;
  }
  return sum / 4;
}

List<Offset> smoothCorners(
  List<Offset> previous,
  List<Offset> current, {
  double alpha =
      0.92, // 0.0 → old only, 1.0 → new only (higher = more reactive)
}) {
  if (previous.length != 4 || current.length != 4) return current;

  return List.generate(4, (i) {
    return Offset(
      previous[i].dx * (1 - alpha) + current[i].dx * alpha,
      previous[i].dy * (1 - alpha) + current[i].dy * alpha,
    );
  });
}
