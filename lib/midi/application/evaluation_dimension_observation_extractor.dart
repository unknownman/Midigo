import '../domain/evaluation_dimension_observations.dart';
import '../domain/expected_musical_target.dart';
import '../domain/expected_note_event.dart';
import '../domain/musical_event.dart';
import '../domain/structural_alignment.dart';

/// Deterministic, neutral extraction of per-dimension observations.
///
/// H2.7 consumes the frozen H2.4/H2.5/H2.6 layers and answers "what observable
/// structural facts are available for each evaluation dimension?". It does NOT
/// answer "did the learner pass?" - that decision belongs to the Evaluation
/// Profile and Evaluation Engine (later).
///
/// Inputs are treated as immutable and are never mutated. The extractor does
/// not re-parse raw MIDI, re-normalize, or re-run structural alignment: it
/// derives everything from the provided [StructuralAlignment] plus the target
/// structure, cross-checking observed references against the [observed] stream
/// for provenance integrity.
///
/// No thresholds or tolerances exist anywhere in this component or its output.
///
/// Retrieval Latency: the frozen models contain no performance anchor. The
/// extractor therefore reports `UNAVAILABLE` and never fabricates a ready
/// timestamp from session start, first event, target creation time, or wall
/// clock (all of which are invalid anchors).
final class EvaluationDimensionObservationExtractor {
  const EvaluationDimensionObservationExtractor();

  /// Deterministic extraction algorithm version.
  static const String algorithmVersion = '1';

  /// Stable reason attached to an [ObservationAvailability.unavailable]
  /// retrieval-latency observation.
  static const String retrievalLatencyUnavailableReason =
      'NO_RUNTIME_PERFORMANCE_ANCHOR';

