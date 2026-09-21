import 'dart:collection';

import '../diagnostics/monotonicity_analyzer.dart';
import '../diagnostics/note_pairing_analyzer.dart';
import '../domain/musical_event.dart';
import '../domain/normalized_midi_event.dart';

/// Responsibilities of this component.
///
/// H2.4 is the fourth step of the locked pipeline:
///
/// ```text
/// Raw MIDI
///   -> Normalized MIDI (H2.1)
///   -> Diagnostic Analysis (H2.2)
///   -> Semantic Interpretation (H2.4, this class)
///   -> Evaluation (later)
/// ```
///
/// The interpreter answers "what musical event did the normalized stream
/// contain?" and never "was the user correct?". It performs no correctness
/// scoring, no chord/arpeggio labelling, no repair, no deletion, and never
/// mutates its inputs.
///
/// Pairing is NOT reimplemented: the frozen H2.1 [NotePairingAnalyzer] is
/// reused as-is (FIFO within `(sessionId, channel, pitch)` identity). Stream
/// anomalies reuse the frozen H2.2 [MonotonicityAnalyzer]; anomaly events are
/// surfaced, never normalized away. The 60 ms simultaneity value from H2.2 is
/// deliberately not referenced here and never becomes a correctness threshold.
final class MusicalEventInterpreter {
  const MusicalEventInterpreter();

  /// Interprets [input] into a deterministic [MusicalEvent] stream:
  ///
  /// * one event per matched pair (a `noteLifecycle` placed at the Note-On
  ///   position),
  /// * unmatched Note-Ons as `noteAttack`,
  /// * unmatched Note-Offs as `noteRelease`,
  /// * normalized `other` as `nonNote`,
  /// * observed regressions / duplicate sequence numbers as
  ///   `integrityAnomaly` events placed immediately before their source event.
  ///
  /// Sessions are hard boundaries: they never pair across each other, never
  /// produce cross-session lifecycles, and are emitted in first-seen order
  /// with capture order preserved inside each session.
  List<MusicalEvent> interpret(Iterable<NormalizedMidiEvent> input) {
    final events = List<NormalizedMidiEvent>.unmodifiable(input);

    final sessionOrder = <String>[];
    final bySession = <String, List<NormalizedMidiEvent>>{};
    for (final event in events) {
      final List<NormalizedMidiEvent> sessionEvents;
      final existing = bySession[event.sessionId];
      if (existing != null) {
        sessionEvents = existing;
      } else {
        sessionOrder.add(event.sessionId);
        sessionEvents = <NormalizedMidiEvent>[];
        bySession[event.sessionId] = sessionEvents;
      }
      sessionEvents.add(event);
    }

    // Reuse H2.1 pairing (FIFO within identity) verbatim.
    final pairing = const NotePairingAnalyzer().analyze(events);
    final pairByOn = LinkedHashMap<NormalizedMidiEvent, NotePair>.identity();
    final pairedOffs = LinkedHashSet<NormalizedMidiEvent>.identity();
    for (final pair in pairing.pairs) {
      pairByOn[pair.noteOn] = pair;
      pairedOffs.add(pair.noteOff);
    }

    final output = <MusicalEvent>[];
    var eventIndex = 0;
    for (final session in sessionOrder) {
      final sessionEvents = bySession[session]!;

      // Reuse H2.2 monotonicity analysis per session for anomaly provenance.
      final monotonic = const MonotonicityAnalyzer().analyze(sessionEvents);
      final seqRegressions = LinkedHashSet<NormalizedMidiEvent>.identity()
        ..addAll(monotonic.sequenceRegressions);
      final tsRegressions = LinkedHashSet<NormalizedMidiEvent>.identity()
        ..addAll(monotonic.timestampRegressions);

      // Positioning-only scan mirroring MonotonicityAnalyzer's duplicate rule
      // so each duplicate sequence occurrence can anchor its anomaly event.
      final seenSequenceNumbers = <int>{};
      final duplicateOccurrences = LinkedHashSet<NormalizedMidiEvent>.identity();
      for (final event in sessionEvents) {
        if (!seenSequenceNumbers.add(event.sourceSeq)) {
          duplicateOccurrences.add(event);
        }
      }

      for (final event in sessionEvents) {
        if (seqRegressions.contains(event)) {
          output.add(_anomaly(eventIndex++, session, event, 'sequence_regression'));
        }
        if (tsRegressions.contains(event)) {
          output.add(_anomaly(eventIndex++, session, event, 'timestamp_regression'));
        }
        if (duplicateOccurrences.contains(event)) {
          output.add(_anomaly(eventIndex++, session, event, 'duplicate_sequence'));
        }

        final pair = pairByOn[event];
        if (pair != null) {
          output.add(MusicalEvent(
            eventIndex: eventIndex++,
            sessionId: session,
            type: MusicalSemanticType.noteLifecycle,
            startTimestampMs: pair.noteOn.sourceAppMonotonicTsMs,
            endTimestampMs: pair.noteOff.sourceAppMonotonicTsMs,
            channel: pair.noteOn.channel,
            pitch: pair.noteOn.pitch,
            velocity: pair.noteOn.velocity,
            durationMs: pair.durationMs,
            sources: <NormalizedMidiEvent>[pair.noteOn, pair.noteOff],
          ));
        } else if (pairedOffs.contains(event)) {
          // Release already folded into its lifecycle; no second event.
          continue;
        } else {
          output.add(MusicalEvent(
            eventIndex: eventIndex++,
            sessionId: session,
            type: _semanticTypeOf(event),
            startTimestampMs: event.sourceAppMonotonicTsMs,
            channel: event.channel,
            pitch: event.pitch,
            velocity: event.velocity,
            sources: <NormalizedMidiEvent>[event],
          ));
        }
      }
    }

    return List<MusicalEvent>.unmodifiable(output);
  }

  static MusicalSemanticType _semanticTypeOf(NormalizedMidiEvent event) =>
      switch (event.type) {
        NormalizedMidiMessageType.noteOn => MusicalSemanticType.noteAttack,
        NormalizedMidiMessageType.noteOff => MusicalSemanticType.noteRelease,
        NormalizedMidiMessageType.other => MusicalSemanticType.nonNote,
      };

  /// Preserves the anomaly instead of repairing it. The offending event is
  /// carried as [MusicalEvent.sources] for full provenance.
  static MusicalEvent _anomaly(
          int eventIndex, String sessionId, NormalizedMidiEvent source, String category) =>
      MusicalEvent(
        eventIndex: eventIndex,
        sessionId: sessionId,
        type: MusicalSemanticType.integrityAnomaly,
        startTimestampMs: source.sourceAppMonotonicTsMs,
        channel: source.channel,
        pitch: source.pitch,
        velocity: source.velocity,
        anomalyCategory: category,
        sources: <NormalizedMidiEvent>[source],
      );
}