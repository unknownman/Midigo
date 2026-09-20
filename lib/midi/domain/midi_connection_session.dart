final class MidiConnectionSession {
  final String sessionId;
  final String deviceId;
  final String connectionType;

  const MidiConnectionSession({
    required this.sessionId,
    required this.deviceId,
    required this.connectionType,
  });

  factory MidiConnectionSession.fromPlatformMap(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
          'Malformed platform response: expected a connection session map.');
    }
    final map = Map<Object?, Object?>.from(raw);

    final sessionId = switch (map['sessionId']) {
      final String value when value.isNotEmpty => value,
      _ => throw const FormatException(
          'Malformed platform response: missing or invalid sessionId.'),
    };

    final deviceId = switch (map['deviceId']) {
      final String value when value.isNotEmpty => value,
      _ => throw const FormatException(
          'Malformed platform response: missing or invalid deviceId.'),
    };

    final connectionType = switch (map['connectionType']) {
      final String value when value.isNotEmpty => value,
      _ => 'USB',
    };

    return MidiConnectionSession(
      sessionId: sessionId,
      deviceId: deviceId,
      connectionType: connectionType,
    );
  }
}