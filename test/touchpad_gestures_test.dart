import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mouse_pad/links/pad_link.dart';
import 'package:mouse_pad/touchpad_gestures.dart';
import 'package:mouse_pad/protocol.dart';

class FakeSink implements PointerSink {
  final events = <String>[];
  int dx = 0, dy = 0, vertical = 0, horizontal = 0, zoomSteps = 0;

  @override
  void move(int x, int y) {
    dx += x;
    dy += y;
  }

  @override
  void scroll(int v, int h) {
    vertical += v;
    horizontal += h;
  }

  @override
  void zoom(int steps) => zoomSteps += steps;

  @override
  void button(PadButton b, {required bool down}) =>
      events.add('${down ? 'down' : 'up'} ${b.name}');

  @override
  void click(PadButton b) => events.add('click ${b.name}');
}

/// Drives [TouchpadGestures] with a fake clock.
class Pad {
  Pad(this.async, {GestureConfig config = const GestureConfig()}) {
    gestures = TouchpadGestures(
      sink: sink,
      config: () => config,
      onSwipe: (fingers, direction) => swipes.add('$fingers ${direction.name}'),
    );
  }

  final FakeAsync async;
  final sink = FakeSink();
  final swipes = <String>[];
  late final TouchpadGestures gestures;
  Duration _now = Duration.zero;
  final _at = <int, Offset>{};

  void down(int id, double x, double y) {
    _at[id] = Offset(x, y);
    gestures.pointerDown(id, Offset(x, y), _now);
  }

  void up(int id) => gestures.pointerUp(id, _now);

  void wait(int ms) {
    _now += Duration(milliseconds: ms);
    async.elapse(Duration(milliseconds: ms));
  }

  /// Moves fingers together by the given offsets, in small steps.
  void drag(Map<int, Offset> by, {int ms = 120, int steps = 12}) {
    for (var i = 1; i <= steps; i++) {
      wait(ms ~/ steps);
      for (final MapEntry(key: id, value: offset) in by.entries) {
        gestures.pointerMove(id, _at[id]! + offset * (i / steps), _now);
      }
    }
    by.forEach((id, offset) => _at[id] = _at[id]! + offset);
  }

  void tap({int fingers = 1}) {
    for (var i = 0; i < fingers; i++) {
      down(i + 1, 100.0 + 40 * i, 100);
    }
    wait(60);
    for (var i = 0; i < fingers; i++) {
      up(i + 1);
    }
  }
}

