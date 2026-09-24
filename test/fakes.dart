import 'dart:async';

import 'package:miditutor/midi/application/midi_device_connection.dart';
import 'package:miditutor/midi/application/midi_device_discovery.dart';
import 'package:miditutor/midi/application/midi_event_stream.dart';
import 'package:miditutor/midi/domain/midi_connection_error.dart';
import 'package:miditutor/midi/domain/midi_connection_session.dart';
import 'package:miditutor/midi/domain/midi_connection_state.dart';
import 'package:miditutor/midi/domain/midi_source_info.dart';
import 'package:miditutor/midi/domain/raw_midi_event.dart';
import 'package:miditutor/practice/application/in_memory_lesson_progress_store.dart';
import 'package:miditutor/practice/domain/practice_clock.dart';

const kFakeSource = MidiSourceInfo(
  id: 'dev',
  name: 'APC Key 25',
  manufacturer: 'Akai',
);

class FakeDiscovery implements MidiDeviceDiscovery {
  FakeDiscovery([this.sources = const <MidiSourceInfo>[kFakeSource]]);

  List<MidiSourceInfo> sources;

  @override
  Future<List<MidiSourceInfo>> listSources() async => sources;
}

class FakeConnection implements MidiDeviceConnection {
  FakeConnection();

  MidiConnectionSession? session;
  MidiConnectionState _state = MidiConnectionState.notConnected;

  /// When set, [connect] fails with this error instead of connecting.
  MidiConnectionException? connectError;

  /// Simulates a shared connection that is already active before Practice opens.
  void preconnect(MidiConnectionSession activeSession) {
    session = activeSession;
    _state = MidiConnectionState.connected;
  }

  @override
  MidiConnectionState get state => _state;

  @override
  MidiConnectionSession? get currentSession => session;

  @override
  Future<MidiConnectionSession> connect(MidiSourceInfo source) async {
    final error = connectError;
    if (error != null) {
      throw error;
    }
    if (_state == MidiConnectionState.connected && session != null) {
      throw const MidiConnectionException(
        MidiConnectionError.alreadyConnected,
        'A MIDI source is already connected.',
      );
    }
    session = MidiConnectionSession(
      sessionId: 'session-1',
      deviceId: source.id,
      connectionType: 'USB',
    );
    _state = MidiConnectionState.connected;
    return session!;
  }

  @override
  Future<void> disconnect() async {
    session = null;
    _state = MidiConnectionState.disconnected;
  }
}

class FakeMidiStream implements MidiEventStream {
  final StreamController<RawMidiEvent> _controller =
      StreamController<RawMidiEvent>.broadcast();

  @override
  Stream<RawMidiEvent> get events => _controller.stream;

  void pushNoteOn(int seq, int ts, int note) {
    _controller.add(RawMidiEvent(
      sessionId: 'session-1',
      deviceId: 'dev',
      connectionType: 'USB',
      seq: seq,
      appMonotonicTsMs: ts,
      messageType: RawMidiMessageType.noteOn,
      channel: 0,
      note: note,
      velocity: 90,
      rawBytes: <int>[0x90, note, 90],
    ));
  }

  void pushNoteOff(int seq, int ts, int note) {
    _controller.add(RawMidiEvent(
      sessionId: 'session-1',
      deviceId: 'dev',
      connectionType: 'USB',
      seq: seq,
      appMonotonicTsMs: ts,
      messageType: RawMidiMessageType.noteOff,
      channel: 0,
      note: note,
      velocity: 0,
      rawBytes: <int>[0x80, note, 0],
    ));
  }

  void pushPerfectCMajorBlock() {
    pushNoteOn(0, 1000, 60);
    pushNoteOn(1, 1000, 64);
    pushNoteOn(2, 1000, 67);
    pushNoteOff(3, 1060, 60);
    pushNoteOff(4, 1060, 64);
    pushNoteOff(5, 1060, 67);
  }
}

class FakeClock implements PracticeClock {
  DateTime current;
  FakeClock(this.current);

  @override
  DateTime now() => current;
}

class FakeProgressStore extends InMemoryLessonProgressStore {
  FakeProgressStore();
}