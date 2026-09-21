import 'expected_musical_target.dart';
import 'musical_event.dart';

/// Availability of one evaluation dimension's observation set.
///
/// H2.7 only reports whether neutral facts exist; it never converts an
/// [unavailable] state into a failure.
enum ObservationAvailability {
  /// Sufficient source data exists and observations are exposed.
  available,

  /// The dimension applies to the target's structure but required data is
  /// absent (for example a performance anchor that no frozen model provides).
  unavailable,

  /// The target structure itself does not use this dimension (for example
  /// Order for a Block target).
  notApplicable;

  String get serialName => switch (this) {
        ObservationAvailability.available => 'AVAILABLE',
        ObservationAvailability.unavailable => 'UNAVAILABLE',
        ObservationAvailability.notApplicable => 'NOT_APPLICABLE',
      };
}

/// Structural association state of a pitch/timing element.
///
/// Purely structural vocabulary that reuses H2.6 semantics verbatim. These are
/// facts about association, never judgments about performance.
enum AssociationState {
  associated,
  expectedUnmatched,
  observedUnmatched;

  String get serialName => switch (this) {
        AssociationState.associated => 'ASSOCIATED',
        AssociationState.expectedUnmatched => 'EXPECTED_UNMATCHED',
        AssociationState.observedUnmatched => 'OBSERVED_UNMATCHED',
      };
}

/// Neutral pitch facts for one structural element.
///
/// Derived directly from an H2.6 association, an expected-unmatched element, or
/// an observed-unmatched element. Both MIDI pitches are preserved for the side
/// that exists; the side that does not exist is null. No score, no enharmonic
/// rules, no correctness claim.
final class PitchObservation {
  final AssociationState associationState;

  /// Index into [ExpectedMusicalTarget.notes]. Null only for an
  /// observed-unmatched element.
  final int? expectedNoteIndex;
  final int? expectedPitch;

  /// Index of the enclosing [ExpectedOnsetGroup]; null when the target does
  /// not place the note in a group.
  final int? expectedGroupIndex;

  /// Index into the original observed [MusicalEvent] stream. Null only for an
  /// expected-unmatched element.
  final int? observedEventIndex;

  /// Observed MIDI pitch. Null only for an expected-unmatched element.
  final int? observedPitch;

  /// Observed semantic type; present for any element with an observed side.
  final MusicalSemanticType? observedType;

  PitchObservation({
    required this.associationState,
    required this.expectedNoteIndex,
    required this.expectedPitch,
    required this.expectedGroupIndex,
    required this.observedEventIndex,
    required this.observedPitch,
    required this.observedType,
  }) {
    switch (associationState) {
      case AssociationState.associated:
        if (expectedNoteIndex == null ||
            expectedPitch == null ||
            observedEventIndex == null ||
            observedPitch == null ||
            observedType == null) {
          throw const FormatException(
              'PitchObservation: associated elements must carry both expected '
              'and observed sides.');
        }
      case AssociationState.expectedUnmatched:
        if (expectedNoteIndex == null ||
            expectedPitch == null ||
            observedEventIndex != null ||
            observedPitch != null) {
          throw const FormatException(
              'PitchObservation: expected-unmatched elements must carry an '
              'expected side and no observed side.');
        }
      case AssociationState.observedUnmatched:
        if (observedEventIndex == null ||
            observedPitch == null ||
            observedType == null ||
            expectedNoteIndex != null ||
            expectedPitch != null) {
          throw const FormatException(
              'PitchObservation: observed-unmatched elements must carry an '
              'observed side and no expected side.');
        }
    }
  }

  @override
  String toString() =>
      'PitchObservation(${associationState.serialName} '
      'expected=${expectedNoteIndex == null ? '-' : '#$expectedNoteIndex pitch=$expectedPitch'} '
      'observed=${observedEventIndex == null ? '-' : '#$observedEventIndex pitch=$observedPitch'})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PitchObservation &&
          other.associationState == associationState &&
          other.expectedNoteIndex == expectedNoteIndex &&
          other.expectedPitch == expectedPitch &&
          other.expectedGroupIndex == expectedGroupIndex &&
          other.observedEventIndex == observedEventIndex &&
          other.observedPitch == observedPitch &&
          other.observedType == observedType;

