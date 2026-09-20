import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/midi/application/midi_event_stream.dart';
import 'package:miditutor/midi/application/midi_raw_event_capture.dart';
import 'package:miditutor/midi/application/raw_midi_event_buffer.dart';
import 'package:miditutor/midi/domain/raw_midi_event.dart';

class _FakeMidiEventStream implements MidiEventStream {
  _FakeMidiEventStream() {
    events = _controller.stream.asBroadcastStream();
  }

  final StreamController<RawMidiEvent> _controller =
      StreamController<RawMidiEvent>();
  @override
  late final Stream<RawMidiEvent> events;

  void emit(RawMidiEvent event) => _controller.add(event);
}

RawMidiEvent buildEvent({
  String sessionId = 'abc',
  int seq = 1,
  RawMidiMessageType type = RawMidiMessageType.noteOn,
}) {
  return RawMidiEvent(
    sessionId: sessionId,
    deviceId: '123456',
    connectionType: 'USB',
    seq: seq,
    appMonotonicTsMs: 1000,
    messageType: type,
    channel: 0,
    note: 60,
    velocity: 83,
    rawBytes: const <int>[0x90, 60, 83],
  );
}

void main() {
  group('RawMidiEventBuffer', () {
    test('appends events and preserves order', () {
      final buffer = RawMidiEventBuffer();
      buffer.append(buildEvent(seq: 1));
      buffer.append(buildEvent(seq: 2));

      expect(buffer.length, 2);
      expect(buffer.events.map((e) => e.seq), <int>[1, 2]);
    });

    test('reads expose an unmodifiable copy that cannot mutate the buffer',
        () {
      final buffer = RawMidiEventBuffer();
      buffer.append(buildEvent(seq: 1));

      final snapshot = buffer.events;
      expect(() => snapshot.add(buildEvent(seq: 2)), throwsUnsupportedError);
      expect(buffer.length, 1);
    });

    test('clear resets the buffer at an explicit boundary', () {
      final buffer = RawMidiEventBuffer();
      buffer.append(buildEvent(seq: 1));
      buffer.clear();

      expect(buffer.isEmpty, isTrue);
      expect(buffer.length, 0);
    });

    test('appendAll appends a batch in order', () {
      final buffer = RawMidiEventBuffer();
      buffer.appendAll(<RawMidiEvent>[
        buildEvent(seq: 1),
        buildEvent(seq: 2),
      ]);

      expect(buffer.events.map((e) => e.seq), <int>[1, 2]);
    });
  });

  group('MidiRawEventCapture', () {
    test('appends matching-session events and bumps the revision', () async {
      final stream = _FakeMidiEventStream();
      final capture = MidiRawEventCapture(stream);
      await capture.start('abc');

      stream.emit(buildEvent(sessionId: 'abc', seq: 1));
      stream.emit(buildEvent(sessionId: 'abc', seq: 2));
      await Future<void>.delayed(Duration.zero);

      expect(capture.buffer.length, 2);
      expect(capture.revision.value, 2);
    });

    test('drops events from a foreign (previous) session', () async {
      final stream = _FakeMidiEventStream();
      final capture = MidiRawEventCapture(stream);
      await capture.start('abc');

      stream.emit(buildEvent(sessionId: 'old-session', seq: 1));
      stream.emit(buildEvent(sessionId: 'abc', seq: 2));
      await Future<void>.delayed(Duration.zero);

      expect(capture.buffer.length, 1);
      expect(capture.buffer.events.single.sessionId, 'abc');
    });

    test('stop cancels the subscription and halts appends', () async {
      final stream = _FakeMidiEventStream();
      final capture = MidiRawEventCapture(stream);
      await capture.start('abc');

      stream.emit(buildEvent(seq: 1));
      await Future<void>.delayed(Duration.zero);
      expect(capture.buffer.length, 1);

      await capture.stop();
      stream.emit(buildEvent(seq: 2));
      await Future<void>.delayed(Duration.zero);

      expect(capture.buffer.length, 1);
      expect(capture.isActive, isFalse);
    });

    test('start clears the buffer for a new session and resets sequence view',
        () async {
      final stream = _FakeMidiEventStream();
      final capture = MidiRawEventCapture(stream);
      await capture.start('abc');
      stream.emit(buildEvent(seq: 1));
      stream.emit(buildEvent(seq: 2));
      await Future<void>.delayed(Duration.zero);

      await capture.start('xyz');
      expect(capture.buffer.isEmpty, isTrue);

      stream.emit(buildEvent(sessionId: 'xyz', seq: 1));
      await Future<void>.delayed(Duration.zero);
      expect(capture.buffer.events.single.seq, 1);
    });
  });
}