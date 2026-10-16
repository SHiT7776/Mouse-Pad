import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mouse_pad/links/usb_link.dart';
import 'package:mouse_pad/protocol.dart';

Future<void> eventually(bool Function() check,
    {Duration timeout = const Duration(seconds: 5)}) async {
  final end = DateTime.now().add(timeout);
  while (!check()) {
    if (DateTime.now().isAfter(end)) fail('timed out waiting');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  group('UsbLink', () {
    test('connects once the receiver says hello, then sends commands',
        () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final received = <String>[];
      server.listen((s) {
        s.write('${helloLine('TEST-PC')}\n');
        utf8.decoder
            .bind(s)
            .transform(const LineSplitter())
            .listen(received.add);
      });

      final link = UsbLink(port: server.port)..start();
      addTearDown(link.dispose);
      await eventually(() => link.connected);
      expect(link.peerName, 'TEST-PC');

      link
        ..move(3, 4)
        ..click(PadButton.left)
        ..typeText('ok')
        ..sendKey(const KeyStroke.key(PadKey.enter));
      await eventually(() => received.length == 4);
      expect(received, ['m 3 4', 'c l', 't ok', 'k - enter']);
    });

    test('follows the PC saying a text box has focus', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      late Socket pc;
      server.listen((s) {
        pc = s..write('${helloLine('TEST-PC')}\n');
      });
      final link = UsbLink(port: server.port)..start();
      addTearDown(link.dispose);
      await eventually(() => link.connected);
      expect(link.textFieldFocused, isFalse);

      pc.write('${keyboardHintLine(textFocused: true)}\n');
      await eventually(() => link.textFieldFocused);
      pc.write('${keyboardHintLine(textFocused: false)}\n');
      await eventually(() => !link.textFieldFocused);
    });

    test("an answer without hello (adb with no receiver) doesn't count",
        () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      var attempts = 0;
      server.listen((s) {
        attempts++;
        s.destroy();
      });
      final link = UsbLink(port: server.port)..start();
      addTearDown(link.dispose);
      await eventually(() => attempts >= 2); // it keeps retrying
      expect(link.connected, isFalse);
    });
  });
}
