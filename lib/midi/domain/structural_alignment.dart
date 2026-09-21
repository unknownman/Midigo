import 'expected_musical_target.dart';
import 'musical_event.dart';

/// One deterministic structural association between an expected target note and
/// an observed semantic note.
///
/// H2.6 only answers "these two elements were associated by the alignment
/// algorithm"; it never states whether the performance was correct. Therefore
/// an association carries NO correctness verdict, score, tolerance, or error
/// classification - exactly the fields the future Evaluation layer adds later.
///
/// Both sides are referenced deterministically:
///
/// * the expected side by its index into [ExpectedMusicalTarget.notes] with its
///   pitch, plus the enclosing [ExpectedOnsetGroup] index and its expected
///   onset offset when the target prescribes one,
/// * the observed side by its index into the original [MusicalEvent] stream
///   with its pitch, onset/release timestamps, and semantic type.
///
/// Provenance is index-based (stable references), never object identity.
final class AlignmentMatch {
  /// Index into [ExpectedMusicalTarget.notes] of the associated expected note.
  final int expectedNoteIndex;

  final int expectedPitch;

  /// Index of the [ExpectedOnsetGroup] whose members contain the expected
  /// note; null when the target does not place that note in any group.
  final int? expectedGroupIndex;

  /// Expected absolute onset offset from the matching group; null when the
  /// group prescribes no timing. Carries no tolerance.
  final int? expectedOnsetOffsetMs;

  /// Index into the original observed [MusicalEvent] stream.
  final int observedEventIndex;

  final int observedPitch;
  final int? observedChannel;

  final int observedOnsetTimestampMs;

  /// Observed release timestamp; null when no release was observed.
  final int? observedEndTimestampMs;

  /// The observed semantic type ([MusicalSemanticType.noteLifecycle] or
  /// [MusicalSemanticType.noteAttack] - an attack identity is always required).
  final MusicalSemanticType observedType;

  AlignmentMatch({
    required this.expectedNoteIndex,
    required this.expectedPitch,
    required this.expectedGroupIndex,
    required this.expectedOnsetOffsetMs,
    required this.observedEventIndex,
    required this.observedPitch,
    required this.observedChannel,
    required this.observedOnsetTimestampMs,
    required this.observedEndTimestampMs,
    required this.observedType,
  }) {
    if (expectedNoteIndex < 0) {
      throw const FormatException('AlignmentMatch: expectedNoteIndex must be >= 0.');
    }
    if (expectedPitch < 0 || expectedPitch > 127) {
      throw const FormatException('AlignmentMatch: expectedPitch must be in 0..127.');
    }
    if (observedEventIndex < 0) {
      throw const FormatException('AlignmentMatch: observedEventIndex must be >= 0.');
    }
    if (observedPitch < 0 || observedPitch > 127) {
      throw const FormatException('AlignmentMatch: observedPitch must be in 0..127.');
    }
    if (observedOnsetTimestampMs < 0) {
      throw const FormatException(
          'AlignmentMatch: observedOnsetTimestampMs must be >= 0.');
    }
    if (observedType != MusicalSemanticType.noteLifecycle &&
        observedType != MusicalSemanticType.noteAttack) {
      throw const FormatException(
          'AlignmentMatch: an association requires an attack/lifecycle '
          'identity.');
    }
  }

  @override
  String toString() =>
      'AlignmentMatch(expected #$expectedNoteIndex pitch=$expectedPitch'
      '${expectedGroupIndex == null ? '' : ' group=$expectedGroupIndex'}'
      ' <-> observed #$observedEventIndex pitch=$observedPitch'
      ' @ $observedOnsetTimestampMs ms $observedType)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlignmentMatch &&
          other.expectedNoteIndex == expectedNoteIndex &&
          other.expectedPitch == expectedPitch &&
          other.expectedGroupIndex == expectedGroupIndex &&
          other.expectedOnsetOffsetMs == expectedOnsetOffsetMs &&
          other.observedEventIndex == observedEventIndex &&
          other.observedPitch == observedPitch &&
          other.observedChannel == observedChannel &&
          other.observedOnsetTimestampMs == observedOnsetTimestampMs &&
          other.observedEndTimestampMs == observedEndTimestampMs &&
          other.observedType == observedType;

