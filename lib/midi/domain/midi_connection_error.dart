enum MidiConnectionError {
  noSource,
  alreadyConnected,
  notConnected,
  connectionFailed,
  disconnectFailed,
  invalidRequest,
  unknown;

  static MidiConnectionError fromPlatformCode(String code) {
    return switch (code) {
      'NO_SOURCE' => MidiConnectionError.noSource,
      'ALREADY_CONNECTED' => MidiConnectionError.alreadyConnected,
      'NOT_CONNECTED' => MidiConnectionError.notConnected,
      'CONNECTION_FAILED' => MidiConnectionError.connectionFailed,
      'DISCONNECT_FAILED' => MidiConnectionError.disconnectFailed,
      'INVALID_REQUEST' => MidiConnectionError.invalidRequest,
      _ => MidiConnectionError.unknown,
    };
  }
}

final class MidiConnectionException implements Exception {
  const MidiConnectionException(this.code, this.message);

  final MidiConnectionError code;
  final String message;

  @override
  String toString() => 'MidiConnectionException(${code.name}): $message';
}