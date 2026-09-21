import 'dart:math' as math;

import '../domain/normalized_midi_event.dart';

/// Identity used to pair Note-On and Note-Off events.
///
/// `(sessionId, channel, pitch)` — events from different sessions are never
/// paired (H2 session boundary rule).
typedef NoteIdentity = (String sessionId, int channel, int pitch);

/// Reflects up to three classifications for one repeated note identity:
/// matched pair count, active instances, and unmatched note-offs.
final class NotePairingReport {
  /// Note-Off events that had no matching active Note-On.
  final List<NormalizedMidiEvent> unmatchedNoteOffs;

  /// Note-On events still active (no matching Note-Off) at end of input.
  final List<NormalizedMidiEvent> activeNoteOns;

  /// Per identity, the maximum number of simultaneously active instances.
  final Map<NoteIdentity, int> maxActivePerIdentity;

  /// Per identity, the number of completed Note-On -> Note-Off cycles.
  final Map<NoteIdentity, int> matchedPairsPerIdentity;

  int get matchedPairCount =>
      matchedPairsPerIdentity.values.fold<int>(0, (a, b) => a + b);

  int get unmatchedNoteOffCount => unmatchedNoteOffs.length;

  int get activeNoteOnCount => activeNoteOns.length;

  const NotePairingReport({
    required this.unmatchedNoteOffs,
    required this.activeNoteOns,
    required this.maxActivePerIdentity,
    required this.matchedPairsPerIdentity,
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
            instances.removeAt(0);
            if (instances.isEmpty) {
              active.remove(identity);
            }
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
    );
  }
}