  @override
  int get hashCode => Object.hash(expectedNoteIndex, expectedPitch,
      expectedGroupIndex, expectedOnsetOffsetMs, observedEventIndex,
      observedPitch, observedChannel, observedOnsetTimestampMs,
      observedEndTimestampMs, observedType);

  Map<String, Object?> toMap() => <String, Object?>{
        'expected_note_index': expectedNoteIndex,
        'expected_pitch': expectedPitch,
        'expected_group_index': expectedGroupIndex,
        'expected_onset_offset_ms': expectedOnsetOffsetMs,
        'observed_event_index': observedEventIndex,
        'observed_pitch': observedPitch,
        'observed_channel': observedChannel,
        'observed_onset_timestamp_ms': observedOnsetTimestampMs,
        'observed_end_timestamp_ms': observedEndTimestampMs,
        'observed_type': observedType.name,
      };
}

/// An expected target element that the alignment algorithm could not
/// structurally associate with any observed note.
///
/// A shared pitch, like the shared group metadata, is carried on the reference
/// so the alignment output is self-describing without requiring lookups into
/// the target. No correctness interpretation is attached.
final class UnmatchedExpectedElement {
  final int expectedNoteIndex;
  final int expectedPitch;
  final int? expectedGroupIndex;
  final int? expectedOnsetOffsetMs;

  UnmatchedExpectedElement({
    required this.expectedNoteIndex,
    required this.expectedPitch,
    required this.expectedGroupIndex,
    required this.expectedOnsetOffsetMs,
  }) {
    if (expectedNoteIndex < 0) {
      throw const FormatException(
          'UnmatchedExpectedElement: expectedNoteIndex must be >= 0.');
    }
    if (expectedPitch < 0 || expectedPitch > 127) {
      throw const FormatException(
          'UnmatchedExpectedElement: expectedPitch must be in 0..127.');
    }
  }

  @override
  String toString() =>
      'UnmatchedExpectedElement(#$expectedNoteIndex pitch=$expectedPitch'
      '${expectedGroupIndex == null ? '' : ' group=$expectedGroupIndex'})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnmatchedExpectedElement &&
          other.expectedNoteIndex == expectedNoteIndex &&
          other.expectedPitch == expectedPitch &&
          other.expectedGroupIndex == expectedGroupIndex &&
          other.expectedOnsetOffsetMs == expectedOnsetOffsetMs;

  @override
  int get hashCode => Object.hash(
      expectedNoteIndex, expectedPitch, expectedGroupIndex, expectedOnsetOffsetMs);

  Map<String, Object?> toMap() => <String, Object?>{
        'expected_note_index': expectedNoteIndex,
        'expected_pitch': expectedPitch,
        'expected_group_index': expectedGroupIndex,
        'expected_onset_offset_ms': expectedOnsetOffsetMs,
      };
}

/// An observed note event (lifecycle or attack) that the alignment algorithm
/// did not consume for any expected-note association.
///
/// Referenced deterministically by its index into the original [MusicalEvent]
/// stream. An unconsumed extra observed note is exposed as-is; it is not
/// classified as an error, and no musical meaning is invented for it.
final class UnmatchedObservedElement {
  final int observedEventIndex;
  final int observedPitch;
  final int? observedChannel;
  final int observedOnsetTimestampMs;
  final int? observedEndTimestampMs;
  final MusicalSemanticType observedType;

