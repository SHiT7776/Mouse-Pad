import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'protocol.dart';
import 'keyboard_bar.dart';
import 'link_status.dart';
import 'links/pad_link.dart';
import 'pad_controller.dart';
import 'pad_theme.dart';
import 'touchpad_screen.dart';

/// Type on the PC with the phone keyboard. Shows what you've typed so far.
class KeyboardScreen extends StatefulWidget {
  const KeyboardScreen({super.key, required this.controller});

  final PadController controller;

  @override
  State<KeyboardScreen> createState() => _KeyboardScreenState();
}

class _KeyboardScreenState extends State<KeyboardScreen> {
  final _focus = FocusNode();
  late final _echo = EchoKeys(widget.controller);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showKeyboard());
  }

  @override
  void dispose() {
    _echo.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _showKeyboard() {
    _focus.requestFocus();
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.show'));
  }

  @override
  Widget build(BuildContext context) {
    final imeVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      body: PadBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: ListenableBuilder(
              listenable: Listenable.merge([widget.controller, _echo]),
              builder: (context, _) {
                final status = describeLink(context, widget.controller);
                return Column(
                  children: [
                    SizedBox(
                      height: 40,
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Back',
                            icon: const Icon(Icons.arrow_back_rounded),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const SizedBox(width: 4),
                          StatusDot(
                              color: status.color,
                              pulsing: !status.connected),
                          const SizedBox(width: 10),
                          Expanded(
                            // With the phone keyboard up there's no room for
                            // the typing area, so the typed text goes here.
                            child: imeVisible && status.connected
                                ? _TypedLine(text: _echo.text)
                                : Text(
                                    status.connected
                                        ? 'Typing on '
                                            '${widget.controller.link.peerName ?? 'your PC'}'
                                        : status.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700),
                                  ),
                          ),
                          if (!status.connected && status.action != null) ...[
                            TextButton(
                                onPressed: status.onAction,
                                child: Text(status.action!)),
                            const SizedBox(width: 4),
                          ],
                          BarButton(
                            icon: Icons.touch_app_outlined,
                            label: 'Touchpad',
                            onPressed: () => Navigator.of(context)
                                .pushReplacement(MaterialPageRoute<void>(
                                    builder: (_) => TouchpadScreen(
                                        controller: widget.controller))),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (imeVisible)
                      const Spacer()
                    else
                      Expanded(
                        child: _TypedText(
                          text: _echo.text,
                          imeVisible: imeVisible,
                          onTap: _showKeyboard,
                          onClear: _echo.clear,
                        ),
                      ),
                    const SizedBox(height: 8),
                    KeyboardBar(
                      keys: _echo,
                      settings: widget.controller.settings,
                      focusNode: _focus,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _TypedText extends StatelessWidget {
  const _TypedText({
    required this.text,
    required this.imeVisible,
    required this.onTap,
    required this.onClear,
  });

  final String text;
  final bool imeVisible;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: PadColors.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: PadColors.border),
        ),
        child: text.isEmpty
            ? Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.keyboard_alt_outlined,
                          color: PadColors.textDim, size: 28),
                      const SizedBox(height: 6),
                      Text(
                        imeVisible
                            ? 'Start typing — it goes straight to your PC'
                            : 'Tap here to open your phone keyboard',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: PadColors.textDim),
                      ),
                    ],
                  ),
                ),
              )
            : Stack(
                children: [
                  Positioned.fill(
                    child: SingleChildScrollView(
                      reverse: true, // keep the newest text in view
                      padding: const EdgeInsets.fromLTRB(16, 12, 48, 12),
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: text),
                          const TextSpan(
                              text: '▌',
                              style: TextStyle(color: PadColors.accent)),
                        ]),
                        style: const TextStyle(fontSize: 18, height: 1.4),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.clear_all_rounded,
                          color: PadColors.textDim),
                      onPressed: onClear,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// The end of what you typed, on one line.
class _TypedLine extends StatelessWidget {
  const _TypedLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final line = text.split('\n').last;
    final tail =
        line.length > 48 ? '…${line.substring(line.length - 48)}' : line;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: PadColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PadColors.border),
      ),
      child: text.isEmpty
          ? const Text('Type on your phone keyboard…',
              maxLines: 1, style: TextStyle(color: PadColors.textDim))
          : Text.rich(
              TextSpan(children: [
                TextSpan(text: tail),
                const TextSpan(
                    text: '▌', style: TextStyle(color: PadColors.accent)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15),
            ),
    );
  }
}

/// Sends typing on to the PC and keeps a copy to show on screen.
class EchoKeys extends ChangeNotifier implements KeySink {
  EchoKeys(this._out);

  final KeySink _out;
  String _text = '';

  String get text => _text;

  @override
  void typeText(String text) {
    _out.typeText(text);
    _append(text);
  }

  @override
  void sendKey(KeyStroke stroke) {
    _out.sendKey(stroke);
    if (stroke.modifiers.isNotEmpty) return; // shortcuts don't type anything
    switch (stroke.key) {
      case PadKey.backspace when _text.isNotEmpty:
        _text = _text.characters.skipLast(1).toString();
        notifyListeners();
      case PadKey.enter:
        _append('\n');
      case PadKey.tab:
        _append('    ');
      case PadKey.space:
        _append(' ');
      default:
        break;
    }
  }

  void clear() {
    _text = '';
    notifyListeners();
  }

  void _append(String s) {
    _text += s;
    if (_text.length > 2000) _text = _text.substring(_text.length - 2000);
    notifyListeners();
  }
}
