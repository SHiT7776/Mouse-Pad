import 'package:flutter/material.dart';

abstract final class PadColors {
  static const background = Color(0xFF0B0D12);
  static const surface = Color(0xFF151922);
  static const surfaceHigh = Color(0xFF1D2230);
  static const pressed = Color(0xFF2A3146);
  static const border = Color(0xFF242A3A);
  static const accent = Color(0xFF7B8CFF);
  static const teal = Color(0xFF2DD4BF);
  static const connected = Color(0xFF34D399);
  static const waiting = Color(0xFFFBBF24);
  static const danger = Color(0xFFF87171);
  static const text = Color(0xFFF2F4F8);
  static const textDim = Color(0xFF9AA3B2);
}

ThemeData buildPadTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: PadColors.accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: PadColors.accent,
    onPrimary: PadColors.background,
    surface: PadColors.background,
    onSurface: PadColors.text,
    onSurfaceVariant: PadColors.textDim,
    surfaceContainer: PadColors.surface,
    surfaceContainerHigh: PadColors.surfaceHigh,
    surfaceContainerHighest: PadColors.pressed,
    outlineVariant: PadColors.border,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: PadColors.background,
    visualDensity: VisualDensity.compact,
    dividerTheme: const DividerThemeData(color: PadColors.border, space: 1),
    sliderTheme: const SliderThemeData(
      trackHeight: 6,
      activeTrackColor: PadColors.accent,
      inactiveTrackColor: PadColors.border,
      thumbColor: Colors.white,
      overlayColor: Color(0x337B8CFF),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? PadColors.accent.withValues(alpha: 0.22)
                : Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? PadColors.text
                : PadColors.textDim),
        side: const WidgetStatePropertyAll(BorderSide(color: PadColors.border)),
        textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: PadColors.surface,
      showDragHandle: true,
      constraints: BoxConstraints(maxWidth: 680),
    ),
  );
}

/// The app's backdrop: near-black with a soft glow of the accent color.
class PadBackground extends StatelessWidget {
  const PadBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.9, -1.2),
          radius: 1.6,
          colors: [Color(0x2A7B8CFF), PadColors.background],
        ),
      ),
      child: child,
    );
  }
}

/// A rounded panel.
class PadCard extends StatelessWidget {
  const PadCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PadColors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: PadColors.border),
      ),
      child: child,
    );
  }
}

/// Small caps label above a group of controls.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: PadColors.accent,
        fontSize: 11.5,
        letterSpacing: 1.3,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// Green when connected; pulses while waiting.
class StatusDot extends StatefulWidget {
  const StatusDot({super.key, required this.color, required this.pulsing});

  final Color color;
  final bool pulsing;

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100), value: 1);

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.pulsing && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.pulsing) {
      _pulse
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_pulse),
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: widget.color.withValues(alpha: 0.6), blurRadius: 8),
          ],
        ),
      ),
    );
  }
}

/// A numbered step in a how-to list.
class StepRow extends StatelessWidget {
  const StepRow(this.number, this.text, {super.key});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: PadColors.accent.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Text('$number',
                style: const TextStyle(
                    color: PadColors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(text, style: const TextStyle(height: 1.35)),
            ),
          ),
        ],
      ),
    );
  }
}

/// A rounded button with an icon and a word, used in the top bars.
class BarButton extends StatelessWidget {
  const BarButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: selected
            ? PadColors.accent.withValues(alpha: 0.28)
            : PadColors.surfaceHigh,
        foregroundColor: selected ? PadColors.text : PadColors.textDim,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        side: BorderSide(
            color: selected ? PadColors.accent : PadColors.border),
      ),
    );
  }
}
