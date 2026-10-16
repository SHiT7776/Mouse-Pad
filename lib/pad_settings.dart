import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'protocol.dart';
import 'links/pad_link.dart';
import 'touchpad_gestures.dart';

/// The phone app's settings, saved as JSON in the app's private files folder.
class PadSettings extends ChangeNotifier {
  PadSettings._(this._file, Map<String, Object?> json)
      : _mode = json['mode'] == 'bluetooth' ? LinkMode.bluetooth : LinkMode.usb,
        _pointerSpeed = _number(json['pointerSpeed'], 1, 0.3, 3),
        _acceleration = json['acceleration'] as bool? ?? true,
        _scrollSpeed = _number(json['scrollSpeed'], 1, 0.25, 4),
        _naturalScroll = json['naturalScroll'] as bool? ?? true,
        _tapToClick = json['tapToClick'] as bool? ?? true,
        _haptics = json['haptics'] as bool? ?? true,
        _smartKeyboard = json['smartKeyboard'] as bool? ?? false,
        _autoKeyboard = json['autoKeyboard'] as bool? ?? true,
        _port = (json['port'] as int?) ?? defaultPort;

  /// Settings that are never saved, for tests.
  PadSettings.memory() : this._(null, const {});

  static Future<PadSettings> load() async {
    File? file;
    var json = const <String, Object?>{};
    try {
      final dir = await const MethodChannel('mouse_pad/app')
          .invokeMethod<String>('filesDir');
      if (dir != null) {
        file = File('$dir/settings.json');
        if (await file.exists()) {
          json = (jsonDecode(await file.readAsString()) as Map)
              .cast<String, Object?>();
        }
      }
    } catch (_) {
      // Missing or unreadable settings: start from the defaults.
    }
    return PadSettings._(file, json);
  }

  final File? _file;
  Timer? _saveTimer;

  LinkMode _mode;
  double _pointerSpeed;
  bool _acceleration;
  double _scrollSpeed;
  bool _naturalScroll;
  bool _tapToClick;
  bool _haptics;
  bool _smartKeyboard;
  bool _autoKeyboard;
  int _port;

  LinkMode get mode => _mode;
  set mode(LinkMode v) => _set(() => _mode = v);

  /// Multiplier on pointer movement.
  double get pointerSpeed => _pointerSpeed;
  set pointerSpeed(double v) => _set(() => _pointerSpeed = v);

  bool get acceleration => _acceleration;
  set acceleration(bool v) => _set(() => _acceleration = v);

  double get scrollSpeed => _scrollSpeed;
  set scrollSpeed(double v) => _set(() => _scrollSpeed = v);

  /// Content follows the fingers, like scrolling on the phone itself.
  bool get naturalScroll => _naturalScroll;
  set naturalScroll(bool v) => _set(() => _naturalScroll = v);

  bool get tapToClick => _tapToClick;
  set tapToClick(bool v) => _set(() => _tapToClick = v);

  bool get haptics => _haptics;
  set haptics(bool v) => _set(() => _haptics = v);

  /// Lets the phone keyboard show suggestions and autocorrect.
  bool get smartKeyboard => _smartKeyboard;
  set smartKeyboard(bool v) => _set(() => _smartKeyboard = v);

  /// Opens the phone keyboard when a text box on the PC gets focus (USB).
  bool get autoKeyboard => _autoKeyboard;
  set autoKeyboard(bool v) => _set(() => _autoKeyboard = v);

  int get port => _port;
  set port(int v) => _set(() => _port = v);

  GestureConfig get gestureConfig => GestureConfig(
        pointerSpeed: _pointerSpeed,
        acceleration: _acceleration,
        scrollSpeed: _scrollSpeed,
        naturalScroll: _naturalScroll,
        tapToClick: _tapToClick,
      );

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  void _set(VoidCallback change) {
    change();
    notifyListeners();
    if (_file == null) return;
    // Sliders change many times a second; write once they settle.
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _save);
  }

  Future<void> _save() async {
    final file = _file;
    if (file == null) return;
    try {
      await file.writeAsString(jsonEncode({
        'mode': _mode.name,
        'pointerSpeed': _pointerSpeed,
        'acceleration': _acceleration,
        'scrollSpeed': _scrollSpeed,
        'naturalScroll': _naturalScroll,
        'tapToClick': _tapToClick,
        'haptics': _haptics,
        'smartKeyboard': _smartKeyboard,
        'autoKeyboard': _autoKeyboard,
        'port': _port,
      }));
    } on FileSystemException {
      // Settings still apply for this session.
    }
  }

  static double _number(Object? value, double fallback, double min, double max) =>
      value is num ? value.toDouble().clamp(min, max) : fallback;
}
