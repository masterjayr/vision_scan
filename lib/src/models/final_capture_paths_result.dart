import 'dart:ui';

class FinalCapturePathsResult {
  final bool success;
  final bool decoded;
  final String? text;
  final List<Offset> corners;

  final String croppedImagePath;
  final String frameImagePath;

  const FinalCapturePathsResult({
    required this.success,
    required this.decoded,
    required this.text,
    required this.corners,
    required this.croppedImagePath,
    required this.frameImagePath,
  });
}
