import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'protocol.dart';
import 'links/pad_link.dart';
import 'pad_settings.dart';
import 'pad_theme.dart';

/// Left and right click buttons along the bottom of the touchpad, like a
/// laptop's. Hold Left with your thumb and move with another finger to drag.
class ClickButtons extends StatelessWidget {
  const ClickButtons({super.key, required this.sink, required this.settings});

  final PointerSink sink;
  final PadSettings settings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ClickButton(
              button: PadButton.left,
              label: 'Left click',
              sink: sink,
              settings: settings),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _ClickButton(
              button: PadButton.right,
              label: 'Right click',
              sink: sink,
              settings: settings),
        ),
      ],
    );
  }
}

class _ClickButton extends StatefulWidget {
  const _ClickButton({
    required this.button,
    required this.label,
    required this.sink,
    required this.settings,
  });

  final PadButton button;
  final String label;
  final PointerSink sink;
  final PadSettings settings;

  @override
  State<_ClickButton> createState() => _ClickButtonState();
}

class _ClickButtonState extends State<_ClickButton> {
  /// Fingers on the button; it stays pressed until the last one lifts.
  final Set<int> _fingers = {};

  void _down(PointerDownEvent e) {
    _fingers.add(e.pointer);
    if (_fingers.length > 1) return;
    setState(() {});
    widget.sink.button(widget.button, down: true);
    if (widget.settings.haptics) unawaited(HapticFeedback.selectionClick());
  }

  void _up(PointerEvent e) {
    if (!_fingers.remove(e.pointer) || _fingers.isNotEmpty) return;
    setState(() {});
    widget.sink.button(widget.button, down: false);
  }

  @override
  void dispose() {
    // Never leave the button held if this disappears mid-press.
    if (_fingers.isNotEmpty) widget.sink.button(widget.button, down: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pressed = _fingers.isNotEmpty;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 70),
        alignment: Alignment.center,
        color: pressed
            ? PadColors.accent.withValues(alpha: 0.22)
            : const Color(0x0DFFFFFF),
        child: Text(
          widget.label,
          style: TextStyle(
            color: pressed ? Colors.white : PadColors.textDim,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}
