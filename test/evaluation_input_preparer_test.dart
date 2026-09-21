import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/midi/application/evaluation_dimension_observation_extractor.dart';
import 'package:miditutor/midi/application/evaluation_input_preparer.dart';
import 'package:miditutor/midi/application/expected_musical_target_factory.dart';
import 'package:miditutor/midi/application/midi_normalizer.dart';
import 'package:miditutor/midi/application/musical_event_interpreter.dart';
import 'package:miditutor/midi/application/structural_aligner.dart';
import 'package:miditutor/midi/domain/evaluation_dimension_observations.dart';
import 'package:miditutor/midi/domain/evaluation_input.dart';
import 'package:miditutor/midi/domain/expected_musical_target.dart';
import 'package:miditutor/midi/domain/expected_note_event.dart';
import 'package:miditutor/midi/domain/musical_event.dart';
import 'package:miditutor/midi/domain/normalized_midi_event.dart';
import 'package:miditutor/midi/domain/raw_midi_event.dart';

const _session = 'h28-session';

String _project(EvaluationInput input) => jsonEncode(input.toMap());

/// H2.8 T18 forbidden evaluation concepts, substring-matched against output
/// keys and nested string values.
const _forbiddenConcepts = <String>[
  'correct',
  'incorrect',
  'pass',
  'fail',
  'success',
  'failure',
  'score',
  'grade',
  'accuracy',
  'error',
  'vector',
  'mastery',
  'qualified',
  'evidence',
  'priority',
];

Set<String> _collectKeys(Object? value, Set<String> into) {
  if (value is Map) {
    for (final entry in value.entries) {
      into.add(entry.key.toString().toLowerCase());
      _collectKeys(entry.value, into);
    }
  } else if (value is List) {
    for (final item in value) {
      _collectKeys(item, into);
    }
  }
  return into;
}

List<String> _collectStringValues(Object? value, List<String> into) {
  if (value is Map) {
    for (final entry in value.entries) {
      _collectStringValues(entry.value, into);
    }
  } else if (value is List) {
    for (final item in value) {
      _collectStringValues(item, into);
    }
  } else if (value is String) {
    into.add(value.toLowerCase());
  }
  return into;
}

NormalizedMidiEvent _norm(int seq, int ts, int? note,
        {String session = _session, String kind = 'on'}) =>
    NormalizedMidiEvent(
      source: RawMidiEvent(
        sessionId: session,
        deviceId: 'dev',
        connectionType: 'USB',
        seq: seq,
        appMonotonicTsMs: ts,
        messageType: switch (kind) {
          'off' => RawMidiMessageType.noteOff,
          'other' => RawMidiMessageType.other,
          _ => RawMidiMessageType.noteOn,
        },
        channel: 0,
        note: note,
        velocity: 90,
        rawBytes: <int>[0x90, note ?? 0, 90],
      ),
      type: switch (kind) {
        'off' => NormalizedMidiMessageType.noteOff,
        'other' => NormalizedMidiMessageType.other,
        _ => NormalizedMidiMessageType.noteOn,
      },
      normalizationRule: 'verbatim',
    );

MusicalEvent _lifecycle(int idx, int ts, int pitch,
        {String session = _session}) =>
    MusicalEvent(
      eventIndex: idx,
      sessionId: session,
      type: MusicalSemanticType.noteLifecycle,
      startTimestampMs: ts,
      endTimestampMs: ts + 100,
      channel: 0,
      pitch: pitch,
      velocity: 90,
      durationMs: 100,
      sources: <NormalizedMidiEvent>[
        _norm(idx, ts, pitch, session: session),
        _norm(idx, ts + 100, pitch, session: session, kind: 'off'),
      ],
    );

MusicalEvent _nonNote(int idx, int ts, {String session = _session}) =>
    MusicalEvent(
      eventIndex: idx,
      sessionId: session,
      type: MusicalSemanticType.nonNote,
      startTimestampMs: ts,
      sources: <NormalizedMidiEvent>[
        _norm(idx, ts, null, session: session, kind: 'other'),
      ],
    );

MusicalEvent _anomaly(int idx, int ts, String category,
        {String session = _session}) =>
    MusicalEvent(
      eventIndex: idx,
      sessionId: session,
      type: MusicalSemanticType.integrityAnomaly,
      startTimestampMs: ts,
      channel: 0,
      pitch: 60,
      anomalyCategory: category,
      sources: <NormalizedMidiEvent>[_norm(idx, ts, 60, session: session)],
    );

ExpectedMusicalTarget _blockTarget(List<int> pitches,
        {String targetId = 't-block'}) =>
    ExpectedMusicalTarget(
      targetId: targetId,
      quality: TargetQuality.major,
      root: TargetRoot.c,
      hand: TargetHand.right,
      mode: TargetMode.block,
      notes: <ExpectedNoteEvent>[
        for (var i = 0; i < pitches.length; i++)
          ExpectedNoteEvent(index: i, pitch: pitches[i]),
      ],
      onsetGroups: <ExpectedOnsetGroup>[
        ExpectedOnsetGroup(
          index: 0,
          memberEventIndices: <int>[for (var i = 0; i < pitches.length; i++) i],
          expectedOnsetOffsetMs: 0,
        ),
      ],
    );

