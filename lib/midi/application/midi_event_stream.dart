import 'package:flutter/services.dart';

import '../domain/raw_midi_event.dart';

abstract interface class MidiEventStream {
  Stream<RawMidiEvent> get events;
}

final class MacosMidiEventStream implements MidiEventStream {
  MacosMidiEventStream({EventChannel? channel})
      : _channel = channel ??
            const EventChannel('piano_midi/macos/events');

  final EventChannel _channel;

  /// Streams raw MIDI events from the platform event channel.
  ///
  /// Malformed platform payloads are dropped rather than terminating the
  /// stream, so a single corrupt packet cannot silently disable capture.
  @override
  Stream<RawMidiEvent> get events => _channel.receiveBroadcastStream()
      .expand((Object? event) {
        try {
          return <RawMidiEvent>[RawMidiEvent.fromPlatformMap(event)];
        } on FormatException {
          return const <RawMidiEvent>[];
        }
      });
}