enum RawMidiMessageType {
  noteOn,
  noteOff,
  other;

  static RawMidiMessageType fromPlatformValue(Object? value) {
    return switch (value) {
      'note_on' => RawMidiMessageType.noteOn,
      'note_off' => RawMidiMessageType.noteOff,
      _ => RawMidiMessageType.other,
    };
  }

  String get displayLabel => switch (this) {
        RawMidiMessageType.noteOn => 'NOTE_ON',
        RawMidiMessageType.noteOff => 'NOTE_OFF',
        RawMidiMessageType.other => 'OTHER',
      };
}

final class RawMidiEvent {
  final String sessionId;
  final String deviceId;
  final String connectionType;
  final int seq;
  final int appMonotonicTsMs;
  final RawMidiMessageType messageType;
  final int? channel;
  final int? note;
  final int? velocity;
  final List<int> rawBytes;

  RawMidiEvent({
    required this.sessionId,
    required this.deviceId,
    required this.connectionType,
    required this.seq,
    required this.appMonotonicTsMs,
    required this.messageType,
    this.channel,
    this.note,
    this.velocity,
    required List<int> rawBytes,
  }) : rawBytes = List<int>.unmodifiable(rawBytes);

  factory RawMidiEvent.fromPlatformMap(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
          'Malformed platform event: expected a MIDI event map.');
    }
    final map = Map<Object?, Object?>.from(raw);

    final sessionId = _requiredString(map, 'sessionId');
    final deviceId = _requiredString(map, 'deviceId');
    final connectionType = _optionalString(map, 'connectionType') ?? 'USB';
    final seq = _requiredInt(map, 'seq');
    final appMonotonicTsMs = _requiredInt(map, 'appMonotonicTsMs');
    final messageType = RawMidiMessageType.fromPlatformValue(map['messageType']);
    final channel = _optionalInt(map, 'channel');
    final note = _optionalInt(map, 'note');
    final velocity = _optionalInt(map, 'velocity');
    final rawBytes = _requiredBytes(map, 'rawBytes');

    return RawMidiEvent(
      sessionId: sessionId,
      deviceId: deviceId,
      connectionType: connectionType,
      seq: seq,
      appMonotonicTsMs: appMonotonicTsMs,
      messageType: messageType,
      channel: channel,
      note: note,
      velocity: velocity,
      rawBytes: rawBytes,
    );
  }

  static String _requiredString(Map<Object?, Object?> map, String key) {
    final value = map[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw FormatException(
        'Malformed platform event: missing or invalid $key.');
  }

  static int _requiredInt(Map<Object?, Object?> map, String key) {
    final value = map[key];
    if (value is int) {
      return value;
    }
    throw FormatException(
        'Malformed platform event: missing or invalid $key.');
  }

  static String? _optionalString(Map<Object?, Object?> map, String key) {
    final value = map[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  static int? _optionalInt(Map<Object?, Object?> map, String key) {
    final value = map[key];
    return value is int ? value : null;
  }

  static List<int> _requiredBytes(Map<Object?, Object?> map, String key) {
    final value = map[key];
    if (value is! List) {
      throw FormatException(
          'Malformed platform event: missing or invalid $key.');
    }
    return List<int>.from(value.map((e) {
      if (e is int) {
        return e;
      }
      throw FormatException(
          'Malformed platform event: invalid byte in $key.');
    }));
  }

  @override
  String toString() =>
      'RawMidiEvent($messageType seq=$seq note=$note velocity=$velocity)';
}