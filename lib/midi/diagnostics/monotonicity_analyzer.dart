import '../domain/normalized_midi_event.dart';

/// Deterministic monotonicity diagnostics over an ordered set of events.
///
/// Sequence order is the authoritative capture ordering. This component
/// reports anomalies without repairing them.
final class MonotonicityReport {
  /// Events whose source sequence regressed below the previous event's.
  final List<NormalizedMidiEvent> sequenceRegressions;

  /// Events whose source timestamp regressed below the previous event's.
  final List<NormalizedMidiEvent> timestampRegressions;

  /// Sequence numbers that appear more than once.
  final Set<int> duplicateSequenceIds;

  int get sequenceRegressionCount => sequenceRegressions.length;

  int get timestampRegressionCount => timestampRegressions.length;

  const MonotonicityReport({
    required this.sequenceRegressions,
    required this.timestampRegressions,
    required this.duplicateSequenceIds,
  });
}

final class MonotonicityAnalyzer {
  const MonotonicityAnalyzer();

  MonotonicityReport analyze(Iterable<NormalizedMidiEvent> events) {
    final seqRegressions = <NormalizedMidiEvent>[];
    final tsRegressions = <NormalizedMidiEvent>[];
    final seen = <int>{};
    final duplicated = <int>{};
    NormalizedMidiEvent? previous;

    for (final event in events) {
      if (previous != null) {
        if (event.sourceSeq < previous.sourceSeq) {
          seqRegressions.add(event);
        }
        if (event.sourceAppMonotonicTsMs < previous.sourceAppMonotonicTsMs) {
          tsRegressions.add(event);
        }
      }
      if (!seen.add(event.sourceSeq)) {
        duplicated.add(event.sourceSeq);
      }
      previous = event;
    }

    return MonotonicityReport(
      sequenceRegressions: List<NormalizedMidiEvent>.unmodifiable(seqRegressions),
      timestampRegressions: List<NormalizedMidiEvent>.unmodifiable(tsRegressions),
      duplicateSequenceIds: Set<int>.unmodifiable(duplicated),
    );
  }
}