import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/midi/application/raw_midi_jsonl_exporter.dart';
import 'package:miditutor/midi/application/raw_midi_jsonl_reader.dart';
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

String line({
  int schemaVersion = 1,
  String sessionId = 's',
  int seq = 0,
  int ts = 1000,
  String messageType = 'note_on',
  int status = 144,
  List<int>? data,
  bool includeSchemaVersion = true,
  bool includeSessionId = true,
  bool includeSeq = true,
  bool includeTs = true,
  bool includeMessageType = true,
  bool includeStatus = true,
  bool includeData = true,
}) {
  final fields = <String>[];
  if (includeSchemaVersion) fields.add('"schema_version":$schemaVersion');
  if (includeSessionId) fields.add('"session_id":"$sessionId"');
  if (includeSeq) fields.add('"seq":$seq');
  if (includeTs) fields.add('"app_monotonic_ts_ms":$ts');
  if (includeMessageType) fields.add('"message_type":"$messageType"');
  if (includeStatus) fields.add('"status":$status');
  if (includeData) fields.add('"data":${data ?? <int>[144, 60, 100]}');
  return '{${fields.join(',')}}';
}

void main() {
  const reader = JsonlRawMidiEventReader();
  final exporter = JsonlRawMidiEventExporter();

  group('replay reader - happy path', () {
    test('round-trips exporter output with all fields preserved', () {
      final input = <RawMidiEvent>[
        ev(sessionId: 'session-1', seq: 7, appMonotonicTsMs: 1234),
        ev(seq: 8, appMonotonicTsMs: 1250, type: RawMidiMessageType.noteOff,
            rawBytes: <int>[0x80, 60, 0]),
      ];

      final result = reader.read(exporter.exportEvents(input));

      expect(result.status, JsonlReplayStatus.success);
      expect(result.issues, isEmpty);
      expect(result.events, hasLength(2));

      final first = result.events[0];
      expect(first.sessionId, 'session-1');
      expect(first.seq, 7);
      expect(first.appMonotonicTsMs, 1234);
      expect(first.messageType, RawMidiMessageType.noteOn);
      expect(first.channel, 0);
      expect(first.note, 60);
      expect(first.velocity, 100);
      expect(first.rawBytes, <int>[0x90, 60, 100]);

      final second = result.events[1];
      expect(second.messageType, RawMidiMessageType.noteOff);
      expect(second.note, 60);
      expect(second.velocity, 0);
      expect(second.rawBytes, <int>[0x80, 60, 0]);
    });

    test('preserves stored order exactly, never sorting by timestamp', () {
      final jsonl = [
        line(seq: 3, ts: 9000),
        line(seq: 1, ts: 100),
        line(seq: 2, ts: 500),
      ].join('\n');

      final result = reader.read(jsonl);

      expect(result.events.map((e) => e.seq), <int>[3, 1, 2]);
      expect(result.events.map((e) => e.appMonotonicTsMs), <int>[9000, 100, 500]);
    });

    test('velocity-zero note_on replays as raw note_on, never note_off', () {
      final result = reader.read(line(
        messageType: 'note_on',
        status: 144,
        data: <int>[144, 60, 0],
      ));

      expect(result.status, JsonlReplayStatus.success);
      final event = result.events.single;
      expect(event.messageType, RawMidiMessageType.noteOn);
      expect(event.velocity, 0);
      expect(event.note, 60);
      expect(event.rawBytes, <int>[144, 60, 0]);
    });

    test('reconstructs channel/note/velocity like live H1 capture decoding', () {
      final result = reader.read([
        line(messageType: 'note_on', status: 145, data: <int>[145, 67, 33]),
        line(messageType: 'note_off', status: 129, data: <int>[129, 60, 0]),
        line(messageType: 'other', status: 176, data: <int>[176, 64, 127]),
        line(messageType: 'other', status: 248, data: <int>[248]),
      ].join('\n'));

      final on = result.events[0];
      expect(on.channel, 1);
      expect(on.note, 67);
      expect(on.velocity, 33);

      final off = result.events[1];
      expect(off.channel, 1);
      expect(off.note, 60);
      expect(off.velocity, 0);

      // CC: channel from status, but no note/velocity.
      final cc = result.events[2];
      expect(cc.channel, 0);
      expect(cc.note, isNull);
      expect(cc.velocity, isNull);

      // System clock (0xF8): no channel, no note, no velocity.
      final clock = result.events[3];
      expect(clock.channel, isNull);
      expect(clock.note, isNull);
      expect(clock.velocity, isNull);
    });

    test('empty input is a valid success with no events', () {
      final result = reader.read('');
      expect(result.status, JsonlReplayStatus.success);
      expect(result.events, isEmpty);
      expect(result.issues, isEmpty);
    });

    test('blank and whitespace-only lines are ignored deterministically', () {
      final result = reader.read(
          '\n  \n${line(seq: 0)}\n\n\t\n${line(seq: 1)}\n');

      expect(result.status, JsonlReplayStatus.success);
      expect(result.events.map((e) => e.seq), <int>[0, 1]);
    });

    test('replayed events and their raw bytes are immutable', () {
      final result = reader.read(
          '${line(seq: 0)}\n${line(seq: 1, messageType: 'note_off', status: 128, data: <int>[128, 60, 0])}');

      expect(() => result.events.add(ev()), throwsUnsupportedError);
      expect(() => result.events[0].rawBytes.add(0xFF), throwsUnsupportedError);
      expect(() => result.events[0].rawBytes.clear(), throwsUnsupportedError);
    });

    test('is deterministic for the same input', () {
      final jsonl = '${line(seq: 3, ts: 9000)}\n${line(seq: 1, ts: 100)}\n';

      final first = reader.read(jsonl);
      final second = reader.read(jsonl);

      expect(second.events[0].seq, first.events[0].seq);
      expect(second.status, first.status);
      expect(second.issues, first.issues);
    });
  });

  group('replay reader - malformed input policy', () {
    test('invalid JSON is a parse failure naming the line', () {
      final result = reader.read('${line(seq: 0)}\nnot-json');

      expect(result.status, JsonlReplayStatus.parseFailure);
      expect(result.events, isEmpty);
      expect(result.issues.single.lineNumber, 2);
      expect(result.issues.single.category, 'invalid_json');
      expect(result.issues.single.reason, contains('unparseable JSON'));
    });

    test('non-object JSON is a parse failure', () {
      final result = reader.read('[1,2,3]');

      expect(result.status, JsonlReplayStatus.parseFailure);
      expect(result.issues.single.lineNumber, 1);
      expect(result.issues.single.category, 'non_object_json');
    });

    test('missing required field is a parse failure', () {
      for (final entry in <String, String>{
        'schema_version': line(includeSchemaVersion: false),
        'session_id': line(includeSessionId: false),
        'seq': line(includeSeq: false),
        'app_monotonic_ts_ms': line(includeTs: false),
        'message_type': line(includeMessageType: false),
        'status': line(includeStatus: false),
        'data': line(includeData: false),
      }.entries) {
        final result = reader.read(entry.value);
        expect(result.status, JsonlReplayStatus.parseFailure,
            reason: 'field: ${entry.key}');
        expect(result.issues.single.category, 'missing_field',
            reason: 'field: ${entry.key}');
        expect(result.issues.single.lineNumber, 1);
      }
    });

    test('invalid field type is a parse failure', () {
      final variants = <String>[
        '{"schema_version":"1","session_id":"s","seq":0,"app_monotonic_ts_ms":1,"message_type":"note_on","status":144,"data":[144,60,100]}',
        '{"schema_version":1,"session_id":5,"seq":0,"app_monotonic_ts_ms":1,"message_type":"note_on","status":144,"data":[144,60,100]}',
        '{"schema_version":1,"session_id":"s","seq":"0","app_monotonic_ts_ms":1,"message_type":"note_on","status":144,"data":[144,60,100]}',
        '{"schema_version":1,"session_id":"s","seq":0,"app_monotonic_ts_ms":true,"message_type":"note_on","status":144,"data":[144,60,100]}',
        '{"schema_version":1,"session_id":"s","seq":0,"app_monotonic_ts_ms":1,"message_type":7,"status":144,"data":[144,60,100]}',
        '{"schema_version":1,"session_id":"s","seq":0,"app_monotonic_ts_ms":1,"message_type":"note_on","status":"144","data":[144,60,100]}',
      ];

      for (final jsonl in variants) {
        final result = reader.read(jsonl);
        expect(result.status, JsonlReplayStatus.parseFailure);
        expect(result.issues.single.category, 'invalid_field_type',
            reason: jsonl);
        expect(result.issues.single.lineNumber, 1);
      }
    });

    test('invalid raw byte list is a parse failure', () {
      final variants = <String, String>{
        line(data: <int>[144, 60, 300]): 'invalid_raw_bytes',
        '{"schema_version":1,"session_id":"s","seq":0,"app_monotonic_ts_ms":1,"message_type":"note_on","status":144,"data":[144,"60",100]}':
            'invalid_raw_bytes',
        '{"schema_version":1,"session_id":"s","seq":0,"app_monotonic_ts_ms":1,"message_type":"note_on","status":144,"data":"not-a-list"}':
            'invalid_field_type',
      };

      variants.forEach((jsonl, expectedCategory) {
        final result = reader.read(jsonl);
        expect(result.status, JsonlReplayStatus.parseFailure, reason: jsonl);
        expect(result.issues.single.category, expectedCategory, reason: jsonl);
      });
    });

    test('out-of-range status byte is a parse failure', () {
      final result = reader.read(line(status: -1));
      expect(result.status, JsonlReplayStatus.parseFailure);
      expect(result.issues.single.category, 'invalid_field_type');

      final high = reader.read(line(status: 256));
      expect(high.status, JsonlReplayStatus.parseFailure);
    });

    test('unknown message type is a parse failure', () {
      final result = reader.read(line(messageType: 'program_change'));
      expect(result.status, JsonlReplayStatus.parseFailure);
      expect(result.issues.single.category, 'unknown_message_type');
    });

    test('status byte inconsistent with data[0] is a parse failure', () {
      final mismatch = reader.read(line(status: 128, data: <int>[144, 60, 100]));
      expect(mismatch.status, JsonlReplayStatus.parseFailure);
      expect(mismatch.issues.single.category, 'inconsistent_record');

      final emptyWithStatus = reader.read(
          line(status: 144, data: <int>[], includeData: true));
      expect(emptyWithStatus.status, JsonlReplayStatus.parseFailure);
    });

    test('unsupported schema version is a schema failure', () {
      final result = reader.read(line(schemaVersion: 2));

      expect(result.status, JsonlReplayStatus.schemaFailure);
      expect(result.events, isEmpty);
      expect(result.issues.single.category, 'unsupported_schema_version');
      expect(result.issues.single.reason, contains('schema version'));
    });

    test('first malformed line aborts replay without partial events', () {
      final jsonl =
          '${line(seq: 0)}\n${line(seq: 1)}\nbad-json\n${line(seq: 3)}';

      final result = reader.read(jsonl);
      expect(result.status, JsonlReplayStatus.parseFailure);
      expect(result.events, isEmpty);
      expect(result.issues.single.lineNumber, 3);
    });

    test('parsed JSON is not modified by the reader', () {
      final jsonl = '${line(seq: 5, ts: 777)}\n';
      final result = reader.read(jsonl);

      expect(result.events.single.seq, 5);
      expect(result.events.single.appMonotonicTsMs, 777);
    });
  });
}