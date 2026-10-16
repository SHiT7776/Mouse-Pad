import 'package:flutter/material.dart';

import 'pad_settings.dart';
import 'pad_theme.dart';

/// Pointer and scroll speed sliders.
class SpeedSliders extends StatelessWidget {
  const SpeedSliders({super.key, required this.settings});

  final PadSettings settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SpeedRow(
            icon: Icons.mouse_outlined,
            label: 'Pointer',
            value: settings.pointerSpeed,
            min: 0.3,
            max: 3,
            onChanged: (v) => settings.pointerSpeed = v,
          ),
          _SpeedRow(
            icon: Icons.swap_vert_rounded,
            label: 'Scroll',
            value: settings.scrollSpeed,
            min: 0.25,
            max: 4,
            onChanged: (v) => settings.scrollSpeed = v,
          ),
        ],
      ),
    );
  }
}

class _SpeedRow extends StatelessWidget {
  const _SpeedRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Icon(icon, size: 18, color: PadColors.textDim),
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            child: Text(label, style: const TextStyle(fontSize: 14)),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 42,
            child: Text(
              '${value.toStringAsFixed(1)}×',
              textAlign: TextAlign.end,
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small card that drops down from the top bar with the speed sliders.
Future<void> showSpeedPopup(BuildContext context, PadSettings settings) =>
    showDialog<void>(
      context: context,
      barrierColor: Colors.black38,
      builder: (context) => SafeArea(
        child: Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 52, 12, 12),
            child: Material(
              color: PadColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: PadColors.border),
              ),
              child: SizedBox(
                width: 380,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 4, 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text('Speed',
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w700)),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: SpeedSliders(settings: settings),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
