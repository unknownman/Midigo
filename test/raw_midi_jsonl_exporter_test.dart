import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/midi/application/raw_midi_jsonl_exporter.dart';
import 'package:miditutor/midi/domain/raw_midi_event.dart';

RawMidiEvent ev({
  String sessionId = 'session-1',
  String deviceId = '123456',
  String connectionType = 'USB',
  int seq = 1,
  int appMonotonicTsMs = 1234,
  RawMidiMessageType type = RawMidiMessageType.noteOn,
  int? channel,
  int? note,
  int? velocity,
  List<int> rawBytes = const <int>[0x90, 60, 100],
}) {
  return RawMidiEvent(
    sessionId: sessionId,
    deviceId: deviceId,
    connectionType: connectionType,
    seq: seq,
    appMonotonicTsMs: appMonotonicTsMs,
    messageType: type,
    channel: channel,
    note: note,
    velocity: velocity,
    rawBytes: rawBytes,
  );
}

Map<String, Object?> decodeSingleLine(String jsonl) {
  final lines = jsonl.split('\n');
  if (lines.length != 1) {
    throw StateError('Expected exactly one JSONL line but found ${lines.length}');
  }
  return jsonDecode(lines.single) as Map<String, Object?>;
}

void main() {
  group('RawMidiJsonlExporter', () {
    final RawMidiJsonlExporter exporter = JsonlRawMidiEventExporter();

    test('exports an empty string for empty input', () {
      expect(exporter.exportEvents(<RawMidiEvent>[]), isEmpty);
    });

    test('single Note-On event carries all schema fields', () {
      final map = decodeSingleLine(
        exporter.exportEvents(<RawMidiEvent>[
          ev(sessionId: 'session-1', seq: 7, appMonotonicTsMs: 1234),
        ]),
      );

      expect(map, <String, Object?>{
        'schema_version': 1,
        'session_id': 'session-1',
        'seq': 7,
        'app_monotonic_ts_ms': 1234,
        'message_type': 'note_on',
        'status': 144,
        'data': <int>[144, 60, 100],
      });
    });

    test('Note-On velocity 0 stays note_on and never becomes note_off', () {
      final map = decodeSingleLine(
        exporter.exportEvents(<RawMidiEvent>[
          ev(type: RawMidiMessageType.noteOn, rawBytes: <int>[0x90, 60, 0]),
        ]),
      );

      expect(map['message_type'], 'note_on');
      expect(map['status'], 0x90);
      expect(map['data'], <int>[0x90, 60, 0]);
    });

    test('Note-Off event preserves its type and raw bytes', () {
      final map = decodeSingleLine(
        exporter.exportEvents(<RawMidiEvent>[
          ev(type: RawMidiMessageType.noteOff, rawBytes: <int>[0x80, 60, 0]),
        ]),
      );

      expect(map['message_type'], 'note_off');
      expect(map['status'], 0x80);
      expect(map['data'], <int>[0x80, 60, 0]);
    });

    test('non-note MIDI messages export as other with exact bytes', () {
      final map = decodeSingleLine(
        exporter.exportEvents(<RawMidiEvent>[
          ev(type: RawMidiMessageType.other, rawBytes: <int>[0xB0, 0x40, 0x7F]),
        ]),
      );

      expect(map['message_type'], 'other');
      expect(map['status'], 0xB0);
      expect(map['data'], <int>[0xB0, 0x40, 0x7F]);
    });

    test('sequence numbers are preserved and never renumbered', () {
      final lines = exporter
          .exportEvents(<RawMidiEvent>[
            ev(seq: 10),
            ev(seq: 11),
            ev(seq: 15),
          ])
          .split('\n');

      expect(
        lines.map(
            (line) => (jsonDecode(line) as Map<String, Object?>)['seq']),
        <Object?>[10, 11, 15],
      );
    });

    test('timestamps survive serialization exactly', () {
      final lines = exporter
          .exportEvents(<RawMidiEvent>[
            ev(appMonotonicTsMs: 1500),
            ev(appMonotonicTsMs: 7321),
            ev(appMonotonicTsMs: 42),
          ])
          .split('\n');

      expect(
        lines.map((line) =>
            (jsonDecode(line) as Map<String, Object?>)['app_monotonic_ts_ms']),
        <Object?>[1500, 7321, 42],
      );
    });

    test('raw bytes are preserved exactly in order', () {
      final lines = exporter
          .exportEvents(<RawMidiEvent>[
            ev(seq: 1, rawBytes: <int>[0x90, 60, 100]),
            ev(seq: 2, rawBytes: <int>[0x80, 64, 0]),
            ev(seq: 3, rawBytes: <int>[0xB0, 0x40, 0x00, 0x01]),
          ])
          .split('\n');

      final decoded = lines.map(jsonDecode).toList();
      expect((decoded[0] as Map<String, Object?>)['data'], <int>[0x90, 60, 100]);
      expect((decoded[1] as Map<String, Object?>)['data'], <int>[0x80, 64, 0]);
      expect(
          (decoded[2] as Map<String, Object?>)['data'],
          <int>[0xB0, 0x40, 0x00, 0x01]);
    });

    test('multiple events produce one valid JSON line each', () {
      final lines = exporter
          .exportEvents(<RawMidiEvent>[
            ev(seq: 1),
            ev(seq: 2),
            ev(seq: 3),
          ])
          .split('\n');

      expect(lines.length, 3);
      for (final line in lines) {
        expect(() => jsonDecode(line), returnsNormally);
      }
    });

    test('is deterministic for the same ordered input', () {
      final events = <RawMidiEvent>[
        ev(seq: 3, appMonotonicTsMs: 9000),
        ev(seq: 1, appMonotonicTsMs: 100),
        ev(seq: 2, appMonotonicTsMs: 500),
      ];

      final first = exporter.exportEvents(events);
      final second = exporter.exportEvents(events);

      expect(first, second);
    });

    test('preserves caller-supplied order without sorting', () {
      final lines = exporter
          .exportEvents(<RawMidiEvent>[
            ev(seq: 3, appMonotonicTsMs: 9000),
            ev(seq: 1, appMonotonicTsMs: 100),
            ev(seq: 2, appMonotonicTsMs: 500),
          ])
          .split('\n');

      expect(
        lines.map(
            (line) => (jsonDecode(line) as Map<String, Object?>)['seq']),
        <Object?>[3, 1, 2],
      );
    });

    test('no trailing newline so no empty JSONL element is produced', () {
      final jsonl = exporter.exportEvents(<RawMidiEvent>[
        ev(seq: 1),
        ev(seq: 2),
        ev(seq: 3),
      ]);

      expect(jsonl.endsWith('\n'), isFalse);
      expect(jsonl.split('\n').where((line) => line.isEmpty), isEmpty);
    });

    test('serialization does not mutate input events or raw bytes', () {
      final rawBytes = <int>[0x90, 60, 100];
      final event = ev(seq: 1, rawBytes: rawBytes);
      final input = <RawMidiEvent>[event];

      exporter.exportEvents(input);

      expect(event.rawBytes, <int>[0x90, 60, 100]);
      expect(event.seq, 1);
      expect(input.length, 1);
    });
  });
}