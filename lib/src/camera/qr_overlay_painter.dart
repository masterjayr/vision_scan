import 'dart:ui';

import 'package:flutter/material.dart';

class QrOverlayPainter extends CustomPainter {
  final List<Offset> points;
  final bool show;

  QrOverlayPainter({required this.points, required this.show});

  @override
  void paint(Canvas canvas, Size size) {
    if (!show || points.length != 4) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final path = Path()
      ..moveTo(points[0].dx, points[0].dy)
      ..lineTo(points[1].dx, points[1].dy)
      ..lineTo(points[2].dx, points[2].dy)
      ..lineTo(points[3].dx, points[3].dy)
      ..close();

    canvas.drawPath(path, paint);

    final dot = Paint()..style = PaintingStyle.fill;
    for (final p in points) {
      canvas.drawCircle(p, 4, dot);
    }
  }

  @override
  bool shouldRepaint(covariant QrOverlayPainter oldDelegate) {
    if (oldDelegate.show != show) return true;
    if (points.length != oldDelegate.points.length) return true;
    for (int i = 0; i < points.length; i++) {
      if (points[i] != oldDelegate.points[i]) return true;
    }
    return false;
  }
}
