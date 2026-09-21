import 'dart:convert';

import '../domain/raw_midi_event.dart';

/// Outcome of a raw JSONL replay.
///
/// * [success] - every non-blank record parsed into a [RawMidiEvent].
/// * [parseFailure] - at least one record is structurally malformed.
/// * [schemaFailure] - a record declares an unsupported schema version.
enum JsonlReplayStatus { success, parseFailure, schemaFailure }

/// Deterministic structured failure describing one malformed JSONL record.
///
/// Carries the 1-based [lineNumber], a stable [category], and a concise
/// [reason]. No stack traces are embedded in the domain result.
final class JsonlReplayIssue {
  final int lineNumber;
  final String category;
  final String reason;

  const JsonlReplayIssue({
    required this.lineNumber,
    required this.category,
    required this.reason,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JsonlReplayIssue &&
          other.lineNumber == lineNumber &&
          other.category == category &&
          other.reason == reason;

  @override
  int get hashCode => Object.hash(lineNumber, category, reason);

  @override
  String toString() => 'line $lineNumber: $category: $reason';
}

/// Immutable result of replaying one JSONL document.
///
/// On [JsonlReplayStatus.success] [events] holds the parsed raw events in
/// stored order and [issues] is empty. On any failure [events] is empty and
/// [issues] holds the first offending record (replay aborts deterministically
/// at the first malformed line; malformed records are never skipped or
/// repaired).
final class JsonlReplayResult {
  final JsonlReplayStatus status;
  final List<RawMidiEvent> events;
  final List<JsonlReplayIssue> issues;

  bool get isSuccess => status == JsonlReplayStatus.success;

  const JsonlReplayResult({
    required this.status,
    required this.events,
    required this.issues,
  });
}

/// Reads persisted raw H1 JSONL back into [RawMidiEvent] objects.
///
/// Consumes the H1 JSONL schema written by [JsonlRawMidiEventExporter]:
///
/// ```json
/// {"schema_version":1,"session_id":"s","seq":0,"app_monotonic_ts_ms":1000,
///  "message_type":"note_on","status":144,"data":[144,60,100]}
/// ```
///
/// The reader is strictly deterministic: one JSON object per line, event order
/// preserved exactly as stored (never re-sorted, never renumbered), and
/// malformed records reported without silent repair. Blank (whitespace-only)
/// lines are ignored.
///
/// The raw `message_type` field is authoritative: a persisted `note_on` with
/// velocity 0 stays a raw Note-On here; velocity-zero normalization is a
/// downstream H2.1 concern and is deliberately not applied.
abstract interface class RawMidiJsonlReader {
  JsonlReplayResult read(String jsonl);
}

/// Default reader for the H1 JSONL schema (version 1).
///
/// channel/note/velocity are reconstructed from the stored `status`/`data`
/// bytes using the same byte-decoding the H1 capture applied at the platform
/// boundary: Note-On/Note-Off carry channel `status & 0x0F`, note from
/// data[1] and velocity from data[2]; everything else carries no note or
/// velocity and only a channel when its status is below `0xF0`.
final class JsonlRawMidiEventReader implements RawMidiJsonlReader {
  static const int supportedSchemaVersion = 1;

  /// Placeholders for fields the H1 JSONL schema does not carry. The capture
  /// device identity and transport type are not part of the persisted schema,
  /// so a replayed event cannot recover them; the H2 pipeline does not consume
  /// either field.
  static const String replayDeviceId = 'replay';
  static const String replayConnectionType = 'REPLAY';

  const JsonlRawMidiEventReader();

  @override
  JsonlReplayResult read(String jsonl) {
    final events = <RawMidiEvent>[];
    final lines = const LineSplitter().convert(jsonl);
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final record = _parseRecord(trimmed, index + 1);
      switch (record) {
        case _RecordEvent():
          events.add(record.event);
        case _RecordIssue():
          return JsonlReplayResult(
            status: record.status,
            events: const <RawMidiEvent>[],
            issues: List<JsonlReplayIssue>.unmodifiable([record.issue]),
          );
        default:
          throw StateError('reader internal invariant violated');
      }
    }
    return JsonlReplayResult(
      status: JsonlReplayStatus.success,
      events: List<RawMidiEvent>.unmodifiable(events),
      issues: const <JsonlReplayIssue>[],
    );
  }

  _RecordResult _parseRecord(String line, int lineNumber) {
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException catch (e) {
      return _issue(
        JsonlReplayStatus.parseFailure,
        lineNumber,
        'invalid_json',
        'unparseable JSON: ${e.message}',
      );
    }
    if (decoded is! Map) {
      return _issue(
        JsonlReplayStatus.parseFailure,
        lineNumber,
        'non_object_json',
        'expected a JSON object per line',
      );
    }
    final map = Map<String, Object?>.from(decoded);

    final schemaVersion = _requiredInt(map, 'schema_version');
    if (schemaVersion case _RecordIssue()) {
      return _atLine(schemaVersion, lineNumber);
    }
    final version = (schemaVersion as _RecordInt).value;
    if (version != supportedSchemaVersion) {
      return _issue(
        JsonlReplayStatus.schemaFailure,
        lineNumber,
        'unsupported_schema_version',
        'expected schema version $supportedSchemaVersion, found $version',
      );
    }

    final sessionId = _requiredString(map, 'session_id');
    if (sessionId case _RecordIssue()) {
      return _atLine(sessionId, lineNumber);
    }
    final seq = _requiredInt(map, 'seq');
    if (seq case _RecordIssue()) {
      return _atLine(seq, lineNumber);
    }
    final timestamp = _requiredInt(map, 'app_monotonic_ts_ms');
    if (timestamp case _RecordIssue()) {
      return _atLine(timestamp, lineNumber);
    }
    final status = _requiredByte(map, 'status');
    if (status case _RecordIssue()) {
      return _atLine(status, lineNumber);
    }
    final data = _requiredByteList(map, 'data');
    if (data case _RecordIssue()) {
      return _atLine(data, lineNumber);
    }

    final messageTypeResult = _messageType(map);
    if (messageTypeResult case _RecordIssue()) {
      return _atLine(messageTypeResult, lineNumber);
    }
    final messageType = (messageTypeResult as _RecordMessageType).value;

    final statusValue = (status as _RecordInt).value;
    final dataValue = (data as _RecordByteList).value;
    if (dataValue.isEmpty) {
      if (statusValue != 0) {
        return _issue(
          JsonlReplayStatus.parseFailure,
          lineNumber,
          'inconsistent_record',
          'status $statusValue with empty data bytes',
        );
      }
    } else if (statusValue != dataValue.first) {
      return _issue(
        JsonlReplayStatus.parseFailure,
        lineNumber,
        'inconsistent_record',
        'status byte $statusValue does not match data[0] ${dataValue.first}',
      );
    }

    return _RecordEvent(RawMidiEvent(
      sessionId: (sessionId as _RecordString).value,
      deviceId: replayDeviceId,
      connectionType: replayConnectionType,
      seq: (seq as _RecordInt).value,
      appMonotonicTsMs: (timestamp as _RecordInt).value,
      messageType: messageType,
      channel: _channelFor(messageType, dataValue),
      note: _noteFor(messageType, dataValue),
      velocity: _velocityFor(messageType, dataValue),
      rawBytes: dataValue,
    ));
  }

  static int? _channelFor(RawMidiMessageType type, List<int> data) {
    if (data.isEmpty) {
      return null;
    }
    if (type == RawMidiMessageType.noteOn ||
        type == RawMidiMessageType.noteOff) {
      return data[0] & 0x0F;
    }
    return data[0] < 0xF0 ? data[0] & 0x0F : null;
  }

  static int? _noteFor(RawMidiMessageType type, List<int> data) {
    if ((type == RawMidiMessageType.noteOn ||
            type == RawMidiMessageType.noteOff) &&
        data.length > 1) {
      return data[1];
    }
    return null;
  }

  static int? _velocityFor(RawMidiMessageType type, List<int> data) {
    if ((type == RawMidiMessageType.noteOn ||
            type == RawMidiMessageType.noteOff) &&
        data.length > 2) {
      return data[2];
    }
    return null;
  }

  static _RecordResult _messageType(Map<String, Object?> map) {
    final value = map['message_type'];
    if (value == null) {
      return _RecordIssue(
        JsonlReplayStatus.parseFailure,
        JsonlReplayIssue(
          lineNumber: -1,
          category: 'missing_field',
          reason: 'required field "message_type" is absent',
        ),
      );
    }
    if (value is! String) {
      return _RecordIssue(
        JsonlReplayStatus.parseFailure,
        JsonlReplayIssue(
          lineNumber: -1,
          category: 'invalid_field_type',
          reason: 'field "message_type" has an invalid type or value',
        ),
      );
    }
    switch (value) {
      case 'note_on':
        return const _RecordMessageType(RawMidiMessageType.noteOn);
      case 'note_off':
        return const _RecordMessageType(RawMidiMessageType.noteOff);
      case 'other':
        return const _RecordMessageType(RawMidiMessageType.other);
    }
    return _RecordIssue(
      JsonlReplayStatus.parseFailure,
      JsonlReplayIssue(
        lineNumber: -1,
        category: 'unknown_message_type',
        reason: 'unsupported message_type "$value"',
      ),
    );
  }

  static _RecordResult _requiredInt(
      Map<String, Object?> map, String key) {
    final value = map[key];
    if (value == null) {
      return _missing(key);
    }
    if (value is! int) {
      return _invalidType(key);
    }
    return _RecordInt(value);
  }

  static _RecordResult _requiredString(
      Map<String, Object?> map, String key) {
    final value = map[key];
    if (value == null) {
      return _missing(key);
    }
    if (value is! String || value.isEmpty) {
      return _invalidType(key);
    }
    return _RecordString(value);
  }

  static _RecordResult _requiredByte(
      Map<String, Object?> map, String key) {
    final intResult = _requiredInt(map, key);
    if (intResult case _RecordInt()) {
      final value = intResult.value;
      if (value < 0 || value > 255) {
        return _RecordIssue(
          JsonlReplayStatus.parseFailure,
          JsonlReplayIssue(
            lineNumber: -1,
            category: 'invalid_field_type',
            reason: '$key must be a byte in 0..255',
          ),
        );
      }
      return intResult;
    }
    return intResult;
  }

  static _RecordResult _requiredByteList(
      Map<String, Object?> map, String key) {
    final value = map[key];
    if (value == null) {
      return _missing(key);
    }
    if (value is! List) {
      return _invalidType(key);
    }
    final bytes = <int>[];
    for (final element in value) {
      if (element is! int || element < 0 || element > 255) {
        return _RecordIssue(
          JsonlReplayStatus.parseFailure,
          JsonlReplayIssue(
            lineNumber: -1,
            category: 'invalid_raw_bytes',
            reason: '$key must contain only bytes in 0..255',
          ),
        );
      }
      bytes.add(element);
    }
    return _RecordByteList(List<int>.unmodifiable(bytes));
  }

  static _RecordIssue _missing(String key) => _RecordIssue(
        JsonlReplayStatus.parseFailure,
        JsonlReplayIssue(
          lineNumber: -1,
          category: 'missing_field',
          reason: 'required field "$key" is absent',
        ),
      );

  static _RecordIssue _invalidType(String key) => _RecordIssue(
        JsonlReplayStatus.parseFailure,
        JsonlReplayIssue(
          lineNumber: -1,
          category: 'invalid_field_type',
          reason: 'field "$key" has an invalid type or value',
        ),
      );

  static _RecordIssue _issue(JsonlReplayStatus status, int lineNumber,
          String category, String reason) =>
      _RecordIssue(
        status,
        JsonlReplayIssue(
          lineNumber: lineNumber,
          category: category,
          reason: reason,
        ),
      );

  /// Rebinds a field-level issue to the line that produced it.
  static _RecordIssue _atLine(_RecordIssue issue, int lineNumber) =>
      _RecordIssue(
        issue.status,
        JsonlReplayIssue(
          lineNumber: lineNumber,
          category: issue.issue.category,
          reason: issue.issue.reason,
        ),
      );
}

sealed class _RecordResult {
  const _RecordResult();
}

final class _RecordEvent extends _RecordResult {
  final RawMidiEvent event;
  _RecordEvent(this.event);
}

final class _RecordIssue extends _RecordResult {
  final JsonlReplayStatus status;
  final JsonlReplayIssue issue;
  _RecordIssue(this.status, this.issue);
}

final class _RecordInt extends _RecordResult {
  final int value;
  _RecordInt(this.value);
}

final class _RecordString extends _RecordResult {
  final String value;
  _RecordString(this.value);
}

final class _RecordMessageType extends _RecordResult {
  final RawMidiMessageType value;
  const _RecordMessageType(this.value);
}

final class _RecordByteList extends _RecordResult {
  final List<int> value;
  _RecordByteList(this.value);
}