import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/raw_midi_event.dart';
import 'midi_event_stream.dart';
import 'raw_midi_event_buffer.dart';

/// Ties an active H1.2 session to a live raw MIDI capture.
///
/// On [start], the buffer is cleared (the explicit session lifecycle boundary)
/// and events are appended as they arrive. Events whose session id does not
/// match the session this capture was started for are dropped, so a late packet
/// from a previous session can never pollute the current capture.
final class MidiRawEventCapture {
  MidiRawEventCapture(this._stream);

  final MidiEventStream _stream;
  final RawMidiEventBuffer buffer = RawMidiEventBuffer();

  /// Bumped on every appended event so a [ValueListenableBuilder] can repaint
  /// the diagnostic display without exposing the mutable buffer.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  StreamSubscription<RawMidiEvent>? _subscription;
  bool _active = false;

  bool get isActive => _active;

  Future<void> start(String sessionId) async {
    await stop();
    buffer.clear();
    _active = true;
    _subscription = _stream.events.listen((event) {
      if (event.sessionId != sessionId) {
        return;
      }
      buffer.append(event);
      revision.value += 1;
    });
  }

  Future<void> stop() async {
    _active = false;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      await subscription.cancel();
    }
  }

  Future<void> dispose() async {
    await stop();
    revision.dispose();
  }
}