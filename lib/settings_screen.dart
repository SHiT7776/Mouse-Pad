import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pad_settings.dart';
import 'pad_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.settings});

  final PadSettings settings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                const _Section('Pointer'),
                _SliderTile(
                  title: 'Pointer speed',
                  value: settings.pointerSpeed,
                  min: 0.3,
                  max: 3,
                  onChanged: (v) => settings.pointerSpeed = v,
                ),
                SwitchListTile(
                  title: const Text('Pointer acceleration'),
                  subtitle: const Text(
                      'Quick flicks go further; slow moves stay precise'),
                  value: settings.acceleration,
                  onChanged: (v) => settings.acceleration = v,
                ),
                const _Section('Scrolling'),
                _SliderTile(
                  title: 'Scroll speed',
                  value: settings.scrollSpeed,
                  min: 0.25,
                  max: 4,
                  onChanged: (v) => settings.scrollSpeed = v,
                ),
                SwitchListTile(
                  title: const Text('Natural scrolling'),
                  subtitle: const Text(
                      'Content follows your fingers, like on the phone'),
                  value: settings.naturalScroll,
                  onChanged: (v) => settings.naturalScroll = v,
                ),
                const _Section('Clicking and typing'),
                SwitchListTile(
                  title: const Text('Tap to click'),
                  subtitle: const Text(
                      'When off, click with the buttons under the pad'),
                  value: settings.tapToClick,
                  onChanged: (v) => settings.tapToClick = v,
                ),
                SwitchListTile(
                  title: const Text('Keyboard pops up by itself'),
                  subtitle: const Text(
                      'When you tap into a text box on the PC, like a search '
                      'box (USB cable)'),
                  value: settings.autoKeyboard,
                  onChanged: (v) => settings.autoKeyboard = v,
                ),
                SwitchListTile(
                  title: const Text('Keyboard suggestions'),
                  subtitle: const Text(
                      'Let the phone keyboard autocorrect and suggest words'),
                  value: settings.smartKeyboard,
                  onChanged: (v) => settings.smartKeyboard = v,
                ),
                SwitchListTile(
                  title: const Text('Vibrate on click'),
                  value: settings.haptics,
                  onChanged: (v) => settings.haptics = v,
                ),
                const _Section('USB'),
                ListTile(
                  title: const Text('Port'),
                  subtitle: Text(
                      '${settings.port} — must match Mouse Pad Receiver on '
                      'the PC'),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editPort(context),
                ),
                const _Section('Gestures'),
                const GestureHelp(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editPort(BuildContext context) async {
    final port = await showDialog<int>(
      context: context,
      builder: (_) => _PortDialog(initial: settings.port),
    );
    if (port != null) settings.port = port;
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(title.toUpperCase(),
          style: const TextStyle(
              color: PadColors.accent,
              fontSize: 12,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600)),
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        onChanged: onChanged,
      ),
      trailing: SizedBox(
        width: 44,
        child: Text('${value.toStringAsFixed(value < 1 ? 2 : 1)}×',
            textAlign: TextAlign.end),
      ),
    );
  }
}

/// What each touchpad gesture does.
class GestureHelp extends StatelessWidget {
  const GestureHelp({super.key});

  static const _rows = [
    (Icons.touch_app_outlined, 'Move one finger', 'Moves the pointer'),
    (Icons.ads_click, 'Tap', 'Left click. Double tap = double click'),
    (Icons.open_with, 'Tap, then touch again and move', 'Drag (lift to drop)'),
    (Icons.back_hand_outlined, 'Hold Left and move with another finger',
        'Drag, like on a laptop'),
    (Icons.looks_two_outlined, 'Two-finger tap', 'Right click'),
    (Icons.looks_3_outlined, 'Three-finger tap', 'Middle click'),
    (Icons.swipe_vertical_outlined, 'Two-finger drag, or the strip on the right',
        'Scroll'),
    (Icons.pinch_outlined, 'Pinch', 'Zoom in and out'),
    (Icons.swipe_up_outlined, 'Three fingers up / down',
        'Task View / show the desktop'),
    (Icons.swipe_outlined, 'Three fingers left or right',
        'Switch to the previous app'),
    (Icons.view_carousel_outlined, 'Four fingers left or right',
        'Switch virtual desktops'),
    (Icons.keyboard_outlined, 'Ctrl / Shift / Alt / Win',
        'Apply to the next key you press. Long-press one to press it alone '
            '(Win alone opens Start)'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (icon, title, detail) in _rows)
          ListTile(
            leading: Icon(icon, color: PadColors.textDim),
            title: Text(title),
            subtitle: Text(detail),
          ),
      ],
    );
  }
}

class _PortDialog extends StatefulWidget {
  const _PortDialog({required this.initial});

  final int initial;

  @override
  State<_PortDialog> createState() => _PortDialogState();
}

class _PortDialogState extends State<_PortDialog> {
  late final _controller = TextEditingController(text: '${widget.initial}');
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final port = int.tryParse(_controller.text.trim());
    if (port == null || port < 1024 || port > 65535) {
      setState(() => _error = 'Use a number from 1024 to 65535');
      return;
    }
    Navigator.pop(context, port);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('USB port'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(errorText: _error),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

Future<void> showGestureHelp(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text('How to use the touchpad',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              ),
              GestureHelp(),
            ],
          ),
        ),
      ),
    );
