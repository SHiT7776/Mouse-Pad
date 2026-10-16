import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'protocol.dart';
import 'links/pad_link.dart';
import 'pad_settings.dart';
import 'pad_theme.dart';

/// What the phone keyboard changed between two versions of the hidden field.
class ImeDiff {
  const ImeDiff(this.deleted, this.inserted);

  /// How many characters to erase with Backspace on the PC.
  final int deleted;
  final String inserted;

  static ImeDiff between(String before, String after) {
    final limit = math.min(before.length, after.length);
    var common = 0;
    while (common < limit &&
        before.codeUnitAt(common) == after.codeUnitAt(common)) {
      common++;
    }
    // Never split an emoji (a surrogate pair) in half.
    if (common > 0 && _isHighSurrogate(before.codeUnitAt(common - 1))) {
      common--;
    }
    return ImeDiff(
        before.substring(common).runes.length, after.substring(common));
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
}

/// The typing bar: PC keys the phone keyboard lacks (Esc, Ctrl, arrows,
/// F-keys…) plus an invisible text field that brings up the phone keyboard.
/// Whatever you type goes to the PC as you type it.
class KeyboardBar extends StatefulWidget {
  const KeyboardBar({
    super.key,
    required this.keys,
    required this.settings,
    required this.focusNode,
    this.onClose,
  });

  final KeySink keys;
  final PadSettings settings;
  final FocusNode focusNode;

  /// Shows a close button when set.
  final VoidCallback? onClose;

  @override
  State<KeyboardBar> createState() => _KeyboardBarState();
}

class _KeyboardBarState extends State<KeyboardBar> {
  /// Zero-width spaces kept in the hidden field, so Backspace still has
  /// something to delete when the field looks empty.
  static const _padding = '​​​​​​​​';
  static const _fresh = TextEditingValue(
      text: _padding, selection: TextSelection.collapsed(offset: 8));

  final _text = TextEditingController.fromValue(_fresh);
  String _last = _padding;
  final Set<Modifier> _armed = {};

  KeySink get _pad => widget.keys;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final diff = ImeDiff.between(_last, value);
    _last = value;
    for (var i = 0; i < diff.deleted; i++) {
      _key(PadKey.backspace);
    }
    if (diff.inserted.isNotEmpty) _type(diff.inserted);

    // Keep the field short, but never yank text the keyboard is composing.
    final current = _text.value;
    final composing =
        current.composing.isValid && !current.composing.isCollapsed;
    if (!composing &&
        (current.text.length > 48 || !current.text.startsWith(_padding))) {
      _text.value = _fresh;
      _last = _padding;
    }
  }

  void _type(String text) {
    final plain = StringBuffer();
    void flush() {
      if (plain.isEmpty) return;
      _pad.typeText(plain.toString());
      plain.clear();
    }

    for (final rune in text.runes) {
      if (rune == 0x200B) continue; // our own padding
      if (rune == 0x0A) {
        flush();
        _key(PadKey.enter);
      } else if (rune == 0x09) {
        flush();
        _key(PadKey.tab);
      } else if (_armed.isNotEmpty) {
        // Ctrl armed + "c" = Ctrl+C.
        flush();
        _pad.sendKey(KeyStroke.char(rune, modifiers: {..._armed}));
        _disarm();
      } else {
        plain.writeCharCode(rune);
      }
    }
    flush();
  }

  void _key(PadKey key) {
    _pad.sendKey(KeyStroke.key(key, modifiers: {..._armed}));
    _disarm();
  }

  void _disarm() {
    if (_armed.isNotEmpty) setState(_armed.clear);
  }

  void _toggle(Modifier m) {
    setState(() => _armed.contains(m) ? _armed.remove(m) : _armed.add(m));
  }

  /// Long press: press the modifier on its own (Win alone opens Start).
  void _alone(Modifier m) {
    _pad.sendKey(KeyStroke.modifiersOnly({..._armed, m}));
    _disarm();
    if (widget.settings.haptics) unawaited(HapticFeedback.mediumImpact());
  }

