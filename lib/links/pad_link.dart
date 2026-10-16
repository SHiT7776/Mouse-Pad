import 'package:flutter/foundation.dart';

import '../protocol.dart';

enum LinkMode { usb, bluetooth }

/// Receives pointer actions from the touchpad.
abstract interface class PointerSink {
  void move(int dx, int dy);

  /// 120 units = one wheel notch; positive [vertical] scrolls up, positive
  /// [horizontal] scrolls right.
  void scroll(int vertical, int horizontal);

  /// Pinch zoom in wheel notches; positive zooms in.
  void zoom(int steps);
  void button(PadButton button, {required bool down});
  void click(PadButton button);
}

/// Receives typing from the keyboard bar.
abstract interface class KeySink {
  void typeText(String text);
  void sendKey(KeyStroke stroke);
}

/// A way to reach the PC: through the USB cable to the receiver app, or
/// straight to Windows as a Bluetooth touchpad and keyboard.
abstract class PadLink extends ChangeNotifier implements PointerSink, KeySink {
  bool get connected;

  /// The PC's name once connected.
  String? get peerName;

  /// A text box on the PC has keyboard focus, so the phone keyboard can pop
  /// up by itself. Only the USB link can know this.
  bool get textFieldFocused => false;

  void start();
}
