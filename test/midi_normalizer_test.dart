import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/midi/application/midi_normalizer.dart';
import 'package:miditutor/midi/domain/normalized_midi_event.dart';
import 'package:miditutor/midi/domain/raw_midi_event.dart';

RawMidiEvent raw({
  String sessionId = 'abc',
  int seq = 1,
  int ts = 1000,
  String messageType = 'note_on',
  int? channel = 0,
  int? note,
  int? velocity,
  List<int>? rawBytes,
}) {
  return RawMidiEvent(
    sessionId: sessionId,
    deviceId: '123456',
    connectionType: 'USB',
    seq: seq,
    appMonotonicTsMs: ts,
    messageType: switch (messageType) {
      'note_on' => RawMidiMessageType.noteOn,
      'note_off' => RawMidiMessageType.noteOff,
      _ => RawMidiMessageType.other,
    },
    channel: channel,
    note: note,
    velocity: velocity,
    rawBytes: rawBytes ?? <int>[0x90, note ?? 60, velocity ?? 100],
  );
}

void main() {
  const normalizer = MidiNormalizer();

  group('Normalization rules', () {
    test('N1: standard Note-On 0x90 velocity>0 derives normalized Note-On', () {
      final event = raw(velocity: 100, rawBytes: <int>[0x90, 60, 100]);
      final normalized = normalizer.normalize(event);

      expect(normalized.type, NormalizedMidiMessageType.noteOn);
      expect(normalized.normalizationRule, MidiNormalizer.ruleNoteOn);
    });

    test('N2: velocity-zero Note-On 0x90 velocity=0 derives normalized Note-Off', () {
      final event = raw(velocity: 0, rawBytes: <int>[0x90, 60, 0]);
      final normalized = normalizer.normalize(event);

      expect(normalized.type, NormalizedMidiMessageType.noteOff);
      expect(normalized.normalizationRule, MidiNormalizer.ruleNoteOnVelocityZero);
      // Raw H1 event remains note_on; status and bytes unchanged.
      expect(event.messageType, RawMidiMessageType.noteOn);
      expect(event.rawBytes, <int>[0x90, 60, 0]);
      expect(event.velocity, 0);
      expect(normalized.rawBytes, <int>[0x90, 60, 0]);
      expect(normalized.rawStatus, 0x90);
    });

    test('N3: standard Note-Off 0x80 derives normalized Note-Off', () {
      final event = raw(
        messageType: 'note_off',
        velocity: 64,
        note: 60,
        rawBytes: <int>[0x80, 60, 64],
      );
      final normalized = normalizer.normalize(event);

      expect(normalized.type, NormalizedMidiMessageType.noteOff);
      expect(normalized.normalizationRule, MidiNormalizer.ruleNoteOff);
      expect(normalized.channel, 0);
      expect(normalized.pitch, 60);
      expect(normalized.velocity, 64);
    });

    test('N4: other MIDI message (CC 0xB0) derives normalized Other', () {
      final event = raw(
        messageType: 'other',
        channel: 0,
        note: null,
        velocity: null,
        rawBytes: <int>[0xB0, 48, 100],
      );
      final normalized = normalizer.normalize(event);

      expect(normalized.type, NormalizedMidiMessageType.other);
      expect(normalized.normalizationRule, MidiNormalizer.ruleOther);
      expect(normalized.rawStatus, 0xB0);
      expect(normalized.rawBytes, <int>[0xB0, 48, 100]);
    });

    test('N5: multiple channels are preserved independently', () {
      final events = normalizer.normalizeAll(<RawMidiEvent>[
        raw(channel: 0, rawBytes: <int>[0x90, 60, 100]),
        raw(channel: 1, rawBytes: <int>[0x91, 62, 100]),
        raw(channel: 15, seq: 3, ts: 1200, rawBytes: <int>[0x9F, 64, 30]),
      ]);

      expect(events.map((e) => e.channel), <int?>[0, 1, 15]);
      expect(events.every((e) => e.type == NormalizedMidiMessageType.noteOn), isTrue);
    });

    test('Raw 0x9n status with null velocity is NOT treated as velocity-zero', () {
      final event = raw(velocity: null, rawBytes: <int>[0x90, 60, 100]);
      expect(normalizer.normalize(event).type, NormalizedMidiMessageType.noteOn);
    });
  });

  group('Immutability and determinism', () {
    test('N15: normalization does not mutate the raw event or its bytes', () {
      final event = raw(velocity: 0, rawBytes: <int>[0x90, 60, 0]);
      final bytesBefore = List<int>.from(event.rawBytes);

      normalizer.normalize(event);

      expect(event.rawBytes, bytesBefore);
      expect(event.rawBytes, <int>[0x90, 60, 0]);
      expect(event.messageType, RawMidiMessageType.noteOn);
      expect(event.velocity, 0);
    });

    test('N16: repeated normalization is deterministic', () {
      final input = <RawMidiEvent>[
        raw(seq: 0, ts: 1000, rawBytes: <int>[0x90, 60, 0]),
        raw(seq: 1, ts: 1001, velocity: 100),
        raw(seq: 2, ts: 1002, messageType: 'note_off', note: 60, rawBytes: <int>[0x80, 60, 0]),
        raw(seq: 3, ts: 1003, messageType: 'other', channel: 0, note: null, velocity: null, rawBytes: <int>[0xB0, 48, 5]),
      ];

      final a = normalizer.normalizeAll(input);
      final b = normalizer.normalizeAll(input);

      expect(a, b);
      expect(
        a.map((e) => (e.type, e.normalizationRule, e.sourceSeq, e.sourceAppMonotonicTsMs)),
        b.map((e) => (e.type, e.normalizationRule, e.sourceSeq, e.sourceAppMonotonicTsMs)),
      );
    });

    test('normalized events preserve provenance to the exact source raw event', () {
      final event = raw(seq: 3, ts: 5555, velocity: 0, rawBytes: <int>[0x90, 72, 0]);
      final normalized = normalizer.normalize(event);

      expect(identical(normalized.source, event), isTrue);
      expect(normalized.sessionId, event.sessionId);
      expect(normalized.sourceSeq, 3);
      expect(normalized.sourceAppMonotonicTsMs, 5555);
    });

    test('normalized raw bytes view is read-only', () {
      final event = raw(rawBytes: <int>[0x90, 60, 100]);
      final normalized = normalizer.normalize(event);

      expect(normalized.rawBytes, isA<List<int>>());
      // Unmodifiable: write attempts throw.
      expect(() => normalized.rawBytes[0] = 0x00, throwsUnsupportedError);
    });
  });
}