  void _toggleIme(bool visible) {
    if (visible) {
      unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
    } else {
      widget.focusNode.requestFocus();
      unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.show'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final imeVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final smart = widget.settings.smartKeyboard;
    const gap = SizedBox(width: 10);
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: PadColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PadColors.border),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: imeVisible ? 'Hide keyboard' : 'Show keyboard',
            icon: Icon(imeVisible
                ? Icons.keyboard_hide_outlined
                : Icons.keyboard_outlined),
            onPressed: () => _toggleIme(imeVisible),
          ),
          SizedBox(
            width: 1,
            height: 1,
            child: EditableText(
              controller: _text,
              focusNode: widget.focusNode,
              style: const TextStyle(fontSize: 1, color: Colors.transparent),
              cursorColor: Colors.transparent,
              backgroundCursorColor: Colors.transparent,
              showCursor: false,
              enableInteractiveSelection: false,
              autocorrect: smart,
              enableSuggestions: smart,
              enableIMEPersonalizedLearning: smart,
              // A "password" keyboard sends exactly the keys you press.
              keyboardType:
                  smart ? TextInputType.text : TextInputType.visiblePassword,
              textInputAction: TextInputAction.newline,
              textCapitalization: TextCapitalization.none,
              onChanged: _onChanged,
              onSubmitted: (_) => _key(PadKey.enter),
              onEditingComplete: () {}, // keep the keyboard up after Enter
            ),
          ),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [
                _KeyCap(label: 'Esc', onPress: () => _key(PadKey.escape)),
                _KeyCap(label: 'Tab', onPress: () => _key(PadKey.tab)),
                gap,
                for (final m in Modifier.values)
                  _ModifierCap(
                    label: switch (m) {
                      Modifier.ctrl => 'Ctrl',
                      Modifier.shift => 'Shift',
                      Modifier.alt => 'Alt',
                      Modifier.win => 'Win',
                    },
                    armed: _armed.contains(m),
                    onTap: () => _toggle(m),
                    onLongPress: () => _alone(m),
                  ),
                gap,
                _KeyCap(
                    icon: Icons.arrow_back,
                    repeat: true,
                    onPress: () => _key(PadKey.left)),
                _KeyCap(
                    icon: Icons.arrow_upward,
                    repeat: true,
                    onPress: () => _key(PadKey.up)),
                _KeyCap(
                    icon: Icons.arrow_downward,
                    repeat: true,
                    onPress: () => _key(PadKey.down)),
                _KeyCap(
                    icon: Icons.arrow_forward,
                    repeat: true,
                    onPress: () => _key(PadKey.right)),
                gap,
                _KeyCap(
                    icon: Icons.backspace_outlined,
                    repeat: true,
                    onPress: () => _key(PadKey.backspace)),
                _KeyCap(
                    icon: Icons.keyboard_return,
                    onPress: () => _key(PadKey.enter)),
                _KeyCap(
                    label: 'Del',
                    repeat: true,
                    onPress: () => _key(PadKey.delete)),
                gap,
                _KeyCap(label: 'Home', onPress: () => _key(PadKey.home)),
                _KeyCap(label: 'End', onPress: () => _key(PadKey.end)),
                _KeyCap(
                    label: 'PgUp',
                    repeat: true,
                    onPress: () => _key(PadKey.pageUp)),
                _KeyCap(
                    label: 'PgDn',
                    repeat: true,
                    onPress: () => _key(PadKey.pageDown)),
                gap,
                for (final (i, f) in [
                  PadKey.f1, PadKey.f2, PadKey.f3, PadKey.f4, //
                  PadKey.f5, PadKey.f6, PadKey.f7, PadKey.f8,
                  PadKey.f9, PadKey.f10, PadKey.f11, PadKey.f12,
                ].indexed)
                  _KeyCap(label: 'F${i + 1}', onPress: () => _key(f)),
              ],
            ),
          ),
          if (widget.onClose case final onClose?)
            IconButton(
              tooltip: 'Close keyboard',
              icon: const Icon(Icons.close),
              onPressed: onClose,
            ),
        ],
      ),
    );
  }
}

/// A key that fires when touched and, if [repeat], keeps firing while held.
class _KeyCap extends StatefulWidget {
  const _KeyCap(
      {this.label, this.icon, required this.onPress, this.repeat = false});

  final String? label;
  final IconData? icon;
  final VoidCallback onPress;
  final bool repeat;

  @override
  State<_KeyCap> createState() => _KeyCapState();
}

class _KeyCapState extends State<_KeyCap> {
  Timer? _timer;
  bool _down = false;

  void _start() {
    setState(() => _down = true);
    widget.onPress();
    if (!widget.repeat) return;
    _timer = Timer(const Duration(milliseconds: 400), () {
      _timer = Timer.periodic(
          const Duration(milliseconds: 60), (_) => widget.onPress());
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    if (_down) setState(() => _down = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _start(),
      onTapUp: (_) => _stop(),
      onTapCancel: _stop,
      child: _Cap(
        highlighted: _down,
        child: widget.icon != null
            ? Icon(widget.icon, size: 18)
            : Text(widget.label ?? ''),
      ),
    );
  }
}

class _ModifierCap extends StatelessWidget {
  const _ModifierCap({
    required this.label,
    required this.armed,
    required this.onTap,
    required this.onLongPress,
  });

  final String label;
  final bool armed;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: _Cap(highlighted: armed, accent: armed, child: Text(label)),
    );
  }
}

class _Cap extends StatelessWidget {
  const _Cap(
      {required this.child, this.highlighted = false, this.accent = false});

  final Widget child;
  final bool highlighted;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final color = accent
        ? PadColors.accent
        : highlighted
            ? Colors.white
            : PadColors.textDim;
    return Container(
      constraints: const BoxConstraints(minWidth: 46),
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent
            ? PadColors.accent.withValues(alpha: 0.18)
            : highlighted
                ? PadColors.pressed
                : PadColors.surfaceHigh,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: accent ? PadColors.accent : PadColors.border),
      ),
      child: IconTheme.merge(
        data: IconThemeData(color: color),
        child: DefaultTextStyle.merge(
          style: TextStyle(
              color: color, fontSize: 13, fontWeight: FontWeight.w600),
          child: child,
        ),
      ),
    );
  }
}
