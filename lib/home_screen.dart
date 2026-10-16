import 'dart:async';

import 'package:flutter/material.dart';

import 'illustrations.dart';
import 'keyboard_screen.dart';
import 'link_status.dart';
import 'links/pad_link.dart';
import 'pad_controller.dart';
import 'pad_theme.dart';
import 'settings_screen.dart';
import 'speed_controls.dart';
import 'touchpad_screen.dart';

/// Start screen: pick how to connect, set the speed, then open the touchpad
/// or the keyboard.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.controller});

  final PadController controller;

  void _open(BuildContext context, Widget screen) {
    unawaited(
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => screen)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PadBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 11,
                  child: Column(
                    children: [
                      _Header(
                        onHelp: () => showGestureHelp(context),
                        onSettings: () => _open(
                          context,
                          SettingsScreen(settings: controller.settings),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: SingleChildScrollView(
                          child: _ConnectionCard(controller: controller),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 9,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _BigButton(
                          title: 'Touchpad',
                          caption: 'Move, click and scroll',
                          painter: const TouchpadIllustration(),
                          colors: const [Color(0xFF4B4FB0), Color(0xFF22245C)],
                          onTap: () => _open(
                            context,
                            TouchpadScreen(controller: controller),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _BigButton(
                          title: 'Keyboard',
                          caption: 'Type with your phone keyboard',
                          painter: const KeyboardIllustration(),
                          colors: const [Color(0xFF0F8F84), Color(0xFF0A3D39)],
                          onTap: () => _open(
                            context,
                            KeyboardScreen(controller: controller),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onHelp, required this.onSettings});

  final VoidCallback onHelp;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [PadColors.accent, PadColors.teal],
            ),
          ),
          child: const Icon(
            Icons.touch_app_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mouse Pad',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              Text(
                'Your phone as a laptop touchpad',
                style: TextStyle(color: PadColors.textDim, fontSize: 12.5),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'How to use',
          icon: const Icon(Icons.help_outline_rounded),
          onPressed: onHelp,
        ),
        IconButton(
          tooltip: 'Settings',
          icon: const Icon(Icons.settings_outlined),
          onPressed: onSettings,
        ),
      ],
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.controller});

  final PadController controller;

  @override
  Widget build(BuildContext context) {
    final settings = controller.settings;
    return PadCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Connect with'),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<LinkMode>(
                  segments: const [
                    ButtonSegment(
                      value: LinkMode.usb,
                      icon: Icon(Icons.usb_rounded),
                      label: Text('USB cable'),
                    ),
                    ButtonSegment(
                      value: LinkMode.bluetooth,
                      icon: Icon(Icons.bluetooth_rounded),
                      label: Text('Bluetooth'),
                    ),
                  ],
                  selected: {settings.mode},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => settings.mode = s.first,
                ),
                const SizedBox(height: 12),
                StatusLine(status: describeLink(context, controller)),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(),
          ),
          const SectionLabel('Speed'),
          const SizedBox(height: 2),
          SpeedSliders(settings: settings),
        ],
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.title,
    required this.caption,
    required this.painter,
    required this.colors,
    required this.onTap,
  });

  final String title;
  final String caption;
  final CustomPainter painter;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(26);
    return DecoratedBox(
      // The glow sits outside the Material so it follows the rounded shape.
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: [
          BoxShadow(
            color: colors.first.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: shape,
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: shape,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: InkWell(
            borderRadius: shape,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: CustomPaint(
                      painter: painter,
                      child: const SizedBox.expand(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    caption,
                    maxLines: 2,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Open',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_forward_rounded, size: 16),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