  @override
  int get hashCode => Object.hash(associationState, expectedNoteIndex,
      expectedPitch, expectedGroupIndex, observedEventIndex, observedPitch,
      observedType);

  Map<String, Object?> toMap() => <String, Object?>{
        'association_state': associationState.serialName,
        'expected_note_index': expectedNoteIndex,
        'expected_pitch': expectedPitch,
        'expected_group_index': expectedGroupIndex,
        'observed_event_index': observedEventIndex,
        'observed_pitch': observedPitch,
        'observed_type': observedType?.name,
      };
}

/// Neutral timing facts for one structural element.
///
/// Raw comparable quantities only: expected onset offset (relative to target
/// start, when prescribed) and observed onset timestamp. The absence of a
/// counterpart is preserved as null - never fabricated into a timestamp.
final class TimingObservation {
  final AssociationState associationState;

  final int? expectedNoteIndex;

  /// Expected absolute onset offset from target start (null = target prescribes
  /// no timing). Relative to the target, never an absolute wall-clock value.
  final int? expectedOnsetOffsetMs;

  final int? observedEventIndex;

  /// Observed onset timestamp in the observed stream's time base.
  final int? observedOnsetTimestampMs;

  TimingObservation({
    required this.associationState,
    required this.expectedNoteIndex,
    required this.expectedOnsetOffsetMs,
    required this.observedEventIndex,
    required this.observedOnsetTimestampMs,
  }) {
    switch (associationState) {
      case AssociationState.associated:
        if (expectedNoteIndex == null ||
            observedEventIndex == null ||
            observedOnsetTimestampMs == null) {
          throw const FormatException(
              'TimingObservation: associated elements must carry both expected '
              'and observed sides.');
        }
      case AssociationState.expectedUnmatched:
        if (expectedNoteIndex == null ||
            observedEventIndex != null ||
            observedOnsetTimestampMs != null) {
          throw const FormatException(
              'TimingObservation: expected-unmatched elements must carry an '
              'expected side and no observed side.');
        }
      case AssociationState.observedUnmatched:
        if (observedEventIndex == null ||
            observedOnsetTimestampMs == null ||
            expectedNoteIndex != null) {
          throw const FormatException(
              'TimingObservation: observed-unmatched elements must carry an '
              'observed side and no expected side.');
        }
    }
  }

  @override
  String toString() =>
      'TimingObservation(${associationState.serialName} '
      'expected=#${expectedNoteIndex ?? '-'}@${expectedOnsetOffsetMs ?? '-'}ms '
      'observed=#${observedEventIndex ?? '-'}@${observedOnsetTimestampMs ?? '-'}ms)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimingObservation &&
          other.associationState == associationState &&
          other.expectedNoteIndex == expectedNoteIndex &&
          other.expectedOnsetOffsetMs == expectedOnsetOffsetMs &&
          other.observedEventIndex == observedEventIndex &&
          other.observedOnsetTimestampMs == observedOnsetTimestampMs;

  @override
  int get hashCode => Object.hash(associationState, expectedNoteIndex,
      expectedOnsetOffsetMs, observedEventIndex, observedOnsetTimestampMs);

  Map<String, Object?> toMap() => <String, Object?>{
        'association_state': associationState.serialName,
        'expected_note_index': expectedNoteIndex,
        'expected_onset_offset_ms': expectedOnsetOffsetMs,
        'observed_event_index': observedEventIndex,
        'observed_onset_timestamp_ms': observedOnsetTimestampMs,
      };
}

/// One position-holder inside an ordered sequence.
///
/// [index] is an expected note index for an expected sequence and an observed
/// event index for an observed sequence. [sequencePosition] is the zero-based
/// position of the element within that sequence.
final class OrderElement {
  final int index;
  final int pitch;
  final int sequencePosition;