EvaluationDimensionObservations _extract(
        ExpectedMusicalTarget target, List<MusicalEvent> observed) =>
    const EvaluationDimensionObservationExtractor().extract(
      target: target,
      observed: observed,
      alignment: const StructuralAligner()
          .align(target: target, sessionId: _session, observed: observed),
    );

EvaluationInput _prepare(ExpectedMusicalTarget target,
        List<MusicalEvent> observed) =>
    const EvaluationInputPreparer().prepare(observations: _extract(target, observed));

/// Manually-built H2.7 observation set for a Block target, used to prove H2.8
/// projects exactly the supplied observations (T12, T16).
EvaluationDimensionObservations _manualBlock({
  required PitchObservations pitch,
  required TimingObservations timing,
  SimultaneityObservations? simultaneity,
  List<int> ignoredNonNote = const <int>[],
  List<int> ignoredAnomaly = const <int>[],
}) =>
    EvaluationDimensionObservations(
      targetId: 't-block',
      sessionId: _session,
      mode: TargetMode.block,
      alignmentAlgorithmVersion: '1',
      extractionAlgorithmVersion: '1',
      pitch: pitch,
      timing: timing,
      order: OrderObservations(
        availability: ObservationAvailability.notApplicable,
        order: OrderObservation(
          expectedOrder: <OrderElement>[],
          observedOrder: <OrderElement>[],
          associatedPairs: <OrderAssociation>[],
        ),
      ),
      simultaneity: simultaneity ??
          SimultaneityObservations(
            availability: ObservationAvailability.notApplicable,
            groups: <SimultaneityGroup>[],
          ),
      ioi: IoiObservations(
        availability: ObservationAvailability.notApplicable,
        expected: <IoiEntry>[],
        observed: <IoiEntry>[],
      ),
      retrievalLatency: RetrievalLatencyObservation(
        availability: ObservationAvailability.unavailable,
        reason: EvaluationDimensionObservationExtractor.retrievalLatencyUnavailableReason,
        performanceAnchorTimestampMs: null,
        performanceAnchorContext: null,
        firstObservedNoteEventIndex: 0,
        firstObservedNoteTimestampMs: 1000,
        latencyDurationMs: null,
      ),
      ignoredNonNoteEventRefs: ignoredNonNote,
      ignoredIntegrityAnomalyEventRefs: ignoredAnomaly,
      ignoredOtherSessionEventRefs: <int>[],
    );

EvaluationDimensionState _stateOf(
        EvaluationInput input, EvaluationDimension dimension) =>
    switch (dimension) {
      EvaluationDimension.pitch => input.pitch.dimensionState,
      EvaluationDimension.timing => input.timing.dimensionState,
      EvaluationDimension.order => input.order.dimensionState,
      EvaluationDimension.simultaneity => input.simultaneity.dimensionState,
      EvaluationDimension.ioi => input.ioi.dimensionState,
      EvaluationDimension.retrievalLatency => input.retrievalLatency.dimensionState,
    };

DataAvailability _availabilityOf(
        EvaluationInput input, EvaluationDimension dimension) =>
    switch (dimension) {
      EvaluationDimension.pitch => input.pitch.dataAvailability,
      EvaluationDimension.timing => input.timing.dataAvailability,
      EvaluationDimension.order => input.order.dataAvailability,
      EvaluationDimension.simultaneity => input.simultaneity.dataAvailability,
      EvaluationDimension.ioi => input.ioi.dataAvailability,
      EvaluationDimension.retrievalLatency => input.retrievalLatency.dataAvailability,
    };

