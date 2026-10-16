import '../protocol.dart';

/// A key the way a Bluetooth keyboard sends it: a HID usage code plus
/// modifier bits.
class HidKey {
  const HidKey(this.usage, [this.modifiers = 0]);

  final int usage;
  final int modifiers;
}

/// Characters for a US keyboard layout, which is what Windows assumes for a
/// Bluetooth keyboard unless told otherwise.
abstract final class HidKeymap {
  static const ctrl = 0x01;
  static const shift = 0x02;
  static const alt = 0x04;
  static const gui = 0x08;

  static const Map<String, HidKey> _symbols = {
    ' ': HidKey(0x2C),
    '\n': HidKey(0x28),
    '\t': HidKey(0x2B),
    '!': HidKey(0x1E, shift),
    '@': HidKey(0x1F, shift),
    '#': HidKey(0x20, shift),
    r'$': HidKey(0x21, shift),
    '%': HidKey(0x22, shift),
    '^': HidKey(0x23, shift),
    '&': HidKey(0x24, shift),
    '*': HidKey(0x25, shift),
    '(': HidKey(0x26, shift),
    ')': HidKey(0x27, shift),
    '-': HidKey(0x2D),
    '_': HidKey(0x2D, shift),
    '=': HidKey(0x2E),
    '+': HidKey(0x2E, shift),
    '[': HidKey(0x2F),
    '{': HidKey(0x2F, shift),
    ']': HidKey(0x30),
    '}': HidKey(0x30, shift),
    r'\': HidKey(0x31),
    '|': HidKey(0x31, shift),
    ';': HidKey(0x33),
    ':': HidKey(0x33, shift),
    "'": HidKey(0x34),
    '"': HidKey(0x34, shift),
    '`': HidKey(0x35),
    '~': HidKey(0x35, shift),
    ',': HidKey(0x36),
    '<': HidKey(0x36, shift),
    '.': HidKey(0x37),
    '>': HidKey(0x37, shift),
    '/': HidKey(0x38),
    '?': HidKey(0x38, shift),
    // Phone keyboards like curly quotes; type the plain ones.
    '‘': HidKey(0x34),
    '’': HidKey(0x34),
    '“': HidKey(0x34, shift),
    '”': HidKey(0x34, shift),
  };

  /// Returns null for characters a US keyboard can't type.
  static HidKey? forChar(int codePoint) {
    if (codePoint >= 0x61 && codePoint <= 0x7A) {
      return HidKey(0x04 + codePoint - 0x61); // a-z
    }
    if (codePoint >= 0x41 && codePoint <= 0x5A) {
      return HidKey(0x04 + codePoint - 0x41, shift); // A-Z
    }
    if (codePoint >= 0x31 && codePoint <= 0x39) {
      return HidKey(0x1E + codePoint - 0x31); // 1-9
    }
    if (codePoint == 0x30) return const HidKey(0x27); // 0
    return _symbols[String.fromCharCode(codePoint)];
  }

  static HidKey? forStroke(KeyStroke stroke) {
    final modifiers =
        stroke.modifiers.fold(0, (bits, m) => bits | _modifierBit(m));
    final key = stroke.key;
    final codePoint = stroke.codePoint;
    if (key != null) return HidKey(_usage(key), modifiers);
    if (codePoint != null) {
      final base = forChar(codePoint);
      return base == null ? null : HidKey(base.usage, base.modifiers | modifiers);
    }
    return modifiers == 0 ? null : HidKey(0, modifiers);
  }

  static int _modifierBit(Modifier m) => switch (m) {
        Modifier.ctrl => ctrl,
        Modifier.shift => shift,
        Modifier.alt => alt,
        Modifier.win => gui,
      };

  static int _usage(PadKey key) => switch (key) {
        PadKey.enter => 0x28,
        PadKey.escape => 0x29,
        PadKey.backspace => 0x2A,
        PadKey.tab => 0x2B,
        PadKey.space => 0x2C,
        PadKey.f1 => 0x3A,
        PadKey.f2 => 0x3B,
        PadKey.f3 => 0x3C,
        PadKey.f4 => 0x3D,
        PadKey.f5 => 0x3E,
        PadKey.f6 => 0x3F,
        PadKey.f7 => 0x40,
        PadKey.f8 => 0x41,
        PadKey.f9 => 0x42,
        PadKey.f10 => 0x43,
        PadKey.f11 => 0x44,
        PadKey.f12 => 0x45,
        PadKey.insert => 0x49,
        PadKey.home => 0x4A,
        PadKey.pageUp => 0x4B,
        PadKey.delete => 0x4C,
        PadKey.end => 0x4D,
        PadKey.pageDown => 0x4E,
        PadKey.right => 0x4F,
        PadKey.left => 0x50,
        PadKey.down => 0x51,
        PadKey.up => 0x52,
      };
}
