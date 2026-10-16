import 'package:flutter/foundation.dart';

import 'protocol.dart';
import 'links/bluetooth_link.dart';
import 'links/pad_link.dart';
import 'links/usb_link.dart';
import 'pad_settings.dart';

/// Owns the active link and swaps it when the USB/Bluetooth setting (or the
/// port) changes. Widgets talk to this, so they don't care which link is live.
class PadController extends ChangeNotifier implements PointerSink, KeySink {
  PadController(this.settings) {
    _link = _createLink();
    settings.addListener(_onSettings);
  }

  final PadSettings settings;
  late PadLink _link;
  late LinkMode _mode;
  late int _port;

  PadLink get link => _link;

  PadLink _createLink() {
    _mode = settings.mode;
    _port = settings.port;
    final link = _mode == LinkMode.usb ? UsbLink(port: _port) : BluetoothLink();
    link
      ..addListener(notifyListeners)
      ..start();
    return link;
  }

  void _onSettings() {
    final sameLink = settings.mode == _mode &&
        (_mode == LinkMode.bluetooth || settings.port == _port);
    if (sameLink) return;
    _link
      ..removeListener(notifyListeners)
      ..dispose();
    _link = _createLink();
    notifyListeners();
  }

  @override
  void dispose() {
    settings.removeListener(_onSettings);
    _link
      ..removeListener(notifyListeners)
      ..dispose();
    super.dispose();
  }

  @override
  void move(int dx, int dy) => _link.move(dx, dy);

  @override
  void scroll(int vertical, int horizontal) =>
      _link.scroll(vertical, horizontal);

  @override
  void zoom(int steps) => _link.zoom(steps);

  @override
  void button(PadButton button, {required bool down}) =>
      _link.button(button, down: down);

  @override
  void click(PadButton button) => _link.click(button);

  @override
  void typeText(String text) => _link.typeText(text);

  @override
  void sendKey(KeyStroke stroke) => _link.sendKey(stroke);
}
