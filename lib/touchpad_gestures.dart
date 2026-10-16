import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'protocol.dart';
import 'links/pad_link.dart';

/// How the touchpad should feel. Read fresh for every movement, so settings
/// apply immediately.
class GestureConfig {
  const GestureConfig({
    this.pointerSpeed = 1,
    this.acceleration = true,
    this.scrollSpeed = 1,
    this.naturalScroll = true,
    this.tapToClick = true,
  });

  final double pointerSpeed;
  final bool acceleration;
  final double scrollSpeed;
  final bool naturalScroll;
  final bool tapToClick;
}

enum PadFeedback { click, dragStart }

enum SwipeDirection { up, down, left, right }

/// Scroll units (120 = one wheel notch) per logical pixel of finger travel.
const double scrollUnitsPerDp = 3;

/// What a Windows laptop touchpad does for three- and four-finger swipes.
KeyStroke swipeShortcut(int fingers, SwipeDirection direction) =>
    switch ((fingers, direction)) {
      // Task View
      (_, SwipeDirection.up) =>
        const KeyStroke.key(PadKey.tab, modifiers: {Modifier.win}),
      // Show the desktop
      (_, SwipeDirection.down) =>
        const KeyStroke.char(0x64, modifiers: {Modifier.win}), // Win+D
      // Switch to the previous app
      (3, _) => const KeyStroke.key(PadKey.tab, modifiers: {Modifier.alt}),
      // Four fingers: switch virtual desktops, following the fingers
      (_, SwipeDirection.left) => const KeyStroke.key(PadKey.right,
          modifiers: {Modifier.ctrl, Modifier.win}),
      (_, SwipeDirection.right) => const KeyStroke.key(PadKey.left,
          modifiers: {Modifier.ctrl, Modifier.win}),
    };

/// Turns raw touches into laptop-touchpad behavior:
///
/// * one finger moves the pointer, faster for quick flicks
/// * tap = left click, two-finger tap = right click, three-finger tap =
///   middle click
/// * double tap = double click; tap, then touch again and move = drag
/// * two-finger drag = scroll, pinch = zoom
/// * three/four-finger swipes = Windows gestures (see [swipeShortcut])
class TouchpadGestures {
  TouchpadGestures({
    required this.sink,
    required this.config,
    this.onFeedback,
    this.onSwipe,
  });

  final PointerSink sink;
  final GestureConfig Function() config;
  final void Function(PadFeedback feedback)? onFeedback;
  final void Function(int fingers, SwipeDirection direction)? onSwipe;

  /// Finger travel (logical pixels) that still counts as a tap.
  static const double slop = 8;

  /// Finger travel after which the pointer starts following. Smaller than
  /// [slop] so slow movements respond right away; a wobbly tap still clicks.
  static const double followSlop = 3;
  static const Duration tapTimeout = Duration(milliseconds: 250);

  /// After a tap, how long a second touch can still turn it into a drag.
  /// The click is held back this long.
  static const Duration dragWindow = Duration(milliseconds: 200);

  /// How far three or four fingers travel before it counts as a swipe.
  static const double swipeDistance = 50;

  /// Change in the gap between two fingers per zoom step.
  static const double zoomStep = 36;

  final Map<int, _Touch> _touches = {};
  _Mode _mode = _Mode.idle;
  int? _primary;
  Duration _sessionStart = Duration.zero;
  int _maxTouches = 0;
  bool _moved = false;
  bool _following = false;
  bool _afterTap = false;
  bool _dragging = false;
  Timer? _pendingClick;

  // Multi-finger state: where the fingers are as a group, and how spread out.
  Offset _centroid = Offset.zero;
  double _spread = 0;
  Offset _travel = Offset.zero;
  double _spreadTravel = 0;
  bool? _scrollVertical;
  bool? _pinching;
  bool _swiped = false;

  double _carryX = 0, _carryY = 0, _carryV = 0, _carryH = 0, _carryZoom = 0;
  double _speed = 0;
  Duration _lastMove = Duration.zero;

  Iterable<Offset> get touches => _touches.values.map((t) => t.position);
  bool get dragging => _dragging;

