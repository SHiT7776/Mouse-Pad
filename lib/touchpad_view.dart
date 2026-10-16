import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'protocol.dart';
import 'links/pad_link.dart';
import 'pad_settings.dart';
import 'pad_theme.dart';
import 'touchpad_gestures.dart';

/// The touch surface. Shows a glow under each finger so you can see what the
/// pad thinks you're doing.
class TouchpadView extends StatefulWidget {
  const TouchpadView({
    super.key,
    required this.sink,
    required this.settings,
    required this.onShortcut,
    this.showHints = true,
  });

  final PointerSink sink;
  final PadSettings settings;

  /// Sends the keyboard shortcut for a three/four-finger swipe.
  final void Function(KeyStroke stroke) onShortcut;

  /// Shows the gesture guide while nothing touches the pad.
  final bool showHints;

  @override
  State<TouchpadView> createState() => _TouchpadViewState();
}

class _TouchpadViewState extends State<TouchpadView> {
  late final _gestures = TouchpadGestures(
    sink: widget.sink,
    config: () => widget.settings.gestureConfig,
    onFeedback: _feedback,
    onSwipe: (fingers, direction) =>
        widget.onShortcut(swipeShortcut(fingers, direction)),
  );
  final _repaint = ValueNotifier<int>(0);
  final _idle = ValueNotifier<bool>(true);
  final _dragging = ValueNotifier<bool>(false);

  void _feedback(PadFeedback feedback) {
    if (!widget.settings.haptics) return;
    unawaited(switch (feedback) {
      PadFeedback.click => HapticFeedback.lightImpact(),
      PadFeedback.dragStart => HapticFeedback.mediumImpact(),
    });
  }

  void _changed() {
    _repaint.value++;
    _idle.value = _gestures.touches.isEmpty;
    _dragging.value = _gestures.dragging;
  }

  @override
  void dispose() {
    _gestures.dispose();
    _repaint.dispose();
    _idle.dispose();
    _dragging.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        _gestures.pointerDown(e.pointer, e.localPosition, e.timeStamp);
        _changed();
      },
      onPointerMove: (e) {
        _gestures.pointerMove(e.pointer, e.localPosition, e.timeStamp);
        _changed();
      },
      onPointerUp: (e) {
        _gestures.pointerUp(e.pointer, e.timeStamp);
        _changed();
      },
      onPointerCancel: (e) {
        _gestures.pointerCancel(e.pointer, e.timeStamp);
        _changed();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(
              child: CustomPaint(painter: _SurfacePainter())),
          CustomPaint(painter: _TouchPainter(_gestures, _repaint)),
          if (widget.showHints)
            ValueListenableBuilder(
              valueListenable: _idle,
              builder: (context, idle, _) => AnimatedOpacity(
                opacity: idle ? 1 : 0,
                duration: const Duration(milliseconds: 250),
                child: const Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 20,
                      runSpacing: 6,
                      children: [
                        _Hint(Icons.touch_app_outlined, 'Tap to click'),
                        _Hint(Icons.ads_click_rounded, 'Double-tap to open'),
                        _Hint(Icons.looks_two_outlined,
                            'Two-finger tap: right-click'),
                        _Hint(Icons.swipe_vertical_outlined,
                            'Two fingers: scroll'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ValueListenableBuilder(
            valueListenable: _dragging,
            builder: (context, dragging, _) => dragging
                ? const Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: _Pill('Dragging — lift to drop'),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    const color = Color(0x80FFFFFF);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: color, fontSize: 12.5)),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: PadColors.accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(label,
          style: const TextStyle(
              color: PadColors.accent,
              fontSize: 12,
              fontWeight: FontWeight.w600)),
    );
  }
}

/// A faint dot grid, so the surface reads as something to touch.
class _SurfacePainter extends CustomPainter {
  const _SurfacePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = const Color(0x14FFFFFF);
    const step = 26.0;
    for (var y = step / 2; y < size.height; y += step) {
      for (var x = step / 2; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1.2, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_SurfacePainter oldDelegate) => false;
}

class _TouchPainter extends CustomPainter {
  _TouchPainter(this.gestures, Listenable repaint) : super(repaint: repaint);

  final TouchpadGestures gestures;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (gestures.dragging) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(3), const Radius.circular(24)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = PadColors.accent,
      );
    }
    canvas
      ..save()
      ..clipRect(rect);
    for (final p in gestures.touches) {
      canvas
        ..drawCircle(
          p,
          44,
          Paint()
            ..shader = RadialGradient(colors: [
              PadColors.accent.withValues(alpha: 0.32),
              PadColors.accent.withValues(alpha: 0),
            ]).createShader(Rect.fromCircle(center: p, radius: 44)),
        )
        ..drawCircle(
          p,
          14,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = PadColors.accent.withValues(alpha: 0.7),
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TouchPainter oldDelegate) =>
      oldDelegate.gestures != gestures;
}
