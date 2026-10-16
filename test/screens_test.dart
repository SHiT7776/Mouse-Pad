import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mouse_pad/links/pad_link.dart';
import 'package:mouse_pad/pad_app.dart';
import 'package:mouse_pad/pad_settings.dart';

/// Phones held sideways, in logical pixels (physical / 3).
const _phones = {
  'regular phone': Size(2340, 1080),
  'small phone': Size(2088, 1008),
};

Future<void> _launch(WidgetTester tester, Size physical) async {
  tester.view.physicalSize = physical;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  // Bluetooth mode talks to Android over channels; answer them here so the
  // test needs no sockets.
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
      const MethodChannel('mouse_pad/bluetooth'), (_) async => null);
  messenger.setMockStreamHandler(
    const EventChannel('mouse_pad/bluetooth/events'),
    MockStreamHandler.inline(
        onListen: (_, events) => events.success({'phase': 'ready'})),
  );

  final settings = PadSettings.memory()
    ..mode = LinkMode.bluetooth
    // Nothing listens on port 1, so USB mode never reaches a real receiver.
    ..port = 1;
  await tester.pumpWidget(PadApp(settings: settings));
  await tester.pump();
}

void main() {
  for (final MapEntry(key: name, value: size) in _phones.entries) {
    group(name, () {
      testWidgets('home shows connection, speed and the two big buttons',
          (tester) async {
        await _launch(tester, size);
        expect(find.text('USB cable'), findsOneWidget);
        expect(find.text('Bluetooth'), findsOneWidget);
        expect(find.text('Not connected'), findsOneWidget);
        expect(find.text('Choose PC'), findsOneWidget);
        expect(find.text('Pointer'), findsOneWidget);
        expect(find.text('Scroll'), findsOneWidget);
        expect(find.text('Touchpad'), findsOneWidget);
        expect(find.text('Keyboard'), findsOneWidget);
      });

      testWidgets('touchpad opens, with its own keyboard and speed buttons',
          (tester) async {
        await _launch(tester, size);
        await tester.tap(find.text('Touchpad'));
        await _settle(tester);
        expect(find.text('Tap to click'), findsOneWidget);
        expect(find.text('Left click'), findsOneWidget);
        expect(find.text('Right click'), findsOneWidget);
        expect(find.text('Speed'), findsOneWidget);

        await tester.tap(find.text('Keyboard'));
        await tester.pump();
        expect(find.text('Esc'), findsOneWidget);

        await tester.tap(find.text('Speed'));
        await _settle(tester);
        expect(find.text('Pointer'), findsOneWidget);
        await tester.tap(find.byTooltip('Close'));
        await _settle(tester);
        expect(find.text('Pointer'), findsNothing);

        await tester.tap(find.byTooltip('Back'));
        await _settle(tester);
        expect(find.text('USB cable'), findsOneWidget);
      });

      testWidgets('keyboard screen shows the typing area and PC keys',
          (tester) async {
        await _launch(tester, size);
        await tester.tap(find.text('Keyboard'));
        await _settle(tester);
        expect(find.text('Tap here to open your phone keyboard'), findsOneWidget);
        expect(find.text('Esc'), findsOneWidget);
        expect(find.text('Ctrl'), findsOneWidget);
        expect(find.byTooltip('Close keyboard'), findsNothing);
      });

      testWidgets('switching to USB shows how to connect', (tester) async {
        await _launch(tester, size);
        await tester.tap(find.text('USB cable'));
        await tester.pump();
        expect(find.text('Waiting for your PC'), findsOneWidget);
        await tester.tap(find.text('How to connect'));
        await _settle(tester);
        expect(find.text('Connect with a USB cable'), findsOneWidget);
        // Leave the screen so the USB link stops retrying.
        await tester.pumpWidget(const SizedBox());
      });
    });
  }
}

/// Lets page and sheet transitions finish. (pumpAndSettle would wait forever:
/// the status dot pulses and the "waiting" spinner spins until connected.)
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}
