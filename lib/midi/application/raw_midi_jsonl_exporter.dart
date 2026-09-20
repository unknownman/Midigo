import 'dart:convert';

import '../domain/raw_midi_event.dart';

/// Serializes captured raw MIDI events to JSON Lines (JSONL).
///
/// One event per line. Exports only the fields defined by the JSONL schema
/// and preserves caller-supplied order. Deterministic: no sorting, no generated
/// ids or timestamps, and no normalization of the captured MIDI bytes.
abstract interface class RawMidiJsonlExporter {
  String exportEvents(Iterable<RawMidiEvent> events);
}

final class JsonlRawMidiEventExporter implements RawMidiJsonlExporter {
  static const int _schemaVersion = 1;

  @override
  String exportEvents(Iterable<RawMidiEvent> events) => events
      .map((event) => jsonEncode(_toJsonMap(event)))
      .join('\n');

  Map<String, Object> _toJsonMap(RawMidiEvent event) => <String, Object>{
        'schema_version': _schemaVersion,
        'session_id': event.sessionId,
        'seq': event.seq,
        'app_monotonic_ts_ms': event.appMonotonicTsMs,
        'message_type': _messageTypeValue(event.messageType),
        'status': _statusByte(event),
        'data': event.rawBytes,
      };

  static String _messageTypeValue(RawMidiMessageType type) => switch (type) {
        RawMidiMessageType.noteOn => 'note_on',
        RawMidiMessageType.noteOff => 'note_off',
        RawMidiMessageType.other => 'other',
      };

  static int _statusByte(RawMidiEvent event) =>
      event.rawBytes.isEmpty ? 0 : event.rawBytes.first;
}