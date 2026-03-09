import 'dart:ui';

class FinalCaptureResult {
  final bool success;
  final bool decoded;
  final String? text;
  final List<Offset> corners;

  final List<int> croppedJpeg;
  final List<int> frameJpeg;

  const FinalCaptureResult({
    required this.success,
    required this.decoded,
    required this.text,
    required this.corners,
    required this.croppedJpeg,
    required this.frameJpeg,
  });
}
