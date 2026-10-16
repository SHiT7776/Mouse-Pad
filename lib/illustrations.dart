import 'package:flutter/material.dart';

/// A laptop touchpad with a finger on it, for the home screen.
class TouchpadIllustration extends CustomPainter {
  const TouchpadIllustration();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.shortestSide * 1.25 > size.width
        ? size.width
        : size.shortestSide * 1.25;
    final h = w * 0.78;
    final body = Rect.fromCenter(
        center: size.center(Offset.zero), width: w, height: h);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.035
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.9);
    final shape = RRect.fromRectAndRadius(body, Radius.circular(w * 0.12));
    canvas
      ..drawRRect(shape, Paint()..color = Colors.white.withValues(alpha: 0.06))
      ..drawRRect(shape, line);

    // The click buttons along the bottom edge.
    final split = body.top + h * 0.76;
    canvas
      ..drawLine(Offset(body.left, split), Offset(body.right, split), line)
      ..drawLine(Offset(body.center.dx, split), Offset(body.center.dx, body.bottom),
          line);

    // A finger touching the pad, with a ripple.
    final touch = Offset(body.left + w * 0.62, body.top + h * 0.36);
    canvas
      ..drawCircle(
          touch,
          w * 0.15,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * 0.02
            ..color = Colors.white.withValues(alpha: 0.35))
      ..drawCircle(touch, w * 0.07, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(TouchpadIllustration oldDelegate) => false;
}

/// A small keyboard, for the home screen.
class KeyboardIllustration extends CustomPainter {
  const KeyboardIllustration();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.shortestSide * 1.3 > size.width
        ? size.width
        : size.shortestSide * 1.3;
    final h = w * 0.6;
    final body = Rect.fromCenter(
        center: size.center(Offset.zero), width: w, height: h);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.032
      ..color = Colors.white.withValues(alpha: 0.9);
    final shape = RRect.fromRectAndRadius(body, Radius.circular(w * 0.09));
    canvas
      ..drawRRect(shape, Paint()..color = Colors.white.withValues(alpha: 0.06))
      ..drawRRect(shape, line);

    final key = Paint()..color = Colors.white.withValues(alpha: 0.85);
    final pad = w * 0.09;
    final gap = w * 0.035;
    final rows = [6, 6, 5];
    final keyH = (h - 2 * pad - gap * 3) / 4;
    for (var r = 0; r < rows.length; r++) {
      final count = rows[r];
      final inset = r == 2 ? w * 0.06 : 0.0;
      final rowW = w - 2 * pad - 2 * inset;
      final keyW = (rowW - gap * (count - 1)) / count;
      for (var k = 0; k < count; k++) {
        final left = body.left + pad + inset + k * (keyW + gap);
        final top = body.top + pad + r * (keyH + gap);
        canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(left, top, keyW, keyH),
                Radius.circular(keyH * 0.25)),
            key);
      }
    }
    // Space bar.
    final top = body.top + pad + 3 * (keyH + gap);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(body.left + w * 0.28, top, w * 0.44, keyH),
            Radius.circular(keyH * 0.25)),
        key);
  }

  @override
  bool shouldRepaint(KeyboardIllustration oldDelegate) => false;
}
