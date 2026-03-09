import 'dart:ui';

class FrameDetectionResult {
  final bool detected;
  final bool decoded;
  final String? text;
  final List<Offset> corners;

  const FrameDetectionResult({
    required this.detected,
    required this.decoded,
    required this.text,
    required this.corners,
  });

  bool get hasCorners => corners.length == 4 && detected;
}
