import 'dart:math' as math;

import 'package:flutter/material.dart';

class FramingGuide extends StatelessWidget {
  const FramingGuide({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(painter: _FramingGuidePainter(), size: Size.infinite),
    );
  }
}

class _FramingGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF6EE7B7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final oval = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.43),
      width: size.width * 0.65,
      height: size.height * 0.66,
    );

    const dashAngle = 0.12;
    const gapAngle = 0.07;

    for (double angle = 0; angle < math.pi * 2; angle += dashAngle + gapAngle) {
      canvas.drawArc(oval, angle, dashAngle, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}
