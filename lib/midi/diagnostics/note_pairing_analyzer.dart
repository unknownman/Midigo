import 'dart:math' as math;

import '../domain/normalized_midi_event.dart';

/// Identity used to pair Note-On and Note-Off events.
///
/// `(sessionId, channel, pitch)` — events from different sessions are never
/// paired (H2 session boundary rule).
typedef NoteIdentity = (String sessionId, int channel, int pitch);

/// A successfully paired Note-On / Note-Off instance.
///
/// Deterministic pairing follows FIFO within one identity: the earliest
/// active Note-On consumes the first matching Note-Off. A negative
/// [durationMs] is retained verbatim as an integrity anomaly - it is never
/// clamped or repaired.
final class NotePair {
  final NormalizedMidiEvent noteOn;
  final NormalizedMidiEvent noteOff;

  const NotePair({
    required this.noteOn,
    required this.noteOff,
  });

  int get durationMs =>
      noteOff.sourceAppMonotonicTsMs - noteOn.sourceAppMonotonicTsMs;

  String get sessionId => noteOn.sessionId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotePair && other.noteOn == noteOn && other.noteOff == noteOff;

  @override
  int get hashCode => Object.hash(noteOn, noteOff);
}

/// Reflects up to four classifications for one repeated note identity:
/// matched pairs, active instances, unmatched note-offs, and durations.
final class NotePairingReport {
  /// Note-Off events that had no matching active Note-On.
  final List<NormalizedMidiEvent> unmatchedNoteOffs;

  /// Note-On events still active (no matching Note-Off) at end of input.
  final List<NormalizedMidiEvent> activeNoteOns;

  /// Per identity, the maximum number of simultaneously active instances.
  final Map<NoteIdentity, int> maxActivePerIdentity;

  /// Per identity, the number of completed Note-On -> Note-Off cycles.
  final Map<NoteIdentity, int> matchedPairsPerIdentity;

  /// Successfully paired instances (FIFO within identity), in pairing order.
  final List<NotePair> pairs;

  int get matchedPairCount =>
      matchedPairsPerIdentity.values.fold<int>(0, (a, b) => a + b);

  int get unmatchedNoteOffCount => unmatchedNoteOffs.length;

  int get activeNoteOnCount => activeNoteOns.length;

  const NotePairingReport({
    required this.unmatchedNoteOffs,
    required this.activeNoteOns,
    required this.maxActivePerIdentity,
    required this.matchedPairsPerIdentity,
    required this.pairs,
  });
}

/// Deterministic Note-On/Note-Off pairing diagnostic over normalized events.
///
/// Matching identity is `(sessionId, channel, pitch)`. Overlapping repeats of
/// the same pitch/channel are tracked as multiple independent active
/// instances rather than collapsed to a boolean. Unmatched events (unmatched
/// Note-Offs and still-active Note-Ons) are reported, never silently repaired.
///
/// This is a diagnostic only; no musical semantics or sustain behavior.
final class NotePairingAnalyzer {
  const NotePairingAnalyzer();

  NotePairingReport analyze(Iterable<NormalizedMidiEvent> events) {
    final unmatchedOffs = <NormalizedMidiEvent>[];
    final active = <NoteIdentity, List<NormalizedMidiEvent>>{};
    final maxActive = <NoteIdentity, int>{};
    final matched = <NoteIdentity, int>{};
    final pairs = <NotePair>[];

    for (final event in events) {
      final channel = event.channel;
      final pitch = event.pitch;
      if (channel == null || pitch == null) {
        continue;
      }
      final identity = (event.sessionId, channel, pitch);

      switch (event.type) {
        case NormalizedMidiMessageType.noteOn:
          final instances = active.putIfAbsent(identity, () => <NormalizedMidiEvent>[]);
          instances.add(event);
          maxActive[identity] = math.max(maxActive[identity] ?? 0, instances.length);
        case NormalizedMidiMessageType.noteOff:
          final instances = active[identity];
          if (instances == null || instances.isEmpty) {
            unmatchedOffs.add(event);
          } else {
            final noteOn = instances.removeAt(0);
            if (instances.isEmpty) {
              active.remove(identity);
            }
            pairs.add(NotePair(noteOn: noteOn, noteOff: event));
            matched[identity] = (matched[identity] ?? 0) + 1;
          }
        case NormalizedMidiMessageType.other:
          break;
      }
    }

    final remaining = <NormalizedMidiEvent>[];
    for (final instances in active.values) {
      remaining.addAll(instances);
    }
    remaining.sort((a, b) => a.sourceSeq.compareTo(b.sourceSeq));

    return NotePairingReport(
      unmatchedNoteOffs: List<NormalizedMidiEvent>.unmodifiable(unmatchedOffs),
      activeNoteOns: List<NormalizedMidiEvent>.unmodifiable(remaining),
      maxActivePerIdentity: Map<NoteIdentity, int>.unmodifiable(maxActive),
      matchedPairsPerIdentity: Map<NoteIdentity, int>.unmodifiable(matched),
      pairs: List<NotePair>.unmodifiable(pairs),
    );
  }
}