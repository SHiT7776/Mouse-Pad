import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../protocol.dart';
import 'hid_keymap.dart';
import 'pad_link.dart';

/// Mirrors the native side's state (BluetoothHidController.kt).
enum BtPhase {
  idle,
  unsupported,
  needsPermission,
  bluetoothOff,
  starting,
  ready,
  connecting,

  /// The link to the last PC dropped; the phone keeps calling it.
  reconnecting,
  connected,
  error,
}

class BtDevice {
  const BtDevice(
      {required this.name, required this.address, required this.isComputer});

  final String name;
  final String address;
  final bool isComputer;
}

/// Makes the phone a Bluetooth touchpad and keyboard (Android 9+). Windows
/// lists it as a Bluetooth mouse and keyboard, the way it does any Bluetooth
/// pointing device, so the PC needs no extra app.
class BluetoothLink extends PadLink {
  BluetoothLink({@visibleForTesting Stream<dynamic>? events})
      : _eventStream = events;

  static const _methods = MethodChannel('mouse_pad/bluetooth');
  static const _events = EventChannel('mouse_pad/bluetooth/events');
  final Stream<dynamic>? _eventStream;

  BtPhase phase = BtPhase.idle;
  String? message;
  String? _hostName;

  /// When the phone stops being visible for pairing, if it is right now.
  DateTime? discoverableUntil;
  List<BtDevice> paired = const [];

  StreamSubscription<dynamic>? _subscription;
  int _buttons = 0;
  double _wheel = 0, _pan = 0;
  bool _disposed = false;

  // Phones report touches several hundred times a second, far more than a
  // Bluetooth link carries, so movement is gathered and handed over at most
  // every 8 ms. (The Android side then paces it to the link.)
  static const handOverEvery = Duration(milliseconds: 8);
  Timer? _coolDown;
  int _dx = 0, _dy = 0, _wheelSteps = 0, _panSteps = 0;

  @override
  bool get connected => phase == BtPhase.connected;

  @override
  String? get peerName => _hostName;

  @override
  void start() {
    _subscription ??= (_eventStream ?? _events.receiveBroadcastStream())
        .listen(_onEvent, onError: (Object _) {});
    _call('start');
  }

  void retry() => _call('start');
  void enableBluetooth() => _call('enableBluetooth');
  void makeDiscoverable() => _call('makeDiscoverable');
  void openAppSettings() => _call('openAppSettings');
  void connectTo(BtDevice device) =>
      _call('connect', {'address': device.address});

  Future<void> refreshPaired() async {
    try {
      final list = await _methods
              .invokeListMethod<Map<dynamic, dynamic>>('pairedDevices') ??
          const [];
      paired = [
        for (final m in list)
          BtDevice(
            name: m['name'] as String? ?? 'Unknown device',
            address: m['address'] as String,
            isComputer: m['isComputer'] == true,
          ),
      ];
      if (!_disposed) notifyListeners();
    } on PlatformException {
      // Keep the old list.
    }
  }

  void _onEvent(dynamic event) {
    if (event is! Map || _disposed) return;
    final name = event['phase'] as String?;
    phase = BtPhase.values
        .firstWhere((p) => p.name == name, orElse: () => BtPhase.error);
    message = event['message'] as String?;
    _hostName = event['device'] as String?;
    final until = event['discoverableUntil'] as int?;
    discoverableUntil =
        until == null ? null : DateTime.fromMillisecondsSinceEpoch(until);
    if (!connected) _dropPending();
    notifyListeners();
    if (phase == BtPhase.ready ||
        phase == BtPhase.connecting ||
        phase == BtPhase.reconnecting) {
      unawaited(refreshPaired());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _coolDown?.cancel();
    unawaited(_subscription?.cancel());
    _call('stop');
    super.dispose();
  }

  @override
  void move(int dx, int dy) {
    _dx += dx;
    _dy += dy;
    _scheduleHandOver();
  }

  @override
  void button(PadButton button, {required bool down}) {
    _handOver(); // movement so far belongs to the old button state
    final bit = switch (button) {
      PadButton.left => 1,
      PadButton.right => 2,
      PadButton.middle => 4,
    };
    _buttons = down ? _buttons | bit : _buttons & ~bit;
    if (connected) {
      _call('mouse', Int32List.fromList([_buttons, 0, 0, 0, 0]));
    }
  }

  @override
  void click(PadButton button) {
    this.button(button, down: true);
    this.button(button, down: false);
  }

  @override
  void scroll(int vertical, int horizontal) {
    // A Bluetooth wheel moves in whole notches; carry the rest over.
    _wheel += vertical / 120;
    _pan += horizontal / 120;
    final wheel = _wheel.truncate();
    final pan = _pan.truncate();
    if (wheel == 0 && pan == 0) return;
    _wheel -= wheel;
    _pan -= pan;
    _wheelSteps += wheel;
    _panSteps += pan;
    _scheduleHandOver();
  }

  @override
  void zoom(int steps) {
    if (connected && steps != 0) _call('zoom', steps.clamp(-127, 127));
  }

  @override
  void typeText(String text) {
    if (!connected) return;
    final codes = <int>[];
    for (final rune in text.runes) {
      final key = HidKeymap.forChar(rune);
      if (key != null) codes.addAll([key.modifiers, key.usage]);
    }
    if (codes.isNotEmpty) _call('keys', Int32List.fromList(codes));
  }

  @override
  void sendKey(KeyStroke stroke) {
    if (!connected) return;
    final key = HidKeymap.forStroke(stroke);
    if (key != null) {
      _call('keys', Int32List.fromList([key.modifiers, key.usage]));
    }
  }

  void _scheduleHandOver() {
    if (!connected) return _dropPending();
    // During the cool-down, movement piles up and goes when it ends.
    if (_coolDown == null) _handOver();
  }

  /// Sends the gathered movement now and starts the cool-down.
  void _handOver() {
    if (_dx == 0 && _dy == 0 && _wheelSteps == 0 && _panSteps == 0) return;
    final dx = _dx.clamp(-32767, 32767);
    final dy = _dy.clamp(-32767, 32767);
    final wheel = _wheelSteps.clamp(-127, 127);
    final pan = _panSteps.clamp(-127, 127);
    _dx -= dx;
    _dy -= dy;
    _wheelSteps -= wheel;
    _panSteps -= pan;
    if (connected) {
      _call('mouse', Int32List.fromList([_buttons, dx, dy, wheel, pan]));
    }
    _coolDown?.cancel();
    _coolDown = Timer(handOverEvery, () {
      _coolDown = null;
      _handOver(); // whatever piled up meanwhile
    });
  }

  void _dropPending() {
    _coolDown?.cancel();
    _coolDown = null;
    _dx = _dy = _wheelSteps = _panSteps = 0;
    _buttons = 0;
  }

  void _call(String method, [Object? arguments]) {
    unawaited(_methods
        .invokeMethod<void>(method, arguments)
        .catchError((Object _) {}));
  }
}
