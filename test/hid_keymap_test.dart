import 'package:flutter_test/flutter_test.dart';
import 'package:mouse_pad/links/hid_keymap.dart';
import 'package:mouse_pad/protocol.dart';

void main() {
  HidKey key(String char) => HidKeymap.forChar(char.runes.single)!;

  test('letters, digits and symbols on a US keyboard', () {
    expect(key('a').usage, 0x04);
    expect(key('z').usage, 0x1D);
    expect((key('A').usage, key('A').modifiers), (0x04, HidKeymap.shift));
    expect(key('1').usage, 0x1E);
    expect(key('0').usage, 0x27);
    expect((key('@').usage, key('@').modifiers), (0x1F, HidKeymap.shift));
    expect(key(' ').usage, 0x2C);
    expect((key('?').usage, key('?').modifiers), (0x38, HidKeymap.shift));
    expect(key('/').modifiers, 0);
  });

  test("characters a US keyboard can't type are skipped", () {
    expect(HidKeymap.forChar('ñ'.runes.single), isNull);
    expect(HidKeymap.forChar('👋'.runes.single), isNull);
  });

  test('shortcuts combine the key with its modifiers', () {
    final copy = HidKeymap.forStroke(
        const KeyStroke.char(0x63, modifiers: {Modifier.ctrl}))!;
    expect((copy.usage, copy.modifiers), (0x06, HidKeymap.ctrl));

    final nextDesktop = HidKeymap.forStroke(const KeyStroke.key(PadKey.right,
        modifiers: {Modifier.ctrl, Modifier.win}))!;
    expect((nextDesktop.usage, nextDesktop.modifiers),
        (0x4F, HidKeymap.ctrl | HidKeymap.gui));

    final start =
        HidKeymap.forStroke(const KeyStroke.modifiersOnly({Modifier.win}))!;
    expect((start.usage, start.modifiers), (0, HidKeymap.gui));
  });

  test('every named key has a usage code', () {
    for (final k in PadKey.values) {
      expect(HidKeymap.forStroke(KeyStroke.key(k))!.usage, greaterThan(0),
          reason: k.name);
    }
  });
}
