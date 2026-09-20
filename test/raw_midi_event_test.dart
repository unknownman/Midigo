import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/midi/domain/raw_midi_event.dart';

Map<String, Object?> noteOnEvent({
  int? seq,
  String? sessionId,
  String? deviceId,
  int? velocity,
  int? note,
  int? channel,
  List<int>? rawBytes,
}) {
  return <String, Object?>{
    'sessionId': sessionId ?? 'abc',
    'deviceId': deviceId ?? '123456',
    'connectionType': 'USB',
    'seq': seq ?? 1,
    'appMonotonicTsMs': 1000,
    'messageType': 'note_on',
    'channel': channel ?? 0,
    'note': note ?? 60,
    'velocity': velocity ?? 83,
    'rawBytes': rawBytes ?? <int>[0x90, 60, 83],
  };
}

void main() {
  test('maps a valid raw Note-On event', () {
    final event = RawMidiEvent.fromPlatformMap(noteOnEvent());

    expect(event.messageType, RawMidiMessageType.noteOn);
    expect(event.channel, 0);
    expect(event.note, 60);
    expect(event.velocity, 83);
  });

  test('maps a valid raw Note-Off event', () {
    final event = RawMidiEvent.fromPlatformMap({
      ...noteOnEvent(),
      'messageType': 'note_off',
      'note': 60,
      'velocity': 0,
      'rawBytes': <int>[0x80, 60, 0],
    });

    expect(event.messageType, RawMidiMessageType.noteOff);
    expect(event.note, 60);
    expect(event.velocity, 0);
  });

  test('Note-On velocity=0 remains note_on (no normalization)', () {
    final event = RawMidiEvent.fromPlatformMap(noteOnEvent(velocity: 0));

    expect(event.messageType, RawMidiMessageType.noteOn);
    expect(event.velocity, 0);
  });

  test('raw bytes are preserved exactly', () {
    final event = RawMidiEvent.fromPlatformMap(
        noteOnEvent(rawBytes: <int>[0x90, 60, 127]));

    expect(event.rawBytes, <int>[0x90, 60, 127]);
  });

  test('raw bytes are defensively copied on construction', () {
    final source = <int>[0x90, 60, 83];
    final event = RawMidiEvent.fromPlatformMap(noteOnEvent(rawBytes: source));

    source.add(0xFF);
    expect(event.rawBytes, <int>[0x90, 60, 83]);
  });

  test('raw bytes getter exposes an unmodifiable list', () {
    final event = RawMidiEvent.fromPlatformMap(noteOnEvent());

    expect(() => event.rawBytes.add(0xFF), throwsUnsupportedError);
    expect(() => event.rawBytes.clear(), throwsUnsupportedError);
  });

  test('sequence number is preserved', () {
    final event = RawMidiEvent.fromPlatformMap(noteOnEvent(seq: 42));

    expect(event.seq, 42);
  });

  test('session id is preserved', () {
    final event =
        RawMidiEvent.fromPlatformMap(noteOnEvent(sessionId: 'session-xyz'));

    expect(event.sessionId, 'session-xyz');
  });

  test('device id is preserved', () {
    final event =
        RawMidiEvent.fromPlatformMap(noteOnEvent(deviceId: '802739987'));

    expect(event.deviceId, '802739987');
  });

  test('connection type is USB from the platform payload', () {
    final event = RawMidiEvent.fromPlatformMap(noteOnEvent());

    expect(event.connectionType, 'USB');
  });

  test('connection type defaults to USB when absent', () {
    final map = noteOnEvent()..remove('connectionType');
    final event = RawMidiEvent.fromPlatformMap(map);

    expect(event.connectionType, 'USB');
  });

  test('rejects a malformed platform event (missing seq)', () {
    final map = noteOnEvent()..remove('seq');

    expect(() => RawMidiEvent.fromPlatformMap(map), throwsFormatException);
  });

  test('rejects a non-map platform event', () {
    expect(() => RawMidiEvent.fromPlatformMap('not-a-map'),
        throwsFormatException);
  });

  test('accepts a nullable channel/note/velocity', () {
    final event = RawMidiEvent.fromPlatformMap({
      'sessionId': 'abc',
      'deviceId': '123456',
      'seq': 1,
      'appMonotonicTsMs': 1000,
      'messageType': 'other',
      'rawBytes': <int>[0xF8],
    });

    expect(event.messageType, RawMidiMessageType.other);
    expect(event.channel, isNull);
    expect(event.note, isNull);
    expect(event.velocity, isNull);
  });

  test('maps an unrecognized message type to other', () {
    final event = RawMidiEvent.fromPlatformMap({
      ...noteOnEvent(),
      'messageType': 'program_change',
    });

    expect(event.messageType, RawMidiMessageType.other);
  });

  test('constructor takes an unmodifiable defensive copy of rawBytes', () {
    final source = <int>[0x90, 60, 83];
    final event = RawMidiEvent(
      sessionId: 'abc',
      deviceId: '123456',
      connectionType: 'USB',
      seq: 1,
      appMonotonicTsMs: 1000,
      messageType: RawMidiMessageType.noteOn,
      channel: 0,
      note: 60,
      velocity: 83,
      rawBytes: source,
    );

    source.add(0xFF);
    expect(event.rawBytes, <int>[0x90, 60, 83]);
  });
}