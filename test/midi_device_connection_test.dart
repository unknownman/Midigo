import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/midi/application/midi_device_connection.dart';
import 'package:miditutor/midi/domain/midi_connection_error.dart';
import 'package:miditutor/midi/domain/midi_connection_session.dart';
import 'package:miditutor/midi/domain/midi_connection_state.dart';
import 'package:miditutor/midi/domain/midi_source_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('piano_midi/macos');

  const source = MidiSourceInfo(
    id: '123456',
    name: 'Example MIDI Keyboard',
    manufacturer: 'Example Manufacturer',
  );

  void mockHandler(
      Future<Object?>? Function(MethodCall call)? handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  setUp(() {
    mockHandler(null);
  });

  Future<MidiConnectionSession> connectThrough(
    MacosMidiDeviceConnection connection,
  ) {
    return connection.connect(const MidiSourceInfo(
      id: '654321',
      name: 'Other Keyboard',
      manufacturer: 'Other Maker',
    ));
  }

  test('starts in the notConnected state with no session', () {
    final connection = MacosMidiDeviceConnection(channel: channel);

    expect(connection.state, MidiConnectionState.notConnected);
    expect(connection.currentSession, isNull);
  });

  test('connect succeeds and returns an active session', () async {
    mockHandler((MethodCall call) async {
      expect(call.method, 'connectMidiSource');
      expect((call.arguments as Map)['id'], '123456');
      return <String, dynamic>{
        'sessionId': 'session-1',
        'deviceId': '123456',
        'connectionType': 'USB',
      };
    });

    final connection = MacosMidiDeviceConnection(channel: channel);
    final session = await connection.connect(source);

    expect(session.sessionId, 'session-1');
    expect(connection.currentSession, isNotNull);
    expect(connection.state, MidiConnectionState.connected);
  });

  test('preserves the connected device id from the platform response',
      () async {
    mockHandler((MethodCall call) async {
      return <String, dynamic>{
        'sessionId': 'session-1',
        'deviceId': '123456',
        'connectionType': 'USB',
      };
    });

    final connection = MacosMidiDeviceConnection(channel: channel);
    final session = await connection.connect(source);

    expect(session.deviceId, '123456');
  });

  test('session exposes a USB connection type', () async {
    mockHandler((MethodCall call) async {
      return <String, dynamic>{
        'sessionId': 'session-1',
        'deviceId': '123456',
        'connectionType': 'USB',
      };
    });

    final connection = MacosMidiDeviceConnection(channel: channel);
    final session = await connection.connect(source);

    expect(session.connectionType, 'USB');
  });

  test('session id is non-empty after a successful connect', () async {
    mockHandler((MethodCall call) async {
      return <String, dynamic>{
        'sessionId': 'session-1',
        'deviceId': '123456',
        'connectionType': 'USB',
      };
    });

    final connection = MacosMidiDeviceConnection(channel: channel);
    final session = await connection.connect(source);

    expect(session.sessionId, isNotEmpty);
  });

  test('reconnecting produces a fresh session id and no longer shares the old session',
      () async {
    var connectCount = 0;
    mockHandler((MethodCall call) async {
      if (call.method == 'connectMidiSource') {
        connectCount += 1;
        return <String, dynamic>{
          'sessionId': 'session-$connectCount',
          'deviceId': '123456',
          'connectionType': 'USB',
        };
      }
      if (call.method == 'disconnectMidiSource') {
        return null;
      }
      return null;
    });

    final connection = MacosMidiDeviceConnection(channel: channel);
    final first = await connection.connect(source);
    await connection.disconnect();
    final second = await connection.connect(source);

    expect(first.sessionId, isNot(second.sessionId));
    expect(connectCount, 2);
    expect(connection.currentSession?.sessionId, second.sessionId);
  });

  test('disconnect clears the active session and state', () async {
    mockHandler((MethodCall call) async {
      if (call.method == 'connectMidiSource') {
        return <String, dynamic>{
          'sessionId': 'session-1',
          'deviceId': '123456',
          'connectionType': 'USB',
        };
      }
      return null;
    });

    final connection = MacosMidiDeviceConnection(channel: channel);
    await connection.connect(source);
    await connection.disconnect();

    expect(connection.currentSession, isNull);
    expect(connection.state, MidiConnectionState.disconnected);
  });

  test('disconnect with no active session is safe', () async {
    mockHandler((MethodCall call) async {
      return null;
    });

    final connection = MacosMidiDeviceConnection(channel: channel);
    await connection.disconnect();

    expect(connection.currentSession, isNull);
    expect(connection.state, MidiConnectionState.disconnected);
  });

  test('connecting while already connected is rejected deterministically',
      () async {
    var disconnectCalls = 0;
    mockHandler((MethodCall call) async {
      if (call.method == 'connectMidiSource') {
        return <String, dynamic>{
          'sessionId': 'session-1',
          'deviceId': '123456',
          'connectionType': 'USB',
        };
      }
      if (call.method == 'disconnectMidiSource') {
        disconnectCalls += 1;
        return null;
      }
      return null;
    });

    final connection = MacosMidiDeviceConnection(channel: channel);
    await connection.connect(source);

    await expectLater(
      connectThrough(connection),
      throwsA(isA<MidiConnectionException>().having(
        (e) => e.code,
        'code',
        MidiConnectionError.alreadyConnected,
      )),
    );
    expect(disconnectCalls, 0);
    expect(connection.currentSession?.sessionId, 'session-1');
  });

  test('a malformed platform response is rejected without exposing a session',
      () async {
    mockHandler((MethodCall call) async {
      return <String, dynamic>{'unexpected': true};
    });

    final connection = MacosMidiDeviceConnection(channel: channel);

    await expectLater(connection.connect(source), throwsFormatException);
    expect(connection.currentSession, isNull);
    expect(connection.state, MidiConnectionState.error);
  });

  test('a platform connection error surfaces as a typed MidiConnectionException',
      () async {
    mockHandler((MethodCall call) async {
      throw PlatformException(code: 'NO_SOURCE', message: 'Not found.');
    });

    final connection = MacosMidiDeviceConnection(channel: channel);

    await expectLater(
      connection.connect(source),
      throwsA(isA<MidiConnectionException>()
          .having((e) => e.code, 'code', MidiConnectionError.noSource)),
    );
    expect(connection.currentSession, isNull);
    expect(connection.state, MidiConnectionState.error);
  });
}