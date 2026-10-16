import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mouse_pad/links/bluetooth_link.dart';
import 'package:mouse_pad/protocol.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Every 'mouse' call to Android: [buttons, dx, dy, wheel, pan].
  late List<List<int>> reports;

  setUp(() {
    reports = [];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('mouse_pad/bluetooth'), (call) async {
      if (call.method == 'mouse') reports.add(List.of(call.arguments as Int32List));
      return null;
    });
  });

  test('a burst of touch movement goes out bundled, nothing lost', () {
    fakeAsync((async) {
      final link = connectedLink();
      async.flushMicrotasks();
      expect(link.connected, isTrue);

      // 40 touch events in 20 ms, like a fast phone screen.
      for (var i = 0; i < 40; i++) {
        link.move(1, -2);
        async.elapse(const Duration(microseconds: 500));
      }
      async.elapse(const Duration(milliseconds: 50));

      expect(reports.length, lessThanOrEqualTo(4),
          reason: 'at most one hand-over every 8 ms');
      expect(reports.fold(0, (sum, r) => sum + r[1]), 40);
      expect(reports.fold(0, (sum, r) => sum + r[2]), -80);
      link.dispose();
    });
  });

  test('a click goes out right away, after the movement before it', () {
    fakeAsync((async) {
      final link = connectedLink();
      async.flushMicrotasks();

      link.move(5, 0); // sent at once, starts the cool-down
      link.move(3, 0); // waits for the cool-down...
      link.click(PadButton.left); // ...but a click doesn't wait
      async.flushMicrotasks();

      expect(reports, [
        [0, 5, 0, 0, 0],
        [0, 3, 0, 0, 0], // the pending movement, with the button still up
        [1, 0, 0, 0, 0], // press
        [0, 0, 0, 0, 0], // release
      ]);
      async.elapse(const Duration(milliseconds: 20));
      expect(reports, hasLength(4), reason: 'nothing left over');
      link.dispose();
    });
  });

  test('scrolling becomes whole wheel notches', () {
    fakeAsync((async) {
      final link = connectedLink();
      async.flushMicrotasks();

      for (var i = 0; i < 6; i++) {
        link.scroll(60, 0); // half a notch each
        async.elapse(const Duration(milliseconds: 1));
      }
      async.elapse(const Duration(milliseconds: 50));

      expect(reports.fold(0, (sum, r) => sum + r[3]), 3);
      link.dispose();
    });
  });
}

/// A link that Android has just reported as connected.
BluetoothLink connectedLink() => BluetoothLink(
      events: Stream.value({'phase': 'connected', 'device': 'PC'}),
    )..start();
