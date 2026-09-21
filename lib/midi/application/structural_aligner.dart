import '../domain/expected_musical_target.dart';
import '../domain/musical_event.dart';
import '../domain/structural_alignment.dart';

/// Deterministic structural alignment between one [ExpectedMusicalTarget] and
/// one observed [MusicalEvent] stream.
///
/// H2.6 sits directly below Evaluation:
///
/// ```text
/// ExpectedMusicalTarget
///         +
/// MusicalEvent stream
///         |
/// StructuralAlignment      <- H2.6 (this aligner)
///         |
/// Evaluation               <- later
/// ```
///
/// It performs NO correctness judgment. It never scores, grades, applies a
/// tolerance, repairs streams, infers musical intent, or classifies any element
/// as an error. It only states which observed note events are structurally
/// associated with which expected target events, and which elements on either
/// side remain unmatched.
///
/// The algorithm is deliberately the smallest deterministic one:
///
/// 1. Filter to the single requested [sessionId] (sessions never mix; events
///    from other sessions are surfaced as ignored references).
/// 2. Candidate pool: observed events of type [MusicalSemanticType.noteLifecycle]
///    or [MusicalSemanticType.noteAttack] carrying a concrete [MusicalEvent.pitch]
///    (an attack identity). Note releases (no attack identity) are excluded
///    from association; non-note and integrity-anomaly events are excluded from
///    association and surfaced as ignored references.
/// 3. For each expected note in ascending expected index, consume the earliest
///    eligible (lowest [MusicalEvent.eventIndex]) unconsumed candidate with an
///    exactly equal MIDI pitch. Exact numeric pitch identity is the only
///    association criterion - no enharmonic, octave, transposition, or pitch
///    tolerance.
/// 4. Expected notes with no available candidate stay unmatched; unconsumed
///    candidates are reported as unmatched observed elements.
///
/// One-to-one consumption is enforced: no observed event can be consumed twice
/// and no expected note silently consumes more than one observed event. The
/// observable order of the raw stream is preserved in every reference, so the
/// future Evaluation layer can still interpret ordering if a later contract
/// requires it; H2.6 never emits an ordering verdict.
final class StructuralAligner {
  const StructuralAligner();

  /// Deterministic algorithm version, emitted on every [StructuralAlignment].
  static const String algorithmVersion = '1';

  StructuralAlignment align({
    required ExpectedMusicalTarget target,
    required String sessionId,
    required List<MusicalEvent> observed,
  }) {
    final stream = List<MusicalEvent>.unmodifiable(observed);

    final noteCandidates = <MusicalEvent>[];
    final ignoredNonNote = <int>[];
    final ignoredAnomaly = <int>[];
    final ignoredOtherSession = <int>[];

    for (final event in stream) {
      if (event.sessionId != sessionId) {
        ignoredOtherSession.add(event.eventIndex);
        continue;
      }
      switch (event.type) {
        case MusicalSemanticType.noteLifecycle:
        case MusicalSemanticType.noteAttack:
          // An attack/lifecycle without a concrete pitch cannot be structurally
          // associated; it is excluded from the candidate pool.
          if (event.pitch != null) {
            noteCandidates.add(event);
          }
        case MusicalSemanticType.noteRelease:
          // A release has no attack identity and can never form an association.
          // It is preserved in the original stream and documented as excluded.
          continue;
        case MusicalSemanticType.nonNote:
          ignoredNonNote.add(event.eventIndex);
        case MusicalSemanticType.integrityAnomaly:
          // Surface but never repair: the anomaly reference is preserved as an
          // ignored reference instead of becoming a note association.
          ignoredAnomaly.add(event.eventIndex);
      }
    }

    noteCandidates.sort((a, b) => a.eventIndex.compareTo(b.eventIndex));

    final consumedObservedEventIndices = <int>{};
    final expectedGroupIndexByNoteIndex = _expectedGroupIndexByNoteIndex(target);

    final matches = <AlignmentMatch>[];
    final unmatchedExpected = <UnmatchedExpectedElement>[];

    for (final expected in target.notes) {
      AlignmentMatch? chosen;
      for (final candidate in noteCandidates) {
        if (consumedObservedEventIndices.contains(candidate.eventIndex)) {
          continue;
        }
        if (candidate.pitch != expected.pitch) {
          continue;
        }
        final groupIndex = expectedGroupIndexByNoteIndex[expected.index];
        chosen = AlignmentMatch(
          expectedNoteIndex: expected.index,
          expectedPitch: expected.pitch,
          expectedGroupIndex: groupIndex,
          expectedOnsetOffsetMs:
              groupIndex == null ? null : _groupExpectedOnsetOffsetMs(target, groupIndex),
          observedEventIndex: candidate.eventIndex,
          observedPitch: candidate.pitch!,
          observedChannel: candidate.channel,
          observedOnsetTimestampMs: candidate.startTimestampMs,
          observedEndTimestampMs: candidate.endTimestampMs,
          observedType: candidate.type,
        );
        consumedObservedEventIndices.add(candidate.eventIndex);
        break;
      }

      if (chosen == null) {
        final groupIndex = expectedGroupIndexByNoteIndex[expected.index];
        unmatchedExpected.add(UnmatchedExpectedElement(
          expectedNoteIndex: expected.index,
          expectedPitch: expected.pitch,
          expectedGroupIndex: groupIndex,
          expectedOnsetOffsetMs:
              groupIndex == null ? null : _groupExpectedOnsetOffsetMs(target, groupIndex),
        ));
      } else {
        matches.add(chosen);
      }
    }

    final unmatchedObserved = <UnmatchedObservedElement>[
      for (final candidate in noteCandidates)
        if (!consumedObservedEventIndices.contains(candidate.eventIndex))
          UnmatchedObservedElement(
            observedEventIndex: candidate.eventIndex,
            observedPitch: candidate.pitch!,
            observedChannel: candidate.channel,
            observedOnsetTimestampMs: candidate.startTimestampMs,
            observedEndTimestampMs: candidate.endTimestampMs,
            observedType: candidate.type,
          ),
    ];

    return StructuralAlignment(
      targetId: target.targetId,
      sessionId: sessionId,
      mode: target.mode,
      algorithmVersion: algorithmVersion,
      matches: matches,
      unmatchedExpected: unmatchedExpected,
      unmatchedObserved: unmatchedObserved,
      ignoredNonNoteEventRefs: ignoredNonNote,
      ignoredIntegrityAnomalyEventRefs: ignoredAnomaly,
      ignoredOtherSessionEventRefs: ignoredOtherSession,
    );
  }

  /// Maps an expected note index to its onset group index. Uses the first group
  /// (ascending group index) whose members contain the note; null when the
  /// target places the note in no group.
  static Map<int, int> _expectedGroupIndexByNoteIndex(ExpectedMusicalTarget target) {
    final byNote = <int, int>{};
    for (final group in target.onsetGroups) {
      for (final member in group.memberEventIndices) {
        byNote.putIfAbsent(member, () => group.index);
      }
    }
    return byNote;
  }

  static int? _groupExpectedOnsetOffsetMs(
          ExpectedMusicalTarget target, int groupIndex) =>
      target.onsetGroups
          .where((g) => g.index == groupIndex)
          .map((g) => g.expectedOnsetOffsetMs)
          .firstOrNull;
}

/// First element of a lazy iterable, or null when empty.
extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}