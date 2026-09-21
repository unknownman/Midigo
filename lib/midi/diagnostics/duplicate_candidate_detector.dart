import '../domain/normalized_midi_event.dart';

/// A pair of same-type events flagged by the duplicate-candidate signature.
///
/// This is a diagnostic candidate only - the events are preserved.
final class DuplicateCandidate {
  final NormalizedMidiEvent first;
  final NormalizedMidiEvent second;

  /// `second.sourceAppMonotonicTsMs - first.sourceAppMonotonicTsMs`.
  final int deltaMs;

  const DuplicateCandidate({
    required this.first,
    required this.second,
    required this.deltaMs,
  });
}

/// Detects duplicate candidates using the existing draft signature:
///
/// ```text
/// same pitch
/// same channel
/// delta < threshold (default 5 ms)
/// ```
///
/// Applied in capture sequence order to consecutive Note-On/Note-Off events
/// that share `(sessionId, channel, pitch, normalized type)`. Candidates are
/// reported as diagnostics; events are NEVER deleted or merged.
///
/// The threshold is a configurable diagnostic parameter and is NOT validated
/// as universal hardware truth.
final class DuplicateCandidateDetector {
  final int thresholdMs;

  const DuplicateCandidateDetector({this.thresholdMs = 5});

  List<DuplicateCandidate> detect(Iterable<NormalizedMidiEvent> events) {
    final candidates = <DuplicateCandidate>[];
    final lastSeen = <(String, int?, int?, NormalizedMidiMessageType), NormalizedMidiEvent>{};

    for (final event in events) {
      final key = (
        event.sessionId,
        event.channel,
        event.pitch,
        event.type,
      );
      final previous = lastSeen[key];
      if (previous != null) {
        final delta = event.sourceAppMonotonicTsMs - previous.sourceAppMonotonicTsMs;
        if (delta >= 0 && delta < thresholdMs) {
          candidates.add(
            DuplicateCandidate(
              first: previous,
              second: event,
              deltaMs: delta,
            ),
          );
        }
      }
      lastSeen[key] = event;
    }

    return List<DuplicateCandidate>.unmodifiable(candidates);
  }
}