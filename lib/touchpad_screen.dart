import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'click_buttons.dart';
import 'keyboard_bar.dart';
import 'link_status.dart';
import 'pad_controller.dart';
import 'pad_theme.dart';
import 'speed_controls.dart';
import 'touchpad_view.dart';

/// The full-screen touchpad.
class TouchpadScreen extends StatefulWidget {
  const TouchpadScreen({super.key, required this.controller});

  final PadController controller;

  @override
  State<TouchpadScreen> createState() => _TouchpadScreenState();
}

class _TouchpadScreenState extends State<TouchpadScreen> {
  final _keyboardFocus = FocusNode();
  bool _keyboardOpen = false;

  /// The keyboard opened because a text box on the PC got focus, so it may
  /// also close by itself when that box loses focus.
  bool _openedForPc = false;
  bool _pcTextFocused = false;

  PadController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_followPcFocus);
  }

  @override
  void dispose() {
    _controller.removeListener(_followPcFocus);
    _keyboardFocus.dispose();
    super.dispose();
  }

  /// Click into a text box on the PC and the phone keyboard pops up.
  void _followPcFocus() {
    final focused = _controller.link.textFieldFocused;
    if (focused == _pcTextFocused) return;
    _pcTextFocused = focused;
    if (!mounted || !_controller.settings.autoKeyboard) return;
    if (focused && !_keyboardOpen) {
      _openKeyboard();
      _openedForPc = true;
    } else if (!focused && _keyboardOpen && _openedForPc) {
      _closeKeyboard();
    }
  }

  void _toggleKeyboard() {
    _keyboardOpen ? _closeKeyboard() : _openKeyboard();
  }

  void _openKeyboard() {
    _openedForPc = false;
    setState(() => _keyboardOpen = true);
    // The bar's hidden text field exists after this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _keyboardFocus.requestFocus();
      unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.show'));
    });
  }

  void _closeKeyboard() {
    _openedForPc = false;
    _keyboardFocus.unfocus();
    setState(() => _keyboardOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final imeVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    return PopScope(
      // A stray edge swipe while using the pad shouldn't throw you out;
      // use the back button in the top bar instead.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _keyboardOpen) _closeKeyboard();
      },
      child: Scaffold(
        body: PadBackground(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: ListenableBuilder(
                listenable: _controller,
                builder: (context, _) {
                  final status = describeLink(context, _controller);
                  return Column(
                    children: [
                      if (!imeVisible) ...[
                        _TopBar(
                          status: status,
                          keyboardOpen: _keyboardOpen,
                          onBack: () => Navigator.of(context).pop(),
                          onSpeed: () =>
                              showSpeedPopup(context, _controller.settings),
                          onKeyboard: _toggleKeyboard,
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (_keyboardOpen) ...[
                        KeyboardBar(
                          key: const ValueKey('keyboard'),
                          keys: _controller,
                          settings: _controller.settings,
                          focusNode: _keyboardFocus,
                          onClose: _closeKeyboard,
                        ),
                        const SizedBox(height: 8),
                      ],
                      Expanded(
                        key: const ValueKey('pad'),
                        child: TouchpadDevice(
                          controller: _controller,
                          compact: imeVisible,
                          overlay: status.connected
                              ? null
                              : NotConnectedOverlay(status: status),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.status,
    required this.keyboardOpen,
    required this.onBack,
    required this.onSpeed,
    required this.onKeyboard,
  });

  final LinkStatus status;
  final bool keyboardOpen;
  final VoidCallback onBack;
  final VoidCallback onSpeed;
  final VoidCallback onKeyboard;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: onBack,
          ),
          const SizedBox(width: 4),
          StatusDot(color: status.color, pulsing: !status.connected),
          const SizedBox(width: 10),
          Expanded(
            child: Text(status.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          BarButton(icon: Icons.speed_rounded, label: 'Speed', onPressed: onSpeed),
          const SizedBox(width: 8),
          BarButton(
            icon: keyboardOpen
                ? Icons.keyboard_hide_outlined
                : Icons.keyboard_outlined,
            label: 'Keyboard',
            selected: keyboardOpen,
            onPressed: onKeyboard,
          ),
        ],
      ),
    );
  }
}

/// The touchpad drawn like a laptop's: the touch surface with Left and Right
/// click buttons along the bottom. Tapping the surface clicks too.
class TouchpadDevice extends StatelessWidget {
  const TouchpadDevice({
    super.key,
    required this.controller,
    this.compact = false,
    this.overlay,
  });

  final PadController controller;

  /// The phone keyboard is up and the pad is short.
  final bool compact;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final radius = compact ? 20.0 : 28.0;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        // A faint top highlight, like light catching a glass touchpad.
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1D2233), Color(0xFF141824)],
        ),
        border: Border.all(color: const Color(0xFF2E3550)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x99000000), blurRadius: 28, offset: Offset(0, 12)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 1),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                Expanded(
                  child: TouchpadView(
                    sink: controller,
                    settings: controller.settings,
                    onShortcut: controller.sendKey,
                    showHints: !compact,
                  ),
                ),
                // With the phone keyboard up there's no room; tapping still clicks.
                if (!compact) ...[
                  const Divider(height: 1),
                  SizedBox(
                    height: 64,
                    child: ClickButtons(
                        sink: controller, settings: controller.settings),
                  ),
                ],
              ],
            ),
            ?overlay,
          ],
        ),
      ),
    );
  }
}