  void dispose() {
    _pendingClick?.cancel();
    if (_dragging) _endDrag();
  }

  void pointerDown(int id, Offset position, Duration time) {
    if (_touches.isEmpty) _beginSession(id, time);
    _touches[id] = _Touch(position);
    _maxTouches = math.max(_maxTouches, _touches.length);
    if (_touches.length >= 2 && _mode == _Mode.pointing) {
      if (_afterTap) {
        // The tap we were holding back was a plain click after all.
        _afterTap = false;
        sink.click(PadButton.left);
      }
      _mode = _Mode.twoFinger;
      _travel = Offset.zero;
      _spreadTravel = 0;
      _scrollVertical = null;
      _pinching = null;
      _carryV = _carryH = _carryZoom = 0;
    }
    if (_touches.length >= 3 && _mode == _Mode.twoFinger) {
      _mode = _Mode.swiping;
      _travel = Offset.zero;
      _swiped = false;
    }
    _rebase();
  }

  void pointerMove(int id, Offset position, Duration time) {
    final touch = _touches[id];
    if (touch == null) return;
    final previous = touch.position;
    touch.position = position;
    if (!_moved && (position - touch.start).distance > slop) {
      _moved = true;
      if (_mode == _Mode.pointing && _afterTap) {
        _afterTap = false;
        _dragging = true;
        _mode = _Mode.dragging;
        sink.button(PadButton.left, down: true);
        onFeedback?.call(PadFeedback.dragStart);
      }
    }
    switch (_mode) {
      case _Mode.pointing || _Mode.dragging:
        if (id != _primary) return;
        if (_following) {
          _movePointer(position - previous, time);
          return;
        }
        // Right after a tap, wait for the whole tap zone: this touch may still
        // be the second half of a double tap, which mustn't move the pointer.
        final zone = _afterTap ? slop : followSlop;
        if ((position - touch.start).distance <= zone) return;
        _following = true;
        // Catch up on the travel inside the zone, so it doesn't feel sticky.
        _movePointer(position - touch.start, time);
      case _Mode.twoFinger:
        final (pan, pinch) = _groupDelta();
        if (!_moved) return;
        if (_pinching case final pinching?) {
          pinching ? _zoom(pinch) : _scroll(pan);
          return;
        }
        // Decided once per gesture: fingers moving apart or together zoom,
        // fingers moving side by side scroll. The travel so far counts too.
        final pinching = _pinching = _touches.length == 2 &&
            _spreadTravel.abs() > _travel.distance * 1.2;
        pinching ? _zoom(_spreadTravel) : _scroll(_travel);
      case _Mode.swiping:
        _groupDelta();
        if (_swiped || _travel.distance < swipeDistance) return;
        _swiped = true;
        final t = _travel;
        final direction = t.dx.abs() > t.dy.abs()
            ? (t.dx > 0 ? SwipeDirection.right : SwipeDirection.left)
            : (t.dy > 0 ? SwipeDirection.down : SwipeDirection.up);
        onSwipe?.call(math.min(_touches.length, 4), direction);
        onFeedback?.call(PadFeedback.click);
      case _Mode.idle:
        break;
    }
  }

  void pointerUp(int id, Duration time) => _lift(id, time, cancelled: false);

  void pointerCancel(int id, Duration time) =>
      _lift(id, time, cancelled: true);

  void _beginSession(int id, Duration time) {
    _sessionStart = time;
    _lastMove = time;
    _maxTouches = 0;
    _moved = false;
    _following = false;
    _primary = id;
    _mode = _Mode.pointing;
    _speed = 0;
    _carryX = _carryY = 0;
    _afterTap = _pendingClick?.isActive ?? false;
    _pendingClick?.cancel();
    _pendingClick = null;
  }