  OrderElement({
    required this.index,
    required this.pitch,
    required this.sequencePosition,
  }) {
    if (index < 0) {
      throw const FormatException('OrderElement: index must be >= 0.');
    }
    if (pitch < 0 || pitch > 127) {
      throw const FormatException('OrderElement: pitch must be in 0..127.');
    }
    if (sequencePosition < 0) {
      throw const FormatException('OrderElement: sequencePosition must be >= 0.');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderElement &&
          other.index == index &&
          other.pitch == pitch &&
          other.sequencePosition == sequencePosition;

  @override
  int get hashCode => Object.hash(index, pitch, sequencePosition);

  Map<String, Object?> toMap() => <String, Object?>{
        'index': index,
        'pitch': pitch,
        'sequence_position': sequencePosition,
      };
}

/// One structurally-associated pair inside the order dimension.
///
/// Carries both sides' indices, pitches, and their positions within their
/// respective sequences. The positions allow a future evaluator to reason
/// about order without H2.7 ever emitting an order verdict.
final class OrderAssociation {
  final int expectedNoteIndex;
  final int expectedPitch;
  final int expectedSequencePosition;
  final int observedEventIndex;
  final int observedPitch;
  final int observedSequencePosition;

  OrderAssociation({
    required this.expectedNoteIndex,
    required this.expectedPitch,
    required this.expectedSequencePosition,
    required this.observedEventIndex,
    required this.observedPitch,
    required this.observedSequencePosition,
  }) {
    if (expectedNoteIndex < 0 ||
        expectedSequencePosition < 0 ||
        observedEventIndex < 0 ||
        observedSequencePosition < 0) {
      throw const FormatException(
          'OrderAssociation: indices and positions must be >= 0.');
    }
    if (expectedPitch < 0 || expectedPitch > 127) {
      throw const FormatException('OrderAssociation: expectedPitch out of range.');
    }
    if (observedPitch < 0 || observedPitch > 127) {
      throw const FormatException('OrderAssociation: observedPitch out of range.');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderAssociation &&
          other.expectedNoteIndex == expectedNoteIndex &&
          other.expectedPitch == expectedPitch &&
          other.expectedSequencePosition == expectedSequencePosition &&
          other.observedEventIndex == observedEventIndex &&
          other.observedPitch == observedPitch &&
          other.observedSequencePosition == observedSequencePosition;

  @override
  int get hashCode => Object.hash(expectedNoteIndex, expectedPitch,
      expectedSequencePosition, observedEventIndex, observedPitch,
      observedSequencePosition);

  Map<String, Object?> toMap() => <String, Object?>{
        'expected_note_index': expectedNoteIndex,
        'expected_pitch': expectedPitch,
        'expected_sequence_position': expectedSequencePosition,
        'observed_event_index': observedEventIndex,
        'observed_pitch': observedPitch,
        'observed_sequence_position': observedSequencePosition,
      };
}

/// Neutral order facts for an Arpeggio target.
///
/// The expected sequence, the observed sequence exactly as captured, and the
/// structurally associated pairs. Nothing is re-sorted to match the expected
/// order and no order verdict is produced.
final class OrderObservation {
  final List<OrderElement> expectedOrder;
  final List<OrderElement> observedOrder;
  final List<OrderAssociation> associatedPairs;

  OrderObservation({
    required List<OrderElement> expectedOrder,
    required List<OrderElement> observedOrder,
    required List<OrderAssociation> associatedPairs,
  })  : expectedOrder = List<OrderElement>.unmodifiable(expectedOrder),
        observedOrder = List<OrderElement>.unmodifiable(observedOrder),
        associatedPairs = List<OrderAssociation>.unmodifiable(associatedPairs);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderObservation &&
          _orderElementListEq(other.expectedOrder, expectedOrder) &&
          _orderElementListEq(other.observedOrder, observedOrder) &&
          _orderAssociationListEq(other.associatedPairs, associatedPairs);

  @override
  int get hashCode => Object.hash(Object.hashAll(expectedOrder),
      Object.hashAll(observedOrder), Object.hashAll(associatedPairs));

  Map<String, Object?> toMap() => <String, Object?>{
        'expected_order': expectedOrder.map((e) => e.toMap()).toList(growable: false),
        'observed_order': observedOrder.map((e) => e.toMap()).toList(growable: false),
        'associated_pairs':
            associatedPairs.map((p) => p.toMap()).toList(growable: false),
      };
}

/// One adjacent inter-onset interval between two ordered elements.
///
/// Raw, signed interval (`to - from`) computed from onset quantities on one
/// side. A null [ioiMs] represents an unavailable interval explicitly; no
/// interval is ever invented.
final class IoiEntry {
  final int fromEventIndex;
  final int toEventIndex;
  final int? ioiMs;

  IoiEntry({
    required this.fromEventIndex,
    required this.toEventIndex,
    required this.ioiMs,
  }) {
    if (fromEventIndex < 0 || toEventIndex < 0) {
      throw const FormatException('IoiEntry: indices must be >= 0.');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IoiEntry &&
          other.fromEventIndex == fromEventIndex &&
          other.toEventIndex == toEventIndex &&
          other.ioiMs == ioiMs;

  @override
  int get hashCode => Object.hash(fromEventIndex, toEventIndex, ioiMs);

  Map<String, Object?> toMap() => <String, Object?>{
        'from_event_index': fromEventIndex,
        'to_event_index': toEventIndex,
        'ioi_ms': ioiMs,
      };
}

/// Raw onset facts for members of one expected onset group (Block targets).
///
/// Exposes group membership, the associated observed events with their onset
/// timestamps, and a raw observed span when derivable. No interpretation of
/// the span is made and no simultaneity threshold exists.
final class SimultaneityGroup {
  final int expectedGroupIndex;

  /// Expected onset offset of the whole group from target start.
  final int? expectedOnsetOffsetMs;

  /// Expected note indices of the group, in member order.
  final List<int> expectedMemberIndices;

  /// Expected pitches of the members, aligned to [expectedMemberIndices].
  final List<int> expectedMemberPitches;

  /// Observed event indices associated with members that were matched, in
  /// member order (unmatched members contribute nothing here).
  final List<int> observedAssociatedEventIndices;

  /// Onset timestamps aligned to [observedAssociatedEventIndices].
  final List<int> observedOnsetTimestampsMs;

  /// Members with no structural association (incomplete association structure
  /// is preserved, never fabricated).
  final List<int> unmatchedExpectedMemberIndices;

  final int? minObservedOnsetMs;
  final int? maxObservedOnsetMs;

  /// `max - min` when at least one onset exists; null when none exist.
  final int? observedSpanMs;

  SimultaneityGroup({
    required this.expectedGroupIndex,
    required this.expectedOnsetOffsetMs,
    required List<int> expectedMemberIndices,
    required List<int> expectedMemberPitches,
    required List<int> observedAssociatedEventIndices,
    required List<int> observedOnsetTimestampsMs,
    required List<int> unmatchedExpectedMemberIndices,
    required this.minObservedOnsetMs,
    required this.maxObservedOnsetMs,
    required this.observedSpanMs,
  })  : expectedMemberIndices = List<int>.unmodifiable(expectedMemberIndices),
        expectedMemberPitches = List<int>.unmodifiable(expectedMemberPitches),
        observedAssociatedEventIndices =
            List<int>.unmodifiable(observedAssociatedEventIndices),
        observedOnsetTimestampsMs = List<int>.unmodifiable(observedOnsetTimestampsMs),
        unmatchedExpectedMemberIndices =
            List<int>.unmodifiable(unmatchedExpectedMemberIndices) {
    if (expectedGroupIndex < 0) {
      throw const FormatException('SimultaneityGroup: expectedGroupIndex must be >= 0.');
    }
    if (expectedMemberIndices.length != expectedMemberPitches.length) {
      throw const FormatException(
          'SimultaneityGroup: member indices and pitches must have equal length.');
    }
    if (observedAssociatedEventIndices.length != observedOnsetTimestampsMs.length) {
      throw const FormatException(
          'SimultaneityGroup: observed event indices and timestamps must have '
          'equal length.');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SimultaneityGroup &&
          other.expectedGroupIndex == expectedGroupIndex &&
          other.expectedOnsetOffsetMs == expectedOnsetOffsetMs &&
          _intListEq(other.expectedMemberIndices, expectedMemberIndices) &&
          _intListEq(other.expectedMemberPitches, expectedMemberPitches) &&
          _intListEq(other.observedAssociatedEventIndices,
              observedAssociatedEventIndices) &&
          _intListEq(other.observedOnsetTimestampsMs, observedOnsetTimestampsMs) &&
          _intListEq(other.unmatchedExpectedMemberIndices,
              unmatchedExpectedMemberIndices) &&
          other.minObservedOnsetMs == minObservedOnsetMs &&
          other.maxObservedOnsetMs == maxObservedOnsetMs &&
          other.observedSpanMs == observedSpanMs;

  @override
  int get hashCode => Object.hash(expectedGroupIndex, expectedOnsetOffsetMs,
      Object.hashAll(expectedMemberIndices), Object.hashAll(expectedMemberPitches),
      Object.hashAll(observedAssociatedEventIndices),
      Object.hashAll(observedOnsetTimestampsMs),
      Object.hashAll(unmatchedExpectedMemberIndices), minObservedOnsetMs,
      maxObservedOnsetMs, observedSpanMs);

  Map<String, Object?> toMap() => <String, Object?>{
        'expected_group_index': expectedGroupIndex,
        'expected_onset_offset_ms': expectedOnsetOffsetMs,
        'expected_member_indices': expectedMemberIndices,
        'expected_member_pitches': expectedMemberPitches,
        'observed_associated_event_indices': observedAssociatedEventIndices,
        'observed_onset_timestamps_ms': observedOnsetTimestampsMs,
        'unmatched_expected_member_indices': unmatchedExpectedMemberIndices,
        'min_observed_onset_ms': minObservedOnsetMs,
        'max_observed_onset_ms': maxObservedOnsetMs,
        'observed_span_ms': observedSpanMs,
      };
}

/// Raw retrieval-latency facts.
///
/// The locked Evaluation Contract includes Retrieval Latency, but the frozen
/// models contain no performance anchor. H2.7 therefore reports
/// [ObservationAvailability.unavailable] and never fabricates a ready
/// timestamp (session start, first JSONL event, target creation time, or wall
/// clock are all rejected as anchors). The first qualifying observed note is
/// still exposed as raw observed data.
final class RetrievalLatencyObservation {
  /// Always [ObservationAvailability.unavailable] while no frozen model
  /// provides a valid performance anchor.
  final ObservationAvailability availability;

  /// Stable reason for the availability state.
  final String reason;

  /// Performance anchor ready timestamp; null (never fabricated).
  final int? performanceAnchorTimestampMs;

  /// Context label for a supplied anchor; null when none exists.
  final String? performanceAnchorContext;

  /// Event index of the first qualifying observed note (earliest onset).
  final int? firstObservedNoteEventIndex;

  /// Onset timestamp of the first qualifying observed note.
  final int? firstObservedNoteTimestampMs;

  /// Latency duration (`firstObservedNote - ready`); null while unavailable.
  final int? latencyDurationMs;

  RetrievalLatencyObservation({
    required this.availability,
    required this.reason,
    required this.performanceAnchorTimestampMs,
    required this.performanceAnchorContext,
    required this.firstObservedNoteEventIndex,
    required this.firstObservedNoteTimestampMs,
    required this.latencyDurationMs,
  }) {
    if (availability == ObservationAvailability.unavailable &&
        (performanceAnchorTimestampMs != null ||
            performanceAnchorContext != null ||
            latencyDurationMs != null)) {
      throw const FormatException(
          'RetrievalLatencyObservation: an unavailable observation must not '
          'carry an anchor or latency duration.');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RetrievalLatencyObservation &&
          other.availability == availability &&
          other.reason == reason &&
          other.performanceAnchorTimestampMs == performanceAnchorTimestampMs &&
          other.performanceAnchorContext == performanceAnchorContext &&
          other.firstObservedNoteEventIndex == firstObservedNoteEventIndex &&
          other.firstObservedNoteTimestampMs == firstObservedNoteTimestampMs &&
          other.latencyDurationMs == latencyDurationMs;

  @override
  int get hashCode => Object.hash(availability, reason,
      performanceAnchorTimestampMs, performanceAnchorContext,
      firstObservedNoteEventIndex, firstObservedNoteTimestampMs, latencyDurationMs);

  Map<String, Object?> toMap() => <String, Object?>{
        'availability': availability.serialName,
        'reason': reason,
        'performance_anchor_timestamp_ms': performanceAnchorTimestampMs,
        'performance_anchor_context': performanceAnchorContext,
        'first_observed_note_event_index': firstObservedNoteEventIndex,
        'first_observed_note_timestamp_ms': firstObservedNoteTimestampMs,
        'latency_duration_ms': latencyDurationMs,
      };
}

/// Immutable, deterministic set of neutral observations for one alignment.
///
/// H2.7 is the final neutral step before Evaluation:
///
/// ```text
/// ExpectedMusicalTarget
///         + MusicalEvent
///         + StructuralAlignment
///               |
/// EvaluationDimensionObservations     <- H2.7 (this model)
///               |
/// Evaluation Profile + Evaluation Engine   <- later
/// ```
///
/// Each dimension is independently inspectable. The model carries structural
/// facts only: no correctness, pass/fail, score, grade, tolerance, error
/// vector, mastery, evidence, priority, or scheduler information.
final class EvaluationDimensionObservations {
  final String targetId;
  final String sessionId;
  final TargetMode mode;

  /// Versions of the producing layers, for provenance.
  final String alignmentAlgorithmVersion;
  final String extractionAlgorithmVersion;

  final PitchObservations pitch;
  final TimingObservations timing;
  final OrderObservations order;
  final SimultaneityObservations simultaneity;
  final IoiObservations ioi;
  final RetrievalLatencyObservation retrievalLatency;

  /// Provenance passthrough of the H2.6 alignment's ignored references.
  final List<int> ignoredNonNoteEventRefs;
  final List<int> ignoredIntegrityAnomalyEventRefs;
  final List<int> ignoredOtherSessionEventRefs;

  EvaluationDimensionObservations({
    required this.targetId,
    required this.sessionId,
    required this.mode,
    required this.alignmentAlgorithmVersion,
    required this.extractionAlgorithmVersion,
    required this.pitch,
    required this.timing,
    required this.order,
    required this.simultaneity,
    required this.ioi,
    required this.retrievalLatency,
    required List<int> ignoredNonNoteEventRefs,
    required List<int> ignoredIntegrityAnomalyEventRefs,
    required List<int> ignoredOtherSessionEventRefs,
  })  : ignoredNonNoteEventRefs = List<int>.unmodifiable(ignoredNonNoteEventRefs),
        ignoredIntegrityAnomalyEventRefs =
            List<int>.unmodifiable(ignoredIntegrityAnomalyEventRefs),
        ignoredOtherSessionEventRefs =
            List<int>.unmodifiable(ignoredOtherSessionEventRefs);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EvaluationDimensionObservations &&
          other.targetId == targetId &&
          other.sessionId == sessionId &&
          other.mode == mode &&
          other.alignmentAlgorithmVersion == alignmentAlgorithmVersion &&
          other.extractionAlgorithmVersion == extractionAlgorithmVersion &&
          other.pitch == pitch &&
          other.timing == timing &&
          other.order == order &&
          other.simultaneity == simultaneity &&
          other.ioi == ioi &&
          other.retrievalLatency == retrievalLatency &&
          _intListEq(other.ignoredNonNoteEventRefs, ignoredNonNoteEventRefs) &&
          _intListEq(other.ignoredIntegrityAnomalyEventRefs,
              ignoredIntegrityAnomalyEventRefs) &&
          _intListEq(other.ignoredOtherSessionEventRefs, ignoredOtherSessionEventRefs);

  @override
  int get hashCode => Object.hash(targetId, sessionId, mode,
      alignmentAlgorithmVersion, extractionAlgorithmVersion, pitch, timing, order,
      simultaneity, ioi, retrievalLatency, Object.hashAll(ignoredNonNoteEventRefs),
      Object.hashAll(ignoredIntegrityAnomalyEventRefs),
      Object.hashAll(ignoredOtherSessionEventRefs));

  Map<String, Object?> toMap() => <String, Object?>{
        'target_id': targetId,
        'session_id': sessionId,
        'mode': mode.name,
        'alignment_algorithm_version': alignmentAlgorithmVersion,
        'extraction_algorithm_version': extractionAlgorithmVersion,
        'pitch': pitch.toMap(),
        'timing': timing.toMap(),
        'order': order.toMap(),
        'simultaneity': simultaneity.toMap(),
        'ioi': ioi.toMap(),
        'retrieval_latency': retrievalLatency.toMap(),
        'ignored_non_note_event_refs': ignoredNonNoteEventRefs,
        'ignored_integrity_anomaly_event_refs': ignoredIntegrityAnomalyEventRefs,
        'ignored_other_session_event_refs': ignoredOtherSessionEventRefs,
      };
}

/// Dimension-set wrappers: availability + independent observation list.
final class PitchObservations {
  final ObservationAvailability availability;
  final List<PitchObservation> observations;

  PitchObservations({
    required this.availability,
    required List<PitchObservation> observations,
  }) : observations = List<PitchObservation>.unmodifiable(observations);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PitchObservations &&
          other.availability == availability &&
          _pitchObservationListEq(other.observations, observations);

  @override
  int get hashCode => Object.hash(availability, Object.hashAll(observations));

  Map<String, Object?> toMap() => <String, Object?>{
        'availability': availability.serialName,
        'observations':
            observations.map((o) => o.toMap()).toList(growable: false),
      };
}

final class TimingObservations {
  final ObservationAvailability availability;
  final List<TimingObservation> observations;

  TimingObservations({
    required this.availability,
    required List<TimingObservation> observations,
  }) : observations = List<TimingObservation>.unmodifiable(observations);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimingObservations &&
          other.availability == availability &&
          _timingObservationListEq(other.observations, observations);

  @override
  int get hashCode => Object.hash(availability, Object.hashAll(observations));

  Map<String, Object?> toMap() => <String, Object?>{
        'availability': availability.serialName,
        'observations':
            observations.map((o) => o.toMap()).toList(growable: false),
      };
}

final class OrderObservations {
  final ObservationAvailability availability;

  /// Order facts. Empty when the dimension is
  /// [ObservationAvailability.notApplicable] (Block targets); the
  /// availability value carries the semantic meaning.
  final OrderObservation order;

  OrderObservations({
    required this.availability,
    required this.order,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderObservations &&
          other.availability == availability &&
          other.order == order;

  @override
  int get hashCode => Object.hash(availability, order);

  Map<String, Object?> toMap() => <String, Object?>{
        'availability': availability.serialName,
        'order': order.toMap(),
      };
}

final class SimultaneityObservations {
  final ObservationAvailability availability;
  final List<SimultaneityGroup> groups;

  SimultaneityObservations({
    required this.availability,
    required List<SimultaneityGroup> groups,
  }) : groups = List<SimultaneityGroup>.unmodifiable(groups);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SimultaneityObservations &&
          other.availability == availability &&
          _simultaneityGroupListEq(other.groups, groups);

  @override
  int get hashCode => Object.hash(availability, Object.hashAll(groups));

  Map<String, Object?> toMap() => <String, Object?>{
        'availability': availability.serialName,
        'groups': groups.map((g) => g.toMap()).toList(growable: false),
      };
}

final class IoiObservations {
  final ObservationAvailability availability;
  final List<IoiEntry> expected;
  final List<IoiEntry> observed;

  IoiObservations({
    required this.availability,
    required List<IoiEntry> expected,
    required List<IoiEntry> observed,
  })  : expected = List<IoiEntry>.unmodifiable(expected),
        observed = List<IoiEntry>.unmodifiable(observed);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IoiObservations &&
          other.availability == availability &&
          _ioiEntryListEq(other.expected, expected) &&
          _ioiEntryListEq(other.observed, observed);

  @override
  int get hashCode => Object.hash(
      availability, Object.hashAll(expected), Object.hashAll(observed));

  Map<String, Object?> toMap() => <String, Object?>{
        'availability': availability.serialName,
        'expected': expected.map((e) => e.toMap()).toList(growable: false),
        'observed': observed.map((e) => e.toMap()).toList(growable: false),
      };
}

bool _pitchObservationListEq(List<PitchObservation> a, List<PitchObservation> b) {
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

bool _timingObservationListEq(List<TimingObservation> a, List<TimingObservation> b) {
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

bool _orderElementListEq(List<OrderElement> a, List<OrderElement> b) {
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

bool _orderAssociationListEq(List<OrderAssociation> a, List<OrderAssociation> b) {
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

bool _simultaneityGroupListEq(List<SimultaneityGroup> a, List<SimultaneityGroup> b) {
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

bool _ioiEntryListEq(List<IoiEntry> a, List<IoiEntry> b) {
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