  EvaluationDimensionObservations extract({
    required ExpectedMusicalTarget target,
    required List<MusicalEvent> observed,
    required StructuralAlignment alignment,
  }) {
    if (alignment.targetId != target.targetId) {
      throw FormatException(
          'EvaluationDimensionObservationExtractor: alignment targetId '
          "'${alignment.targetId}' does not match target '$target.targetId'.");
    }

    final observedByIndex = _indexObserved(observed);

    final pitchObservations = <PitchObservation>[];
    final timingObservations = <TimingObservation>[];

    for (final match in alignment.matches) {
      _requireObserved(match.observedEventIndex, observedByIndex);
      pitchObservations.add(PitchObservation(
        associationState: AssociationState.associated,
        expectedNoteIndex: match.expectedNoteIndex,
        expectedPitch: match.expectedPitch,
        expectedGroupIndex: match.expectedGroupIndex,
        observedEventIndex: match.observedEventIndex,
        observedPitch: match.observedPitch,
        observedType: match.observedType,
      ));
      timingObservations.add(TimingObservation(
        associationState: AssociationState.associated,
        expectedNoteIndex: match.expectedNoteIndex,
        expectedOnsetOffsetMs: match.expectedOnsetOffsetMs,
        observedEventIndex: match.observedEventIndex,
        observedOnsetTimestampMs: match.observedOnsetTimestampMs,
      ));
    }

    for (final element in alignment.unmatchedExpected) {
      pitchObservations.add(PitchObservation(
        associationState: AssociationState.expectedUnmatched,
        expectedNoteIndex: element.expectedNoteIndex,
        expectedPitch: element.expectedPitch,
        expectedGroupIndex: element.expectedGroupIndex,
        observedEventIndex: null,
        observedPitch: null,
        observedType: null,
      ));
      timingObservations.add(TimingObservation(
        associationState: AssociationState.expectedUnmatched,
        expectedNoteIndex: element.expectedNoteIndex,
        expectedOnsetOffsetMs: element.expectedOnsetOffsetMs,
        observedEventIndex: null,
        observedOnsetTimestampMs: null,
      ));
    }

    for (final element in alignment.unmatchedObserved) {
      _requireObserved(element.observedEventIndex, observedByIndex);
      pitchObservations.add(PitchObservation(
        associationState: AssociationState.observedUnmatched,
        expectedNoteIndex: null,
        expectedPitch: null,
        expectedGroupIndex: null,
        observedEventIndex: element.observedEventIndex,
        observedPitch: element.observedPitch,
        observedType: element.observedType,
      ));
      timingObservations.add(TimingObservation(
        associationState: AssociationState.observedUnmatched,
        expectedNoteIndex: null,
        expectedOnsetOffsetMs: null,
        observedEventIndex: element.observedEventIndex,
        observedOnsetTimestampMs: element.observedOnsetTimestampMs,
      ));
    }

    // Observed note sequence: union of associated and observed-unmatched note
    // events, in capture order (ascending event index). This is the raw
    // observed sequence exactly as captured; it is never reordered.
    final observedNoteByIndex = <int, (int pitch, int onsetTs)>{};
    for (final match in alignment.matches) {
      observedNoteByIndex[match.observedEventIndex] =
          (match.observedPitch, match.observedOnsetTimestampMs);
    }
    for (final element in alignment.unmatchedObserved) {
      observedNoteByIndex[element.observedEventIndex] =
          (element.observedPitch, element.observedOnsetTimestampMs);
    }
    final observedNoteEntries = observedNoteByIndex.entries.toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));
    final observedNoteIndices = observedNoteEntries.map((e) => e.key).toList();

    final pitch = PitchObservations(
      availability: pitchObservations.isEmpty
          ? ObservationAvailability.unavailable
          : ObservationAvailability.available,
      observations: pitchObservations,
    );

    final timing = TimingObservations(
      availability: timingObservations.isEmpty
          ? ObservationAvailability.unavailable
          : ObservationAvailability.available,
      observations: timingObservations,
    );

    final order = _buildOrder(target, alignment, observedNoteIndices);
    final ioi = _buildIoi(target, alignment, observedNoteEntries);
    final simultaneity = _buildSimultaneity(target, alignment);
    final retrievalLatency = _buildRetrievalLatency(observedNoteEntries);

    return EvaluationDimensionObservations(
      targetId: target.targetId,
      sessionId: alignment.sessionId,
      mode: target.mode,
      alignmentAlgorithmVersion: alignment.algorithmVersion,
      extractionAlgorithmVersion: algorithmVersion,
      pitch: pitch,
      timing: timing,
      order: order,
      simultaneity: simultaneity,
      ioi: ioi,
      retrievalLatency: retrievalLatency,
      ignoredNonNoteEventRefs: alignment.ignoredNonNoteEventRefs,
      ignoredIntegrityAnomalyEventRefs: alignment.ignoredIntegrityAnomalyEventRefs,
      ignoredOtherSessionEventRefs: alignment.ignoredOtherSessionEventRefs,
    );
  }

  static Map<int, MusicalEvent> _indexObserved(List<MusicalEvent> observed) {
    final byIndex = <int, MusicalEvent>{};
    for (final event in observed) {
      if (byIndex.containsKey(event.eventIndex)) {
        throw FormatException(
            'EvaluationDimensionObservationExtractor: duplicate observed '
            'event index ${event.eventIndex}.');
      }
      byIndex[event.eventIndex] = event;
    }
    return byIndex;
  }

  static void _requireObserved(
      int eventIndex, Map<int, MusicalEvent> observedByIndex) {
    if (!observedByIndex.containsKey(eventIndex)) {
      throw FormatException(
          'EvaluationDimensionObservationExtractor: alignment references '
          'observed event index $eventIndex, but the supplied observed stream '
          'does not contain it.');
    }
  }

  static OrderObservations _buildOrder(
      ExpectedMusicalTarget target,
      StructuralAlignment alignment,
      List<int> observedNoteIndices) {
    if (target.mode != TargetMode.arpeggio) {
      return OrderObservations(
        availability: ObservationAvailability.notApplicable,
        order: OrderObservation(
          expectedOrder: <OrderElement>[],
          observedOrder: <OrderElement>[],
          associatedPairs: <OrderAssociation>[],
        ),
      );
    }

    final expectedOrder = <OrderElement>[
      for (var i = 0; i < target.notes.length; i++)
        OrderElement(
          index: target.notes[i].index,
          pitch: target.notes[i].pitch,
          sequencePosition: i,
        ),
    ];

    final expectedPositionByNoteIndex = <int, int>{
      for (final element in expectedOrder) element.index: element.sequencePosition,
    };

    final observedOrder = <OrderElement>[
      for (var i = 0; i < observedNoteIndices.length; i++)
        OrderElement(
          index: observedNoteIndices[i],
          pitch: _observedPitch(alignment, observedNoteIndices[i]),
          sequencePosition: i,
        ),
    ];
    final observedPositionByEventIndex = <int, int>{
      for (final element in observedOrder) element.index: element.sequencePosition,
    };

    final associatedPairs = <OrderAssociation>[
      for (final match in alignment.matches)
        OrderAssociation(
          expectedNoteIndex: match.expectedNoteIndex,
          expectedPitch: match.expectedPitch,
          expectedSequencePosition:
              expectedPositionByNoteIndex[match.expectedNoteIndex] ?? -1,
          observedEventIndex: match.observedEventIndex,
          observedPitch: match.observedPitch,
          observedSequencePosition:
              observedPositionByEventIndex[match.observedEventIndex] ?? -1,
        ),
    ];

    return OrderObservations(
      availability: ObservationAvailability.available,
      order: OrderObservation(
        expectedOrder: expectedOrder,
        observedOrder: observedOrder,
        associatedPairs: associatedPairs,
      ),
    );
  }

  static IoiObservations _buildIoi(
      ExpectedMusicalTarget target,
      StructuralAlignment alignment,
      List<MapEntry<int, (int, int)>> observedNoteEntries) {
    if (target.mode != TargetMode.arpeggio) {
      return IoiObservations(
        availability: ObservationAvailability.notApplicable,
        expected: <IoiEntry>[],
        observed: <IoiEntry>[],
      );
    }

    final expectedOffsetByNoteIndex = _expectedOffsetByNoteIndex(target);

    final expectedIois = <IoiEntry>[];
    for (var i = 0; i < target.notes.length - 1; i++) {
      final from = target.notes[i];
      final to = target.notes[i + 1];
      final fromOffset = expectedOffsetByNoteIndex[from.index];
      final toOffset = expectedOffsetByNoteIndex[to.index];
      expectedIois.add(IoiEntry(
        fromEventIndex: from.index,
        toEventIndex: to.index,
        ioiMs: fromOffset == null || toOffset == null
            ? null
            : toOffset - fromOffset,
      ));
    }

    final observedIois = <IoiEntry>[];
    for (var i = 0; i + 1 < observedNoteEntries.length; i++) {
      final from = observedNoteEntries[i];
      final to = observedNoteEntries[i + 1];
      observedIois.add(IoiEntry(
        fromEventIndex: from.key,
        toEventIndex: to.key,
        ioiMs: to.value.$2 - from.value.$2,
      ));
    }

    final available = expectedIois.isNotEmpty || observedIois.isNotEmpty;
    return IoiObservations(
      availability: available
          ? ObservationAvailability.available
          : ObservationAvailability.unavailable,
      expected: expectedIois,
      observed: observedIois,
    );
  }

  static SimultaneityObservations _buildSimultaneity(
      ExpectedMusicalTarget target, StructuralAlignment alignment) {
    if (target.mode != TargetMode.block) {
      return SimultaneityObservations(
        availability: ObservationAvailability.notApplicable,
        groups: <SimultaneityGroup>[],
      );
    }

    final matchedObservedEventByNoteIndex = <int, int>{
      for (final match in alignment.matches)
        match.expectedNoteIndex: match.observedEventIndex,
    };
    final observedTsByEventIndex = <int, int>{
      for (final element in alignment.matches)
        element.observedEventIndex: element.observedOnsetTimestampMs,
      for (final element in alignment.unmatchedObserved)
        element.observedEventIndex: element.observedOnsetTimestampMs,
    };
    final pitchByNoteIndex = <int, int>{
      for (final ExpectedNoteEvent note in target.notes) note.index: note.pitch,
    };

    final groups = <SimultaneityGroup>[];
    for (final group in target.onsetGroups) {
      final memberIndices = group.memberEventIndices;
      final associated = <int>[];
      final associatedTs = <int>[];
      final unmatchedMembers = <int>[];
      for (final member in memberIndices) {
        final observedEventIndex = matchedObservedEventByNoteIndex[member];
        if (observedEventIndex == null) {
          unmatchedMembers.add(member);
        } else {
          associated.add(observedEventIndex);
          associatedTs.add(observedTsByEventIndex[observedEventIndex]!);
        }
      }
      final int? minTs;
      final int? maxTs;
      if (associatedTs.isEmpty) {
        minTs = null;
        maxTs = null;
      } else {
        minTs = associatedTs.reduce((a, b) => a < b ? a : b);
        maxTs = associatedTs.reduce((a, b) => a > b ? a : b);
      }
      groups.add(SimultaneityGroup(
        expectedGroupIndex: group.index,
        expectedOnsetOffsetMs: group.expectedOnsetOffsetMs,
        expectedMemberIndices: memberIndices,
        expectedMemberPitches: <int>[
          for (final member in memberIndices) pitchByNoteIndex[member]!,
        ],
        observedAssociatedEventIndices: associated,
        observedOnsetTimestampsMs: associatedTs,
        unmatchedExpectedMemberIndices: unmatchedMembers,
        minObservedOnsetMs: minTs,
        maxObservedOnsetMs: maxTs,
        observedSpanMs: (minTs == null || maxTs == null)
            ? null
            : maxTs - minTs,
      ));
    }

    return SimultaneityObservations(
      availability: groups.isEmpty
          ? ObservationAvailability.unavailable
          : ObservationAvailability.available,
      groups: groups,
    );
  }

  static RetrievalLatencyObservation _buildRetrievalLatency(
      List<MapEntry<int, (int, int)>> observedNoteEntries) {
    final first = observedNoteEntries.isEmpty ? null : observedNoteEntries.first;
    return RetrievalLatencyObservation(
      availability: ObservationAvailability.unavailable,
      reason: retrievalLatencyUnavailableReason,
      performanceAnchorTimestampMs: null,
      performanceAnchorContext: null,
      firstObservedNoteEventIndex: first?.key,
      firstObservedNoteTimestampMs: first?.value.$2,
      latencyDurationMs: null,
    );
  }

  static int _observedPitch(
      StructuralAlignment alignment, int observedEventIndex) {
    for (final match in alignment.matches) {
      if (match.observedEventIndex == observedEventIndex) {
        return match.observedPitch;
      }
    }
    for (final element in alignment.unmatchedObserved) {
      if (element.observedEventIndex == observedEventIndex) {
        return element.observedPitch;
      }
    }
    throw StateError('Impossible: observed event $observedEventIndex not found.');
  }

  static Map<int, int?> _expectedOffsetByNoteIndex(ExpectedMusicalTarget target) {
    final offsetByNote = <int, int?>{};
    for (final group in target.onsetGroups) {
      for (final member in group.memberEventIndices) {
        offsetByNote.putIfAbsent(member, () => group.expectedOnsetOffsetMs);
      }
    }
    return offsetByNote;
  }
}