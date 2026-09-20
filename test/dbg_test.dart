import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:miditutor/midi/application/midi_event_stream.dart';
import 'package:miditutor/midi/application/midi_raw_event_capture.dart';
import 'package:miditutor/midi/domain/raw_midi_event.dart';

class Fake implements MidiEventStream {
  Fake() { events = c.stream.asBroadcastStream(); }
  final c = StreamController<RawMidiEvent>();
  @override late final Stream<RawMidiEvent> events;
  void emit(RawMidiEvent e) => c.add(e);
}

RawMidiEvent ev(String s, int seq) => RawMidiEvent(
  sessionId: s, deviceId: 'd', connectionType: 'USB', seq: seq,
  appMonotonicTsMs: 1, messageType: RawMidiMessageType.noteOn,
  channel: 0, note: 60, velocity: 1, rawBytes: const [0x90, 60, 1]);

void main() {
  testWidgets('dbg', (t) async {
    final f = Fake();
    final cap = MidiRawEventCapture(f);
    await cap.start('abc');
    f.emit(ev('abc', 1));
    await Future<void>.delayed(Duration.zero);
    print('after 1st: ${cap.buffer.length} / rev ${cap.revision.value}');

    await cap.start('xyz');
    print('after start xyz: len ${cap.buffer.length} active ${cap.isActive}');
    f.emit(ev('xyz', 1));
    await Future<void>.delayed(Duration.zero);
    print('after xyz emit: len ${cap.buffer.length} rev ${cap.revision.value}');
  });
}