void main() {
  const factory = ExpectedMusicalTargetFactory();

  group('T1 - block profile', () {
    test('mvp_default_v1 applicability for a block target', () {
      final target = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.block);
      final input = _prepare(
        target,
        <MusicalEvent>[
          _lifecycle(0, 1000, 60),
          _lifecycle(1, 1002, 64),
          _lifecycle(2, 1004, 67),
        ],
      );

      expect(input.evaluationProfileId, 'mvp_default_v1');
      expect(input.evaluationProfileVersion, 'v1.1');
      expect(input.mode, TargetMode.block);

      expect(_stateOf(input, EvaluationDimension.pitch),
          EvaluationDimensionState.enabled);
      expect(_availabilityOf(input, EvaluationDimension.pitch),
          DataAvailability.available);
      expect(_stateOf(input, EvaluationDimension.timing),
          EvaluationDimensionState.enabled);
      expect(_availabilityOf(input, EvaluationDimension.timing),
          DataAvailability.available);
      expect(_stateOf(input, EvaluationDimension.simultaneity),
          EvaluationDimensionState.enabled);
      expect(_availabilityOf(input, EvaluationDimension.simultaneity),
          DataAvailability.available);
      expect(_stateOf(input, EvaluationDimension.retrievalLatency),
          EvaluationDimensionState.enabled);
      expect(_availabilityOf(input, EvaluationDimension.retrievalLatency),
          DataAvailability.unavailable);
      expect(_stateOf(input, EvaluationDimension.order),
          EvaluationDimensionState.notApplicable);
      expect(_availabilityOf(input, EvaluationDimension.order),
          DataAvailability.unavailable);
      expect(_stateOf(input, EvaluationDimension.ioi),
          EvaluationDimensionState.notApplicable);
      expect(_availabilityOf(input, EvaluationDimension.ioi),
          DataAvailability.unavailable);
    });
  });

  group('T2 - arpeggio profile', () {
    test('mvp_default_v1 applicability for an arpeggio target', () {
      final target = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.arpeggio);
      final input = _prepare(
        target,
        <MusicalEvent>[
          _lifecycle(0, 1000, 60),
          _lifecycle(1, 1250, 64),
          _lifecycle(2, 1500, 67),
          _lifecycle(3, 1750, 72),
        ],
      );

      expect(input.evaluationProfileId, 'mvp_default_v1');
      expect(input.evaluationProfileVersion, 'v1.1');
      expect(input.mode, TargetMode.arpeggio);

      expect(_stateOf(input, EvaluationDimension.pitch),
          EvaluationDimensionState.enabled);
      expect(_available(input, EvaluationDimension.pitch), isTrue);
      expect(_stateOf(input, EvaluationDimension.timing),
          EvaluationDimensionState.enabled);
      expect(_available(input, EvaluationDimension.timing), isTrue);
      expect(_stateOf(input, EvaluationDimension.order),
          EvaluationDimensionState.enabled);
      expect(_available(input, EvaluationDimension.order), isTrue);
      expect(_stateOf(input, EvaluationDimension.ioi),
          EvaluationDimensionState.enabled);
      expect(_available(input, EvaluationDimension.ioi), isTrue);
      expect(_stateOf(input, EvaluationDimension.retrievalLatency),
          EvaluationDimensionState.enabled);
      expect(_availabilityOf(input, EvaluationDimension.retrievalLatency),
          DataAvailability.unavailable);
      expect(_stateOf(input, EvaluationDimension.simultaneity),
          EvaluationDimensionState.notApplicable);
      expect(_availabilityOf(input, EvaluationDimension.simultaneity),
          DataAvailability.unavailable);
    });
  });

  group('T3 - pitch pass-through', () {
    test('h2.7 pitch observations preserved without reinterpretation', () {
      final target = _blockTarget(<int>[60, 64, 67]);
      final observations = _extract(
        target,
        <MusicalEvent>[
          _lifecycle(0, 1000, 60),
          _lifecycle(1, 1002, 64),
          _lifecycle(2, 1004, 72),
        ],
      );
      final input = const EvaluationInputPreparer().prepare(
          observations: observations);

      expect(input.pitch.observations, hasLength(4));
      expect(
          jsonEncode(input.pitch.observations
              .map((o) => o.toMap())
              .toList(growable: false)),
          jsonEncode(observations.pitch.observations
              .map((o) => o.toMap())
              .toList(growable: false)));

      expect(input.pitch.observations[2].associationState,
          AssociationState.expectedUnmatched);
      expect(input.pitch.observations[2].expectedNoteIndex, 2);
      expect(input.pitch.observations[2].expectedPitch, 67);
      expect(input.pitch.observations[2].observedEventIndex, isNull);

      expect(input.pitch.observations[3].associationState,
          AssociationState.observedUnmatched);
      expect(input.pitch.observations[3].observedEventIndex, 2);
      expect(input.pitch.observations[3].observedPitch, 72);
      expect(input.pitch.observations[3].expectedNoteIndex, isNull);
    });
  });

  group('T4 - timing pass-through', () {
    test('raw expected/observed timing data preserved', () {
      final target = _blockTarget(<int>[60, 64, 67]);
      final observations = _extract(
        target,
        <MusicalEvent>[
          _lifecycle(0, 1000, 60),
          _lifecycle(1, 1002, 64),
          _lifecycle(2, 1004, 72),
        ],
      );
      final input = const EvaluationInputPreparer().prepare(
          observations: observations);

      expect(input.timing.observations, hasLength(4));
      expect(
          jsonEncode(input.timing.observations
              .map((o) => o.toMap())
              .toList(growable: false)),
          jsonEncode(observations.timing.observations
              .map((o) => o.toMap())
              .toList(growable: false)));

      expect(input.timing.observations[0].expectedNoteIndex, 0);
      expect(input.timing.observations[0].expectedOnsetOffsetMs, 0);
      expect(input.timing.observations[0].observedOnsetTimestampMs, 1000);

      expect(input.timing.observations[2].associationState,
          AssociationState.expectedUnmatched);
      expect(input.timing.observations[2].expectedOnsetOffsetMs, 0);
      expect(input.timing.observations[2].observedOnsetTimestampMs, isNull);

      expect(input.timing.observations[3].associationState,
          AssociationState.observedUnmatched);
      expect(input.timing.observations[3].observedOnsetTimestampMs, 1004);
      expect(input.timing.observations[3].expectedNoteIndex, isNull);
    });
  });

  group('T5 - order pass-through', () {
    test('observed sequence preserved unchanged; no reordering', () {
      final target = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.arpeggio);
      final observations = _extract(
        target,
        <MusicalEvent>[
          _lifecycle(0, 1000, 67),
          _lifecycle(1, 1250, 60),
          _lifecycle(2, 1500, 64),
          _lifecycle(3, 1750, 72),
        ],
      );
      final input = const EvaluationInputPreparer().prepare(
          observations: observations);

      expect(input.order.order, observations.order.order);

      expect(input.order.order.observedOrder.map((e) => e.index),
          <int>[0, 1, 2, 3]);
      expect(input.order.order.observedOrder.map((e) => e.pitch),
          <int>[67, 60, 64, 72]);
      expect(input.order.order.observedOrder.map((e) => e.sequencePosition),
          <int>[0, 1, 2, 3]);

      expect(input.order.order.associatedPairs
          .map((p) => p.observedSequencePosition), <int>[1, 2, 0, 3]);
      expect(input.order.order.associatedPairs
          .map((p) => p.expectedSequencePosition), <int>[0, 1, 2, 3]);
    });
  });

  group('T6 - ioi pass-through', () {
    test('signed/raw ioi values preserved', () {
      final target = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.arpeggio);
      final observations = _extract(
        target,
        <MusicalEvent>[
          _lifecycle(0, 1000, 60),
          _lifecycle(1, 1300, 64),
          _lifecycle(2, 1400, 67),
          _lifecycle(3, 1750, 72),
        ],
      );
      final input = const EvaluationInputPreparer().prepare(
          observations: observations);

      expect(
          jsonEncode(input.ioi.expected.map((e) => e.toMap()).toList()),
          jsonEncode(observations.ioi.expected.map((e) => e.toMap()).toList()));
      expect(input.ioi.expected.map((e) => e.ioiMs), <int?>[250, 250, 250]);

      expect(
          jsonEncode(input.ioi.observed.map((e) => e.toMap()).toList()),
          jsonEncode(observations.ioi.observed.map((e) => e.toMap()).toList()));
      expect(input.ioi.observed.map((e) => e.fromEventIndex), <int>[0, 1, 2]);
      expect(input.ioi.observed.map((e) => e.toEventIndex), <int>[1, 2, 3]);
      expect(input.ioi.observed.map((e) => e.ioiMs), <int?>[300, 100, 350]);
    });
  });

  group('T7 - simultaneity pass-through', () {
    test('observed timestamps/span and expected group membership preserved', () {
      final target = _blockTarget(<int>[60, 64, 67]);
      final observations = _extract(
        target,
        <MusicalEvent>[
          _lifecycle(0, 1000, 60),
          _lifecycle(1, 1047, 64),
          _lifecycle(2, 1090, 67),
        ],
      );
      final input = const EvaluationInputPreparer().prepare(
          observations: observations);

      final group = input.simultaneity.groups.single;
      expect(group.expectedGroupIndex, 0);
      expect(group.expectedOnsetOffsetMs, 0);
      expect(group.expectedMemberIndices, <int>[0, 1, 2]);
      expect(group.expectedMemberPitches, <int>[60, 64, 67]);
      expect(group.observedAssociatedEventIndices, <int>[0, 1, 2]);
      expect(group.observedOnsetTimestampsMs, <int>[1000, 1047, 1090]);
      expect(group.minObservedOnsetMs, 1000);
      expect(group.maxObservedOnsetMs, 1090);
      expect(group.observedSpanMs, 90);
      expect(group.unmatchedExpectedMemberIndices, <int>[]);
      expect(
          jsonEncode(input.simultaneity.groups.map((g) => g.toMap()).toList()),
          jsonEncode(observations.simultaneity.groups.map((g) => g.toMap()).toList()));
    });

    test('unmatched group members preserved', () {
      final target = _blockTarget(<int>[60, 64, 67]);
      final input = _prepare(
        target,
        <MusicalEvent>[
          _lifecycle(0, 1000, 60),
          _lifecycle(1, 1004, 64),
        ],
      );

      final group = input.simultaneity.groups.single;
      expect(group.observedAssociatedEventIndices, <int>[0, 1]);
      expect(group.observedOnsetTimestampsMs, <int>[1000, 1004]);
      expect(group.unmatchedExpectedMemberIndices, <int>[2]);
      expect(group.observedSpanMs, 4);
    });
  });

  group('T8 - retrieval latency unavailable', () {
    test('enabled in profile with unavailable data, never a verdict', () {
      final target = _blockTarget(<int>[60, 64, 67]);
      final observations = _extract(
        target,
        <MusicalEvent>[
          _lifecycle(0, 1000, 60),
          _lifecycle(1, 1002, 64),
          _lifecycle(2, 1004, 67),
        ],
      );
      final input = const EvaluationInputPreparer().prepare(
          observations: observations);

      expect(input.retrievalLatency.dimensionState,
          EvaluationDimensionState.enabled);
      expect(input.retrievalLatency.dataAvailability,
          DataAvailability.unavailable);

      final observation = input.retrievalLatency.observation;
      expect(observation.availability, ObservationAvailability.unavailable);
      expect(observation.reason,
          EvaluationDimensionObservationExtractor.retrievalLatencyUnavailableReason);
      expect(observation.reason, 'NO_RUNTIME_PERFORMANCE_ANCHOR');
      expect(observation.firstObservedNoteEventIndex, 0);
      expect(observation.firstObservedNoteTimestampMs, 1000);
      expect(observation.performanceAnchorTimestampMs, isNull);
      expect(observation.performanceAnchorContext, isNull);
      expect(observation.latencyDurationMs, isNull);
    });
  });

  group('T9 - unmatched expected survives', () {
    test('expected-unmatched elements and state survive', () {
      final target = _blockTarget(<int>[60, 64, 67]);
      final input = _prepare(
        target,
        <MusicalEvent>[
          _lifecycle(0, 1000, 60),
          _lifecycle(1, 1004, 64),
        ],
      );

      final unmatchedPitch = input.pitch.observations
          .where((o) => o.associationState == AssociationState.expectedUnmatched);
      expect(unmatchedPitch, hasLength(1));
      expect(unmatchedPitch.single.expectedNoteIndex, 2);
      expect(unmatchedPitch.single.expectedPitch, 67);
      expect(unmatchedPitch.single.observedEventIndex, isNull);

      final unmatchedTiming = input.timing.observations
          .where((o) => o.associationState == AssociationState.expectedUnmatched);
      expect(unmatchedTiming, hasLength(1));
      expect(unmatchedTiming.single.expectedOnsetOffsetMs, 0);
      expect(unmatchedTiming.single.observedOnsetTimestampMs, isNull);

      expect(_stateOf(input, EvaluationDimension.pitch),
          EvaluationDimensionState.enabled);
      expect(_availabilityOf(input, EvaluationDimension.pitch),
          DataAvailability.available);
    });
  });

  group('T10 - unmatched observed survives', () {
    test('observed-unmatched elements and state survive', () {
      final target = _blockTarget(<int>[60, 64, 67]);
      final input = _prepare(
        target,
        <MusicalEvent>[
          _lifecycle(0, 1000, 60),
          _lifecycle(1, 1004, 64),
          _lifecycle(2, 1008, 72),
        ],
      );

      final unmatchedPitch = input.pitch.observations
          .where((o) => o.associationState == AssociationState.observedUnmatched);
      expect(unmatchedPitch, hasLength(1));
      expect(unmatchedPitch.single.observedEventIndex, 2);
      expect(unmatchedPitch.single.observedPitch, 72);
      expect(unmatchedPitch.single.expectedNoteIndex, isNull);

      final unmatchedTiming = input.timing.observations
          .where((o) => o.associationState == AssociationState.observedUnmatched);
      expect(unmatchedTiming, hasLength(1));
      expect(unmatchedTiming.single.observedOnsetTimestampMs, 1008);
      expect(unmatchedTiming.single.expectedNoteIndex, isNull);
    });
  });

  group('T11 - integrity / ignored events', () {
    test('non-note and anomaly provenance preserved, never a judgment', () {
      final target = _blockTarget(<int>[60, 64, 67]);
      final observations = _extract(
        target,
        <MusicalEvent>[
          _anomaly(0, 990, 'duplicate_sequence'),
          _lifecycle(1, 1000, 60),
          _nonNote(2, 1002),
          _lifecycle(3, 1004, 64),
        ],
      );
      final input = const EvaluationInputPreparer().prepare(
          observations: observations);

      expect(input.ignoredNonNoteEventRefs, <int>[2]);
      expect(input.ignoredIntegrityAnomalyEventRefs, <int>[0]);
      expect(input.ignoredOtherSessionEventRefs, <int>[]);

      expect(
          input.ignoredNonNoteEventRefs,
          observations.ignoredNonNoteEventRefs);
      expect(input.ignoredIntegrityAnomalyEventRefs,
          observations.ignoredIntegrityAnomalyEventRefs);

      expect(input.pitch.observations
          .map((o) => o.observedEventIndex), <int?>[1, 3, null]);
      expect(input.timing.observations
          .map((o) => o.observedEventIndex), <int?>[1, 3, null]);
    });
  });

  group('T12 - no re-alignment', () {
    test('supplied observations are projected unchanged; no re-matching', () {
      final pitch = PitchObservations(
        availability: ObservationAvailability.available,
        observations: <PitchObservation>[
          PitchObservation(
            associationState: AssociationState.associated,
            expectedNoteIndex: 0,
            expectedPitch: 60,
            expectedGroupIndex: 0,
            observedEventIndex: 0,
            observedPitch: 64,
            observedType: MusicalSemanticType.noteLifecycle,
          ),
          PitchObservation(
            associationState: AssociationState.associated,
            expectedNoteIndex: 1,
            expectedPitch: 64,
            expectedGroupIndex: 0,
            observedEventIndex: 1,
            observedPitch: 60,
            observedType: MusicalSemanticType.noteLifecycle,
          ),
          PitchObservation(
            associationState: AssociationState.associated,
            expectedNoteIndex: 2,
            expectedPitch: 67,
            expectedGroupIndex: 0,
            observedEventIndex: 2,
            observedPitch: 67,
            observedType: MusicalSemanticType.noteLifecycle,
          ),
        ],
      );
      final timing = TimingObservations(
        availability: ObservationAvailability.available,
        observations: <TimingObservation>[
          TimingObservation(
            associationState: AssociationState.associated,
            expectedNoteIndex: 0,
            expectedOnsetOffsetMs: 0,
            observedEventIndex: 0,
            observedOnsetTimestampMs: 1000,
          ),
          TimingObservation(
            associationState: AssociationState.associated,
            expectedNoteIndex: 1,
            expectedOnsetOffsetMs: 0,
            observedEventIndex: 1,
            observedOnsetTimestampMs: 1001,
          ),
          TimingObservation(
            associationState: AssociationState.associated,
            expectedNoteIndex: 2,
            expectedOnsetOffsetMs: 0,
            observedEventIndex: 2,
            observedOnsetTimestampMs: 1002,
          ),
        ],
      );
      final observations = _manualBlock(pitch: pitch, timing: timing);
      final input = const EvaluationInputPreparer().prepare(
          observations: observations);

      // A pitch-based re-match would swap expected<->observed pitch pairs;
      // the deliberately inverted association is preserved untouched.
      expect(input.pitch.observations[0].expectedPitch, 60);
      expect(input.pitch.observations[0].observedPitch, 64);
      expect(input.pitch.observations[1].expectedPitch, 64);
      expect(input.pitch.observations[1].observedPitch, 60);
      expect(input.pitch.observations[0], observations.pitch.observations[0]);
      expect(input.pitch.observations, hasLength(3));
      expect(
          jsonEncode(input.pitch.observations
              .map((o) => o.toMap())
              .toList(growable: false)),
          jsonEncode(observations.pitch.observations
              .map((o) => o.toMap())
              .toList(growable: false)));
    });
  });

  group('T13 - policy snapshot', () {
    test('profile identity/version copied; no policy value invented', () {
      final target = _blockTarget(<int>[60, 64, 67]);
      final observations = _extract(
        target,
        <MusicalEvent>[
          _lifecycle(0, 1000, 60),
          _lifecycle(1, 1002, 64),
          _lifecycle(2, 1004, 67),
        ],
      );
      final input = const EvaluationInputPreparer().prepare(
          observations: observations);

      expect(input.policy.profileId, 'mvp_default_v1');
      expect(input.policy.profileVersion, 'v1.1');
      expect(input.policy.hasAnyDefinedPolicies, isFalse);
      expect(input.policy.pitchMs, isNull);
      expect(input.policy.timingMs, isNull);
      expect(input.policy.orderMs, isNull);
      expect(input.policy.simultaneityMs, isNull);
      expect(input.policy.ioiMs, isNull);
      expect(input.policy.retrievalLatencyMs, isNull);

      expect(input.toMap()['policy'], <String, Object?>{
        'profile_id': 'mvp_default_v1',
        'profile_version': 'v1.1',
        'pitch_ms': null,
        'timing_ms': null,
        'order_ms': null,
        'simultaneity_ms': null,
        'ioi_ms': null,
        'retrieval_latency_ms': null,
      });
    });
  });

  group('T14 - no threshold execution', () {
    test('boundary spans pass through regardless of classification', () {
      for (final span in <int>[59, 60, 61]) {
        final target = _blockTarget(<int>[60, 64, 67]);
        final observations = _extract(
          target,
          <MusicalEvent>[
            _lifecycle(0, 1000, 60),
            _lifecycle(1, 1000, 64),
            _lifecycle(2, 1000 + span, 67),
          ],
        );
        final input = const EvaluationInputPreparer().prepare(
            observations: observations);

        expect(input.simultaneity.groups.single.observedSpanMs, span);
        expect(input.simultaneity.groups.single.observedSpanMs,
            observations.simultaneity.groups.single.observedSpanMs);
        expect(_stateOf(input, EvaluationDimension.simultaneity),
            EvaluationDimensionState.enabled);
        expect(_availabilityOf(input, EvaluationDimension.simultaneity),
            DataAvailability.available);

        final keys = _collectKeys(input.toMap(), <String>{});
        expect(keys.contains('simultaneous'), isFalse);
        expect(keys.contains('not_simultaneous'), isFalse);
        expect(keys.contains('threshold'), isFalse);
        expect(keys.contains('tolerance'), isFalse);
      }
    });
  });

  group('T15 - determinism', () {
    test('identical input yields identical stable projection', () {
      final target = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.arpeggio);
      final observed = <MusicalEvent>[
        _lifecycle(0, 1000, 60),
        _lifecycle(1, 1250, 64),
        _lifecycle(2, 1500, 67),
        _lifecycle(3, 1750, 72),
      ];

      final first = _prepare(target, observed);
      final second = _prepare(target, observed);

      expect(first, second);
      expect(_project(first), _project(second));
      expect(_project(first), jsonEncode(first.toMap()));
    });
  });

  group('T16 - immutability', () {
    test('mutating source collections cannot mutate EvaluationInput', () {
      final pitchSource = <PitchObservation>[
        PitchObservation(
          associationState: AssociationState.associated,
          expectedNoteIndex: 0,
          expectedPitch: 60,
          expectedGroupIndex: 0,
          observedEventIndex: 0,
          observedPitch: 60,
          observedType: MusicalSemanticType.noteLifecycle,
        ),
        PitchObservation(
          associationState: AssociationState.associated,
          expectedNoteIndex: 1,
          expectedPitch: 64,
          expectedGroupIndex: 0,
          observedEventIndex: 1,
          observedPitch: 64,
          observedType: MusicalSemanticType.noteLifecycle,
        ),
      ];
      final timing = TimingObservations(
        availability: ObservationAvailability.unavailable,
        observations: <TimingObservation>[],
      );
      final observations = _manualBlock(
        pitch: PitchObservations(
            availability: ObservationAvailability.available, observations: pitchSource),
        timing: timing,
        ignoredNonNote: <int>[2],
        ignoredAnomaly: <int>[1],
      );
      final input = const EvaluationInputPreparer().prepare(
          observations: observations);
      final before = _project(input);

      pitchSource.add(PitchObservation(
        associationState: AssociationState.associated,
        expectedNoteIndex: 2,
        expectedPitch: 67,
        expectedGroupIndex: 0,
        observedEventIndex: 2,
        observedPitch: 67,
        observedType: MusicalSemanticType.noteLifecycle,
      ));

      expect(_project(input), before);
      expect(input.pitch.observations, hasLength(2));

      expect(
          () => input.pitch.observations.add(PitchObservation(
                associationState: AssociationState.associated,
                expectedNoteIndex: 2,
                expectedPitch: 67,
                expectedGroupIndex: 0,
                observedEventIndex: 2,
                observedPitch: 67,
                observedType: MusicalSemanticType.noteLifecycle,
              )),
          throwsUnsupportedError);
      expect(() => input.pitch.observations.clear(), throwsUnsupportedError);
      expect(
          () => input.ioi.expected.add(
              IoiEntry(fromEventIndex: 0, toEventIndex: 1, ioiMs: 250)),
          throwsUnsupportedError);
      expect(
          () => input.ioi.observed.add(
              IoiEntry(fromEventIndex: 0, toEventIndex: 1, ioiMs: 250)),
          throwsUnsupportedError);
      expect(
          () => input.simultaneity.groups.add(SimultaneityGroup(
                expectedGroupIndex: 0,
                expectedOnsetOffsetMs: 0,
                expectedMemberIndices: <int>[0, 1, 2],
                expectedMemberPitches: <int>[60, 64, 67],
                observedAssociatedEventIndices: <int>[],
                observedOnsetTimestampsMs: <int>[],
                unmatchedExpectedMemberIndices: <int>[0, 1, 2],
                minObservedOnsetMs: null,
                maxObservedOnsetMs: null,
                observedSpanMs: null,
              )),
          throwsUnsupportedError);
      expect(() => input.ignoredNonNoteEventRefs.add(5),
          throwsUnsupportedError);
      expect(() => input.ignoredIntegrityAnomalyEventRefs.add(5),
          throwsUnsupportedError);
      expect(() => input.ignoredOtherSessionEventRefs.add(5),
          throwsUnsupportedError);
    });
  });

  group('T17 - block/arpeggio applicability', () {
    test('dimension states follow mvp_default_v1 exactly for both modes', () {
      const expectedStates = <TargetMode, Map<EvaluationDimension, EvaluationDimensionState>>{
        TargetMode.block: <EvaluationDimension, EvaluationDimensionState>{
          EvaluationDimension.pitch: EvaluationDimensionState.enabled,
          EvaluationDimension.timing: EvaluationDimensionState.enabled,
          EvaluationDimension.simultaneity: EvaluationDimensionState.enabled,
          EvaluationDimension.retrievalLatency: EvaluationDimensionState.enabled,
          EvaluationDimension.order: EvaluationDimensionState.notApplicable,
          EvaluationDimension.ioi: EvaluationDimensionState.notApplicable,
        },
        TargetMode.arpeggio: <EvaluationDimension, EvaluationDimensionState>{
          EvaluationDimension.pitch: EvaluationDimensionState.enabled,
          EvaluationDimension.timing: EvaluationDimensionState.enabled,
          EvaluationDimension.order: EvaluationDimensionState.enabled,
          EvaluationDimension.ioi: EvaluationDimensionState.enabled,
          EvaluationDimension.retrievalLatency: EvaluationDimensionState.enabled,
          EvaluationDimension.simultaneity: EvaluationDimensionState.notApplicable,
        },
      };

      for (final mode in TargetMode.values) {
        final target = factory.build(
            quality: TargetQuality.major,
            root: TargetRoot.c,
            hand: TargetHand.right,
            mode: mode);
        final input = _prepare(
          target,
          <MusicalEvent>[
            for (var i = 0; i < target.notes.length; i++)
              _lifecycle(i, 1000 + i * 250, target.notes[i].pitch),
          ],
        );

        for (final dimension in EvaluationDimension.values) {
          expect(
              _stateOf(input, dimension),
              expectedStates[mode]![dimension],
              reason: '${mode.name}: ${dimension.name} state must follow the '
                  'locked profile');
          expect(_stateOf(input, dimension),
              isNot(EvaluationDimensionState.unavailable),
              reason: 'mvp_default_v1 never reports an unresolved dimension');
        }

        expect(_availabilityOf(input, EvaluationDimension.retrievalLatency),
            DataAvailability.unavailable);
        expect(_availabilityOf(input, EvaluationDimension.pitch),
            DataAvailability.available);
      }
    });
  });

  group('T18 - no evaluation leakage', () {
    test('recursive scan of keys and string values finds no concepts', () {
      final inputs = <EvaluationInput>[
        _prepare(
          factory.build(
              quality: TargetQuality.major,
              root: TargetRoot.c,
              hand: TargetHand.right,
              mode: TargetMode.block),
          <MusicalEvent>[
            _lifecycle(0, 1000, 60),
            _lifecycle(1, 1002, 64),
            _lifecycle(2, 1004, 67),
          ],
        ),
        _prepare(
          factory.build(
              quality: TargetQuality.major,
              root: TargetRoot.c,
              hand: TargetHand.right,
              mode: TargetMode.arpeggio),
          <MusicalEvent>[
            _lifecycle(0, 1000, 60),
            _lifecycle(1, 1250, 64),
            _lifecycle(2, 1500, 67),
            _lifecycle(3, 1750, 72),
          ],
        ),
        _prepare(
          _blockTarget(<int>[60, 64, 67]),
          <MusicalEvent>[
            _anomaly(0, 990, 'duplicate_sequence'),
            _lifecycle(1, 1000, 60),
            _nonNote(2, 1002),
            _lifecycle(3, 1004, 64),
            _lifecycle(4, 1008, 72),
          ],
        ),
      ];

      for (final input in inputs) {
        final keys = _collectKeys(input.toMap(), <String>{});
        for (final key in keys) {
          for (final concept in _forbiddenConcepts) {
            expect(key.contains(concept), isFalse,
                reason: 'key "$key" must not leak "$concept"');
          }
        }
        for (final value in _collectStringValues(input.toMap(), <String>[])) {
          for (final concept in _forbiddenConcepts) {
            expect(value.contains(concept), isFalse,
                reason: 'value "$value" must not leak "$concept"');
          }
        }
      }
    });
  });

  group('H2.4/H2.5/H2.6/H2.7/H2.8 integration', () {
    test('full pipeline produces canonical evaluation input without a verdict',
        () {
      final target = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.block);

      final raw = <RawMidiEvent>[
        _rawOn(0, 1000, 60),
        _rawOn(1, 1003, 64),
        _rawOn(2, 1007, 67),
        _rawOff(3, 1100, 60),
        _rawOff(4, 1103, 64),
        _rawOff(5, 1107, 67),
      ];
      final observed = const MusicalEventInterpreter()
          .interpret(const MidiNormalizer().normalizeAll(raw));

      final alignment = const StructuralAligner().align(
          target: target, sessionId: _session, observed: observed);
      final observations = const EvaluationDimensionObservationExtractor()
          .extract(target: target, observed: observed, alignment: alignment);
      final input = const EvaluationInputPreparer().prepare(
          observations: observations);

      expect(input.evaluationProfileId, 'mvp_default_v1');
      expect(input.evaluationProfileVersion, 'v1.1');
      expect(input.targetId, target.targetId);
      expect(input.sessionId, _session);
      expect(input.mode, TargetMode.block);
      expect(input.alignmentAlgorithmVersion, '1');
      expect(input.observationExtractionAlgorithmVersion, '1');
      expect(input.preparationAlgorithmVersion, '1');

      expect(_stateOf(input, EvaluationDimension.pitch),
          EvaluationDimensionState.enabled);
      expect(_stateOf(input, EvaluationDimension.simultaneity),
          EvaluationDimensionState.enabled);
      expect(_stateOf(input, EvaluationDimension.order),
          EvaluationDimensionState.notApplicable);
      expect(input.simultaneity.groups.single.observedSpanMs, 7);
      expect(input.pitch.observations, hasLength(3));
      expect(input.pitch.observations.every(
          (o) => o.associationState == AssociationState.associated), isTrue);
      expect(input.retrievalLatency.dataAvailability, DataAvailability.unavailable);
      expect(input.retrievalLatency.observation.reason,
          EvaluationDimensionObservationExtractor.retrievalLatencyUnavailableReason);
      expect(input.policy.hasAnyDefinedPolicies, isFalse);
    });
  });
}

bool _available(EvaluationInput input, EvaluationDimension dimension) =>
    _availabilityOf(input, dimension) == DataAvailability.available;

RawMidiEvent _rawOn(int seq, int ts, int note) => RawMidiEvent(
      sessionId: _session,
      deviceId: 'dev',
      connectionType: 'USB',
      seq: seq,
      appMonotonicTsMs: ts,
      messageType: RawMidiMessageType.noteOn,
      channel: 0,
      note: note,
      velocity: 90,
      rawBytes: <int>[0x90, note, 90],
    );

RawMidiEvent _rawOff(int seq, int ts, int note) => RawMidiEvent(
      sessionId: _session,
      deviceId: 'dev',
      connectionType: 'USB',
      seq: seq,
      appMonotonicTsMs: ts,
      messageType: RawMidiMessageType.noteOff,
      channel: 0,
      note: note,
      velocity: 0,
      rawBytes: <int>[0x80, note, 0],
    );