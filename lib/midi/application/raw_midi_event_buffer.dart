import 'package:flutter/foundation.dart';

import '../domain/raw_midi_event.dart';

/// Append-only in-memory capture buffer for raw MIDI events.
///
/// Events are only ever added or removed via [clear], which is expected to be
/// called at a session lifecycle boundary. Reads expose an unmodifiable copy,
/// so callers can never mutate captured event data or the buffer itself.
@immutable
final class RawMidiEventBuffer {
  final List<RawMidiEvent> _events = <RawMidiEvent>[];

  int get length => _events.length;

  bool get isEmpty => _events.isEmpty;

  List<RawMidiEvent> get events => List<RawMidiEvent>.unmodifiable(_events);

  RawMidiEvent operator [](int index) => _events[index];

  void append(RawMidiEvent event) {
    _events.add(event);
  }

  void appendAll(Iterable<RawMidiEvent> events) {
    _events.addAll(events);
  }

  void clear() {
    _events.clear();
  }
}