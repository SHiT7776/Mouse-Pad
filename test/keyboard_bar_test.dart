import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mouse_pad/keyboard_bar.dart';
import 'package:mouse_pad/links/pad_link.dart';
import 'package:mouse_pad/pad_settings.dart';
import 'package:mouse_pad/protocol.dart';

class FakeKeys implements KeySink {
  final log = <String>[];

  @override
  void typeText(String text) => log.add('type $text');

  @override
  void sendKey(KeyStroke stroke) => log.add('$stroke');
}

void main() {
  group('ImeDiff', () {
    test('typing appends', () {
      final d = ImeDiff.between('..ab', '..abc');
      expect((d.deleted, d.inserted), (0, 'c'));
    });

    test('backspace deletes', () {
      final d = ImeDiff.between('..abc', '..ab');
      expect((d.deleted, d.inserted), (1, ''));
    });

    test('autocorrect retypes only the changed end', () {
      final d = ImeDiff.between('.. helo', '.. hello ');
      expect((d.deleted, d.inserted), (1, 'lo '));
    });

    test('an emoji is one character', () {
      expect(ImeDiff.between('..👋', '..').deleted, 1);
      // 👋 and 👍 share their first UTF-16 unit; don't split them.
      final d = ImeDiff.between('..👋', '..👍');
      expect((d.deleted, d.inserted), (1, '👍'));
    });
  });

  testWidgets('phone keyboard input goes to the PC as text and keys',
      (tester) async {
    final keys = FakeKeys();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: KeyboardBar(
          keys: keys,
          settings: PadSettings.memory(),
          focusNode: focus,
          onClose: () {},
        ),
      ),
    ));
    focus.requestFocus();
    await tester.pump();

    final field = tester.state<EditableTextState>(find.byType(EditableText));
    final padding = '​' * 8;
    void ime(String typed) => field.updateEditingValue(TextEditingValue(
        text: padding + typed,
        selection: TextSelection.collapsed(offset: 8 + typed.length)));

    ime('h');
    ime('hi');
    ime('h'); // Backspace
    expect(keys.log, ['type h', 'type i', 'k - backspace']);

    // Backspace on a field that looks empty eats into the padding.
    field.updateEditingValue(TextEditingValue(
        text: '​' * 7, selection: const TextSelection.collapsed(offset: 7)));
    expect(keys.log.last, 'k - backspace');

    // Ctrl applies to the next key only: Ctrl+C, then a plain "c".
    await tester.tap(find.text('Ctrl'));
    await tester.pump();
    ime('c');
    ime('cc');
    expect(keys.log.sublist(keys.log.length - 2), ['k c u+63', 'type c']);

    await tester.tap(find.text('Esc'));
    await tester.pump();
    expect(keys.log.last, 'k - esc');

    // Enter from the phone keyboard.
    field.performAction(TextInputAction.newline);
    expect(keys.log.last, 'k - enter');
    expect(focus.hasFocus, isTrue, reason: 'keyboard stays up');
  });
}