  UnmatchedObservedElement({
    required this.observedEventIndex,
    required this.observedPitch,
    required this.observedChannel,
    required this.observedOnsetTimestampMs,
    required this.observedEndTimestampMs,
    required this.observedType,
  }) {
    if (observedEventIndex < 0) {
      throw const FormatException(
          'UnmatchedObservedElement: observedEventIndex must be >= 0.');
    }
    if (observedPitch < 0 || observedPitch > 127) {
      throw const FormatException(
          'UnmatchedObservedElement: observedPitch must be in 0..127.');
    }
    if (observedOnsetTimestampMs < 0) {
      throw const FormatException(
          'UnmatchedObservedElement: observedOnsetTimestampMs must be >= 0.');
    }
    if (observedType != MusicalSemanticType.noteLifecycle &&
        observedType != MusicalSemanticType.noteAttack) {
      throw const FormatException(
          'UnmatchedObservedElement: only attack/lifecycle notes are '
          'eligible for association.');
    }
  }

  @override
  String toString() =>
      'UnmatchedObservedElement(#$observedEventIndex pitch=$observedPitch'
      ' @ $observedOnsetTimestampMs ms $observedType)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnmatchedObservedElement &&
          other.observedEventIndex == observedEventIndex &&
          other.observedPitch == observedPitch &&
          other.observedChannel == observedChannel &&
          other.observedOnsetTimestampMs == observedOnsetTimestampMs &&
          other.observedEndTimestampMs == observedEndTimestampMs &&
          other.observedType == observedType;

  @override
  int get hashCode => Object.hash(observedEventIndex, observedPitch,
      observedChannel, observedOnsetTimestampMs, observedEndTimestampMs, observedType);

  Map<String, Object?> toMap() => <String, Object?>{
        'observed_event_index': observedEventIndex,
        'observed_pitch': observedPitch,
        'observed_channel': observedChannel,
        'observed_onset_timestamp_ms': observedOnsetTimestampMs,
        'observed_end_timestamp_ms': observedEndTimestampMs,
        'observed_type': observedType.name,
      };
}

/// Immutable, deterministic structural alignment between one expected musical
/// target and one observed [MusicalEvent] stream from a single session.
///
/// H2.6 is the neutral intermediate representation between target and
/// evaluation:
///
/// ```text
/// ExpectedMusicalTarget
///         +
/// MusicalEvent stream
///         |
/// StructuralAlignment      <- this model (H2.6)
///         |
/// Evaluation               <- later
/// ```
///
/// It answers "which observed semantic notes can be structurally associated
/// with which expected target notes, and which elements on either side remain
/// unmatched". It deliberately contains NO correctness verdict, score,
/// tolerance, error vector, mastery, evidence, or scheduler information.
///
/// Every element list is deterministic and immutable. Associations are ordered
/// by expected note index; unmatched expected elements by expected note index;
/// unmatched observed elements and ignored references by observed event index.
final class StructuralAlignment {
  /// Identity reference of the aligned expected target.
  final String targetId;

  /// The single observed session this alignment was produced for.
  final String sessionId;

  /// Target mode, carried forward so downstream layers can interpret ordering
  /// semantics without re-deriving them.
  final TargetMode mode;

  /// Deterministic algorithm version that produced this alignment.
  final String algorithmVersion;

  /// One-to-one structural associations, in deterministic order.
  final List<AlignmentMatch> matches;

  /// Expected elements with no observed counterpart, in expected-index order.
  final List<UnmatchedExpectedElement> unmatchedExpected;

  /// Observed note events not consumed by any association, in event-index
  /// order. Never an error classification.
  final List<UnmatchedObservedElement> unmatchedObserved;

  /// Event indices of non-note events that were excluded from note matching.
  final List<int> ignoredNonNoteEventRefs;

  /// Event indices of integrity anomalies that were surfaced but excluded from
  /// note matching (never repaired, never turned into musical errors).
  final List<int> ignoredIntegrityAnomalyEventRefs;