  void _lift(int id, Duration time, {required bool cancelled}) {
    if (_touches.remove(id) == null) return;
    if (_touches.isNotEmpty) {
      _rebase();
      if (id == _primary && _mode == _Mode.dragging) {
        _endDrag();
        _mode = _Mode.idle; // ignore the other fingers until they lift
      }
      return;
    }

    final tap = !cancelled && !_moved && time - _sessionStart <= tapTimeout;
    if (_dragging) {
      _endDrag();
    } else if (_afterTap && !cancelled) {
      // A second touch that never moved: a double tap is a double click; a
      // slow second press is just the first click.
      sink.click(PadButton.left);
      if (tap) sink.click(PadButton.left);
      onFeedback?.call(PadFeedback.click);
    } else if (tap && config().tapToClick && _maxTouches <= 3) {
      onFeedback?.call(PadFeedback.click);
      switch (_maxTouches) {
        case 1:
          _pendingClick = Timer(dragWindow, () {
            _pendingClick = null;
            sink.click(PadButton.left);
          });
        case 2:
          sink.click(PadButton.right);
        case 3:
          sink.click(PadButton.middle);
      }
    }
    _afterTap = false;
    _mode = _Mode.idle;
    _primary = null;
  }

  void _endDrag() {
    _dragging = false;
    sink.button(PadButton.left, down: false);
  }

  void _movePointer(Offset delta, Duration time) {
    final ms = math.max(1.0, (time - _lastMove).inMicroseconds / 1000);
    _lastMove = time;
    final instant = delta.distance / ms;
    _speed = _speed == 0 ? instant : _speed * 0.6 + instant * 0.4;
    final gain = _gain(_speed);
    _carryX += delta.dx * gain;
    _carryY += delta.dy * gain;
    final dx = _carryX.truncate();
    final dy = _carryY.truncate();
    _carryX -= dx;
    _carryY -= dy;
    if (dx != 0 || dy != 0) sink.move(dx, dy);
  }

  /// PC pixels per phone pixel: precise when slow, quick across the screen
  /// when flicked. [speed] is in logical pixels per millisecond.
  double _gain(double speed) {
    final c = config();
    if (!c.acceleration) return 2.2 * c.pointerSpeed;
    final t = ((speed - 0.15) / (1.5 - 0.15)).clamp(0.0, 1.0);
    return c.pointerSpeed * (1.4 + 3.0 * t * t * (3 - 2 * t));
  }

  void _scroll(Offset delta) {
    final c = config();
    // Lock to the main direction, so a vertical scroll doesn't wobble sideways.
    final vertical = _scrollVertical ??= _travel.dy.abs() >= _travel.dx.abs();
    final units = scrollUnitsPerDp * c.scrollSpeed * (c.naturalScroll ? 1 : -1);
    if (vertical) {
      _carryV += delta.dy * units;
    } else {
      _carryH -= delta.dx * units;
    }
    final v = _carryV.truncate();
    final h = _carryH.truncate();
    _carryV -= v;
    _carryH -= h;
    if (v != 0 || h != 0) sink.scroll(v, h);
  }

  void _zoom(double spreadDelta) {
    _carryZoom += spreadDelta / zoomStep;
    final steps = _carryZoom.truncate();
    if (steps == 0) return;
    _carryZoom -= steps;
    sink.zoom(steps);
  }

  /// Movement of the finger group since the last event: (pan, spread change).
  (Offset, double) _groupDelta() {
    final centroid = _centroidNow();
    final spread = _spreadNow(centroid);
    final pan = centroid - _centroid;
    final pinch = spread - _spread;
    _centroid = centroid;
    _spread = spread;
    _travel += pan;
    _spreadTravel += pinch;
    return (pan, pinch);
  }

  /// Fingers were added or lifted: measure from here, without a jump.
  void _rebase() {
    if (_touches.isEmpty) return;
    _centroid = _centroidNow();
    _spread = _spreadNow(_centroid);
  }

  Offset _centroidNow() {
    var sum = Offset.zero;
    for (final t in _touches.values) {
      sum += t.position;
    }
    return sum / _touches.length.toDouble();
  }

  /// Twice the average distance from the centroid: the gap between two
  /// fingers.
  double _spreadNow(Offset centroid) {
    var sum = 0.0;
    for (final t in _touches.values) {
      sum += (t.position - centroid).distance;
    }
    return 2 * sum / _touches.length;
  }
}

enum _Mode { idle, pointing, dragging, twoFinger, swiping }

class _Touch {
  _Touch(this.start) : position = start;

  final Offset start;
  Offset position;
}
