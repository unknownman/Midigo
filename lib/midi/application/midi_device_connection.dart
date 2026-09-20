import 'package:flutter/services.dart';

import '../domain/midi_connection_error.dart';
import '../domain/midi_connection_session.dart';
import '../domain/midi_connection_state.dart';
import '../domain/midi_source_info.dart';

abstract interface class MidiDeviceConnection {
  Future<MidiConnectionSession> connect(MidiSourceInfo source);

  Future<void> disconnect();

  MidiConnectionState get state;

  MidiConnectionSession? get currentSession;
}

final class MacosMidiDeviceConnection implements MidiDeviceConnection {
  MacosMidiDeviceConnection({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('piano_midi/macos');

  static const _connectMethod = 'connectMidiSource';
  static const _disconnectMethod = 'disconnectMidiSource';

  final MethodChannel _channel;

  MidiConnectionState _state = MidiConnectionState.notConnected;
  MidiConnectionSession? _currentSession;

  @override
  MidiConnectionState get state => _state;

  @override
  MidiConnectionSession? get currentSession => _currentSession;

  @override
  Future<MidiConnectionSession> connect(MidiSourceInfo source) async {
    if (_state == MidiConnectionState.connecting ||
        _state == MidiConnectionState.connected) {
      throw const MidiConnectionException(
        MidiConnectionError.alreadyConnected,
        'A MIDI source is already connected.',
      );
    }

    _state = MidiConnectionState.connecting;
    try {
      final raw = await _channel.invokeMethod<Object?>(
        _connectMethod,
        {'id': source.id},
      );
      final session = MidiConnectionSession.fromPlatformMap(raw);
      _currentSession = session;
      _state = MidiConnectionState.connected;
      return session;
    } on PlatformException catch (e) {
      _currentSession = null;
      _state = MidiConnectionState.error;
      throw MidiConnectionException(
        MidiConnectionError.fromPlatformCode(e.code),
        e.message ?? 'The platform could not establish a MIDI connection.',
      );
    } on MissingPluginException {
      _currentSession = null;
      _state = MidiConnectionState.error;
      throw const MidiConnectionException(
        MidiConnectionError.unknown,
        'The MIDI platform adapter is unavailable.',
      );
    } on FormatException {
      _currentSession = null;
      _state = MidiConnectionState.error;
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    if (_state == MidiConnectionState.connecting) {
      throw const MidiConnectionException(
        MidiConnectionError.connectionFailed,
        'A connection is still being established.',
      );
    }
    if (_state != MidiConnectionState.connected) {
      _currentSession = null;
      _state = MidiConnectionState.disconnected;
      return;
    }

    _state = MidiConnectionState.disconnecting;
    try {
      await _channel.invokeMethod<void>(_disconnectMethod);
      _currentSession = null;
      _state = MidiConnectionState.disconnected;
    } on PlatformException catch (e) {
      // The native session state failed to tear down cleanly; the Dart-side
      // session must still be dropped to keep the application consistent.
      _currentSession = null;
      _state = MidiConnectionState.disconnected;
      throw MidiConnectionException(
        MidiConnectionError.fromPlatformCode(e.code),
        e.message ?? 'The platform could not disconnect the MIDI source.',
      );
    } on MissingPluginException {
      _currentSession = null;
      _state = MidiConnectionState.disconnected;
      throw const MidiConnectionException(
        MidiConnectionError.unknown,
        'The MIDI platform adapter is unavailable.',
      );
    }
  }
}