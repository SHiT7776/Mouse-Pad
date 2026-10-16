import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../protocol.dart';
import 'pad_link.dart';

/// Talks to the PC receiver through the USB cable.
///
/// The receiver runs `adb reverse`, which makes 127.0.0.1:[port] on the phone
/// lead to the PC over the cable, so this connects to localhost and keeps
/// retrying until the receiver answers.
class UsbLink extends PadLink {
  UsbLink({required this.port});

  final int port;
  ConnectionTask<Socket>? _connecting;
  Timer? _connectTimeout;
  Socket? _socket; // through to the receiver
  Socket? _attempt; // connected, waiting for the receiver's hello
  StreamSubscription<String>? _subscription;
  Timer? _helloTimeout;
  String? _pcName;
  bool _textFieldFocused = false;
  Timer? _retry;
  bool _running = false;

  @override
  bool get connected => _socket != null;

  @override
  String? get peerName => _pcName;

  @override
  bool get textFieldFocused => _textFieldFocused;

  @override
  void start() {
    if (_running) return;
    _running = true;
    unawaited(_connect());
  }

  @override
  void dispose() {
    _running = false;
    _retry?.cancel();
    _connectTimeout?.cancel();
    _connecting?.cancel();
    _helloTimeout?.cancel();
    unawaited(_subscription?.cancel());
    _attempt?.destroy();
    _socket?.destroy();
    _socket = null;
    super.dispose();
  }

  Future<void> _connect() async {
    _retry = null;
    if (!_running) return;
    final Socket socket;
    try {
      final task = await Socket.startConnect(InternetAddress.loopbackIPv4, port);
      if (!_running) return task.cancel();
      _connecting = task;
      _connectTimeout = Timer(const Duration(seconds: 2), task.cancel);
      socket = await task.socket;
    } on Object {
      _scheduleRetry();
      return;
    } finally {
      _connectTimeout?.cancel();
      _connecting = null;
    }
    if (!_running) {
      socket.destroy();
      return;
    }
    socket.setOption(SocketOption.tcpNoDelay, true);
    // Write errors also surface here; without a handler they'd crash the app.
    unawaited(socket.done.catchError((Object _) {}));

    // adb accepts the connection even when the receiver isn't running, then
    // hangs up, so only the receiver's hello line means we're really through.
    _attempt = socket;
    _helloTimeout = Timer(const Duration(seconds: 3), socket.destroy);
    _subscription = const Utf8Decoder(allowMalformed: true)
        .bind(socket)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (!_running) return;
            if (identical(_socket, socket)) {
              final focused = parseKeyboardHint(line);
              if (focused == null || focused == _textFieldFocused) return;
              _textFieldFocused = focused;
              notifyListeners();
              return;
            }
            final name = parseHello(line);
            if (name == null || _socket != null) return;
            _helloTimeout?.cancel();
            _attempt = null;
            _socket = socket;
            _pcName = name;
            notifyListeners();
          },
          onDone: () => _closed(socket),
          onError: (Object _) => _closed(socket),
          cancelOnError: true,
        );
  }

  void _closed(Socket socket) {
    _helloTimeout?.cancel();
    socket.destroy();
    if (identical(_attempt, socket)) _attempt = null;
    if (identical(_socket, socket)) {
      _socket = null;
      _pcName = null;
      _textFieldFocused = false;
      if (_running) notifyListeners();
    }
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (!_running || _retry != null) return;
    _retry = Timer(const Duration(seconds: 1), () => unawaited(_connect()));
  }

  void _send(PadCommand command) {
    final socket = _socket;
    if (socket == null) return;
    try {
      socket.add(utf8.encode('${command.encode()}\n'));
    } on Object {
      // The connection is closing; _closed() will clean up and retry.
    }
  }

  @override
  void move(int dx, int dy) => _send(MoveCommand(dx, dy));

  @override
  void scroll(int vertical, int horizontal) =>
      _send(ScrollCommand(vertical, horizontal));

  @override
  void zoom(int steps) => _send(ZoomCommand(steps));

  @override
  void button(PadButton button, {required bool down}) =>
      _send(ButtonCommand(button, down: down));

  @override
  void click(PadButton button) => _send(ClickCommand(button));

  @override
  void typeText(String text) {
    if (text.isNotEmpty) _send(TextCommand(text));
  }

  @override
  void sendKey(KeyStroke stroke) => _send(KeyCommand(stroke));
}
