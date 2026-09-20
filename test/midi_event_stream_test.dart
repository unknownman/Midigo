import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/midi/application/midi_event_stream.dart';
import 'package:miditutor/midi/domain/raw_midi_event.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = EventChannel('piano_midi/macos/events');

  Map<String, Object?> platformEvent({
    int seq = 1,
    String sessionId = 'abc',
    String messageType = 'note_on',
    int? channel = 0,
    int? note = 60,
    int? velocity = 83,
  }) {
    return <String, Object?>{
      'sessionId': sessionId,
      'deviceId': '123456',
      'connectionType': 'USB',
      'seq': seq,
      'appMonotonicTsMs': 1000,
      'messageType': messageType,
      'channel': channel,
      'note': note,
      'velocity': velocity,
      'rawBytes': <int>[0x90, 60, 83],
    };
  }

  void setMock(MockStreamHandler? handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(channel, handler);
  }

  setUp(() {
    setMock(null);
  });

  test('stream delivers valid events in platform order', () async {
    MockStreamHandlerEventSink? sink;
    setMock(MockStreamHandler.inline(
      onListen: (arguments, events) { sink = events; },
      onCancel: (arguments) {},
    ));

    final received = <RawMidiEvent>[];
    final subscription = MacosMidiEventStream().events.listen(received.add);
    await Future<void>.delayed(Duration.zero);

    sink!.success(platformEvent(seq: 1, messageType: 'note_on'));
    sink!.success(platformEvent(seq: 2, messageType: 'note_off', note: 60, velocity: 0));
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(2));
    expect(received[0].messageType, RawMidiMessageType.noteOn);
    expect(received[1].messageType, RawMidiMessageType.noteOff);

    await subscription.cancel();
  });

  test('stream preserves Note-On with velocity 0 as note_on', () async {
    MockStreamHandlerEventSink? sink;
    setMock(MockStreamHandler.inline(
      onListen: (arguments, events) { sink = events; },
      onCancel: (arguments) {},
    ));

    final received = <RawMidiEvent>[];
    final subscription = MacosMidiEventStream().events.listen(received.add);
    await Future<void>.delayed(Duration.zero);

    sink!.success(platformEvent(seq: 5, velocity: 0));
    await Future<void>.delayed(Duration.zero);

    expect(received.single.messageType, RawMidiMessageType.noteOn);
    expect(received.single.velocity, 0);

    await subscription.cancel();
  });

  test('stream drops a malformed event without terminating capture', () async {
    MockStreamHandlerEventSink? sink;
    setMock(MockStreamHandler.inline(
      onListen: (arguments, events) { sink = events; },
      onCancel: (arguments) {},
    ));

    final received = <RawMidiEvent>[];
    final subscription = MacosMidiEventStream().events.listen(received.add);
    await Future<void>.delayed(Duration.zero);

    sink!.success(<String, Object?>{'broken': true});
    await Future<void>.delayed(Duration.zero);
    expect(received, isEmpty);

    sink!.success(platformEvent(seq: 1));
    await Future<void>.delayed(Duration.zero);
    expect(received, hasLength(1));

    await subscription.cancel();
  });

  test('stream subscription can be cancelled safely', () async {
    MockStreamHandlerEventSink? sink;
    var cancelled = false;
    setMock(MockStreamHandler.inline(
      onListen: (arguments, events) { sink = events; },
      onCancel: (arguments) => cancelled = true,
    ));

    final subscription = MacosMidiEventStream().events.listen((_) {});
    await Future<void>.delayed(Duration.zero);
    sink!.success(platformEvent(seq: 1));

    await subscription.cancel();
    expect(cancelled, isTrue);
  });

  test('multiple stream sources are independent streams', () async {
    final stream = MacosMidiEventStream();
    final first = stream.events;
    final second = stream.events;

    expect(identical(first, second), isFalse);
  });
}