  /// Event indices belonging to sessions other than [sessionId], excluded so no
  /// alignment ever spans sessions.
  final List<int> ignoredOtherSessionEventRefs;

  StructuralAlignment({
    required this.targetId,
    required this.sessionId,
    required this.mode,
    required this.algorithmVersion,
    required List<AlignmentMatch> matches,
    required List<UnmatchedExpectedElement> unmatchedExpected,
    required List<UnmatchedObservedElement> unmatchedObserved,
    required List<int> ignoredNonNoteEventRefs,
    required List<int> ignoredIntegrityAnomalyEventRefs,
    required List<int> ignoredOtherSessionEventRefs,
  })  : matches = List<AlignmentMatch>.unmodifiable(matches),
        unmatchedExpected = List<UnmatchedExpectedElement>.unmodifiable(unmatchedExpected),
        unmatchedObserved = List<UnmatchedObservedElement>.unmodifiable(unmatchedObserved),
        ignoredNonNoteEventRefs = List<int>.unmodifiable(ignoredNonNoteEventRefs),
        ignoredIntegrityAnomalyEventRefs =
            List<int>.unmodifiable(ignoredIntegrityAnomalyEventRefs),
        ignoredOtherSessionEventRefs =
            List<int>.unmodifiable(ignoredOtherSessionEventRefs);

  @override
  String toString() =>
      'StructuralAlignment(target=$targetId session=$sessionId mode=${mode.name} '
      'v$algorithmVersion: ${matches.length} matches, '
      '${unmatchedExpected.length} unmatched expected, '
      '${unmatchedObserved.length} unmatched observed)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StructuralAlignment &&
          other.targetId == targetId &&
          other.sessionId == sessionId &&
          other.mode == mode &&
          other.algorithmVersion == algorithmVersion &&
          _alignmentMatchesEq(other.matches, matches) &&
          _unmatchedExpectedEq(other.unmatchedExpected, unmatchedExpected) &&
          _unmatchedObservedEq(other.unmatchedObserved, unmatchedObserved) &&
          _intListEq(other.ignoredNonNoteEventRefs, ignoredNonNoteEventRefs) &&
          _intListEq(other.ignoredIntegrityAnomalyEventRefs,
              ignoredIntegrityAnomalyEventRefs) &&
          _intListEq(other.ignoredOtherSessionEventRefs, ignoredOtherSessionEventRefs);

  @override
  int get hashCode => Object.hash(targetId, sessionId, mode, algorithmVersion,
      Object.hashAll(matches), Object.hashAll(unmatchedExpected),
      Object.hashAll(unmatchedObserved), Object.hashAll(ignoredNonNoteEventRefs),
      Object.hashAll(ignoredIntegrityAnomalyEventRefs),
      Object.hashAll(ignoredOtherSessionEventRefs));

  Map<String, Object?> toMap() => <String, Object?>{
        'target_id': targetId,
        'session_id': sessionId,
        'mode': mode.name,
        'algorithm_version': algorithmVersion,
        'matches': matches.map((m) => m.toMap()).toList(growable: false),
        'unmatched_expected':
            unmatchedExpected.map((e) => e.toMap()).toList(growable: false),
        'unmatched_observed':
            unmatchedObserved.map((e) => e.toMap()).toList(growable: false),
        'ignored_non_note_event_refs': ignoredNonNoteEventRefs,
        'ignored_integrity_anomaly_event_refs': ignoredIntegrityAnomalyEventRefs,
        'ignored_other_session_event_refs': ignoredOtherSessionEventRefs,
      };
}

bool _alignmentMatchesEq(List<AlignmentMatch> a, List<AlignmentMatch> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

bool _unmatchedExpectedEq(
    List<UnmatchedExpectedElement> a, List<UnmatchedExpectedElement> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

bool _unmatchedObservedEq(
    List<UnmatchedObservedElement> a, List<UnmatchedObservedElement> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

bool _intListEq(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}