void main() {
  const holdBack = TouchpadGestures.dragWindow;

  test('one finger moves the pointer the same way, without clicking', () {
    fakeAsync((async) {
      final pad = Pad(async)..down(1, 100, 100);
      pad
        ..drag({1: const Offset(60, 30)})
        ..up(1)
        ..wait(500);
      expect(pad.sink.dx, greaterThan(60));
      expect(pad.sink.dy, greaterThan(30));
      expect(pad.sink.events, isEmpty);
    });
  });

  test('a quick flick goes further than a slow drag', () {
    int distance(int ms) {
      late int dx;
      fakeAsync((async) {
        final pad = Pad(async)..down(1, 100, 100);
        pad.drag({1: const Offset(80, 0)}, ms: ms, steps: 16);
        dx = pad.sink.dx;
      });
      return dx;
    }

    expect(distance(40), greaterThan(distance(800) * 1.8));
  });

  test('without acceleration, speed does not matter', () {
    int distance(int ms) {
      late int dx;
      fakeAsync((async) {
        final pad = Pad(async, config: const GestureConfig(acceleration: false))
          ..down(1, 100, 100);
        pad.drag({1: const Offset(80, 0)}, ms: ms, steps: 16);
        dx = pad.sink.dx;
      });
      return dx;
    }

    expect((distance(40) - distance(800)).abs(), lessThanOrEqualTo(1));
  });

  test('a tap clicks once the drag window has passed', () {
    fakeAsync((async) {
      final pad = Pad(async)..down(1, 100, 100);
      pad
        ..wait(30)
        ..drag({1: const Offset(2, 1)}, ms: 30, steps: 3) // finger wobble
        ..up(1);
      expect(pad.sink.dx, 0, reason: 'a wobble too small to follow');
      expect(pad.sink.events, isEmpty, reason: 'click is held back');
      pad.wait(holdBack.inMilliseconds + 1);
      expect(pad.sink.events, ['click left']);
    });
  });

  test('the pointer follows a small movement right away, yet it still taps',
      () {
    fakeAsync((async) {
      final pad = Pad(async)..down(1, 100, 100);
      pad.drag({1: const Offset(5, 0)}, ms: 40, steps: 4);
      expect(pad.sink.dx, greaterThan(0), reason: 'past the 3 px follow zone');
      pad
        ..up(1)
        ..wait(holdBack.inMilliseconds + 1);
      expect(pad.sink.events, ['click left'],
          reason: 'still inside the 8 px tap zone');
    });
  });

  test("right after a tap a small wobble doesn't move the pointer", () {
    fakeAsync((async) {
      final pad = Pad(async)..tap();
      pad
        ..wait(80)
        ..down(1, 100, 100)
        ..drag({1: const Offset(5, 0)}, ms: 30, steps: 3)
        ..up(1);
      expect(pad.sink.dx, 0, reason: 'a double click must stay in place');
      expect(pad.sink.events, ['click left', 'click left']);
    });
  });

  test('a long press is not a tap', () {
    fakeAsync((async) {
      final pad = Pad(async)..down(1, 100, 100);
      pad
        ..wait(600)
        ..up(1)
        ..wait(500);
      expect(pad.sink.events, isEmpty);
    });
  });

  test('double tap is a double click', () {
    fakeAsync((async) {
      final pad = Pad(async)..tap();
      pad
        ..wait(80)
        ..tap();
      expect(pad.sink.events, ['click left', 'click left']);
      pad.wait(500);
      expect(pad.sink.events, hasLength(2));
    });
  });

  test('tap, then touch again and move, drags with the left button held', () {
    fakeAsync((async) {
      final pad = Pad(async)..tap();
      pad
        ..wait(80)
        ..down(1, 100, 100)
        ..drag({1: const Offset(60, 0)});
      expect(pad.sink.events, ['down left']);
      expect(pad.gestures.dragging, isTrue);
      expect(pad.sink.dx, greaterThan(0));
      pad
        ..up(1)
        ..wait(500);
      expect(pad.sink.events, ['down left', 'up left']);
    });
  });

  test('two-finger tap is a right click, three-finger tap a middle click', () {
    fakeAsync((async) {
      final pad = Pad(async)..tap(fingers: 2);
      expect(pad.sink.events, ['click right']);
      pad
        ..wait(500)
        ..tap(fingers: 3);
      expect(pad.sink.events, ['click right', 'click middle']);
    });
  });

  test('tap to click can be turned off', () {
    fakeAsync((async) {
      final pad = Pad(async, config: const GestureConfig(tapToClick: false))
        ..tap()
        ..wait(500)
        ..tap(fingers: 2)
        ..wait(500);
      expect(pad.sink.events, isEmpty);
    });
  });

  test('a held-back tap still clicks when two fingers follow', () {
    fakeAsync((async) {
      final pad = Pad(async)..tap();
      pad
        ..wait(80)
        ..down(1, 100, 100)
        ..down(2, 150, 100)
        ..drag({1: const Offset(0, 60), 2: const Offset(0, 60)});
      expect(pad.sink.events, ['click left']);
      expect(pad.sink.vertical, isNot(0));
    });
  });

  group('two fingers', () {
    test('dragging down scrolls up with natural scrolling', () {
      fakeAsync((async) {
        final pad = Pad(async)
          ..down(1, 100, 100)
          ..down(2, 150, 100);
        pad
          ..drag({1: const Offset(4, 60), 2: const Offset(4, 60)})
          ..up(1)
          ..up(2);
        expect(pad.sink.vertical, greaterThan(100));
        expect(pad.sink.horizontal, 0, reason: 'locked to vertical');
        expect(pad.sink.events, isEmpty);
        expect(pad.sink.dx, 0, reason: 'the pointer stays put');
      });
    });

    test('scroll direction flips when natural scrolling is off', () {
      fakeAsync((async) {
        final pad = Pad(async, config: const GestureConfig(naturalScroll: false))
          ..down(1, 100, 100)
          ..down(2, 150, 100);
        pad.drag({1: const Offset(0, 60), 2: const Offset(0, 60)});
        expect(pad.sink.vertical, lessThan(-100));
      });
    });

    test('dragging right scrolls left (natural)', () {
      fakeAsync((async) {
        final pad = Pad(async)
          ..down(1, 100, 100)
          ..down(2, 100, 150);
        pad.drag({1: const Offset(60, 5), 2: const Offset(60, 5)});
        expect(pad.sink.horizontal, lessThan(-100));
        expect(pad.sink.vertical, 0);
      });
    });

    test('spreading zooms in, pinching zooms out', () {
      fakeAsync((async) {
        final pad = Pad(async)
          ..down(1, 100, 100)
          ..down(2, 160, 100);
        pad
          ..drag({1: const Offset(-40, 0), 2: const Offset(40, 0)})
          ..up(1)
          ..up(2);
        expect(pad.sink.zoomSteps, 2); // the gap grew by 80
        expect(pad.sink.vertical, 0);
        pad
          ..wait(500)
          ..down(1, 60, 100)
          ..down(2, 200, 100)
          ..drag({1: const Offset(40, 0), 2: const Offset(-40, 0)});
        expect(pad.sink.zoomSteps, 0);
      });
    });
  });

  group('swipes', () {
    test('three fingers up fires once', () {
      fakeAsync((async) {
        final pad = Pad(async)
          ..down(1, 100, 200)
          ..down(2, 140, 200)
          ..down(3, 180, 200);
        pad
          ..drag({
            1: const Offset(0, -120),
            2: const Offset(0, -120),
            3: const Offset(0, -120),
          })
          ..up(1)
          ..up(2)
          ..up(3)
          ..wait(500);
        expect(pad.swipes, ['3 up']);
        expect(pad.sink.events, isEmpty, reason: 'no middle click');
        expect(pad.sink.vertical, 0, reason: 'no scrolling');
      });
    });

    test('four fingers left', () {
      fakeAsync((async) {
        final pad = Pad(async);
        for (var i = 1; i <= 4; i++) {
          pad.down(i, 100.0 + 30 * i, 200);
        }
        pad.drag({for (var i = 1; i <= 4; i++) i: const Offset(-90, 4)});
        expect(pad.swipes, ['4 left']);
      });
    });

    test('map to the Windows touchpad shortcuts', () {
      String shortcut(int fingers, SwipeDirection d) =>
          swipeShortcut(fingers, d).toString();
      expect(shortcut(3, SwipeDirection.up), 'k w tab'); // Task View
      expect(shortcut(3, SwipeDirection.down), 'k w u+64'); // Win+D
      expect(shortcut(3, SwipeDirection.left), 'k a tab'); // Alt+Tab
      expect(shortcut(3, SwipeDirection.right), 'k a tab');
      expect(shortcut(4, SwipeDirection.left), 'k cw right'); // next desktop
      expect(shortcut(4, SwipeDirection.right), 'k cw left');
      expect(shortcut(4, SwipeDirection.up), 'k w tab');
    });
  });

  test('lifting the dragging finger releases the button', () {
    fakeAsync((async) {
      final pad = Pad(async)..tap();
      pad
        ..wait(80)
        ..down(1, 100, 100)
        ..drag({1: const Offset(40, 0)})
        ..down(2, 200, 100) // a second finger lands mid-drag
        ..up(1);
      expect(pad.sink.events, ['down left', 'up left']);
      pad
        ..drag({2: const Offset(40, 0)})
        ..up(2);
      expect(pad.sink.events, ['down left', 'up left']);
    });
  });
}
