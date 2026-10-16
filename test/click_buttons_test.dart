import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mouse_pad/click_buttons.dart';
import 'package:mouse_pad/links/pad_link.dart';
import 'package:mouse_pad/pad_settings.dart';
import 'package:mouse_pad/protocol.dart';

class RecordingSink implements PointerSink {
  final events = <String>[];

  @override
  void button(PadButton button, {required bool down}) =>
      events.add('${down ? 'down' : 'up'} ${button.name}');
  @override
  void click(PadButton button) => events.add('click ${button.name}');
  @override
  void move(int dx, int dy) {}
  @override
  void scroll(int vertical, int horizontal) {}
  @override
  void zoom(int steps) {}
}

void main() {
  testWidgets('Left and Right click press, hold and release', (tester) async {
    final sink = RecordingSink();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 64,
          child: ClickButtons(sink: sink, settings: PadSettings.memory()),
        ),
      ),
    ));

    // Held down until the finger lifts, so the pad can drag meanwhile.
    final finger = await tester.startGesture(tester.getCenter(find.text('Left click')));
    await tester.pump();
    expect(sink.events, ['down left']);
    await finger.up();
    expect(sink.events, ['down left', 'up left']);

    await tester.tap(find.text('Right click'));
    expect(sink.events.skip(2), ['down right', 'up right']);
  });
}
