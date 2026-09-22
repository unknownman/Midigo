import 'package:flutter_test/flutter_test.dart';
import 'package:miditutor/midi/domain/evaluation_dimension_observations.dart';
import 'package:miditutor/midi/domain/evaluation_engine.dart';
import 'package:miditutor/midi/domain/evaluation_input.dart';
import 'package:miditutor/midi/domain/evaluation_policy.dart';
import 'package:miditutor/midi/domain/evaluation_result.dart';
import 'package:miditutor/midi/domain/expected_musical_target.dart';
import 'package:miditutor/midi/domain/musical_event.dart';

// ---------------------------------------------------------------------------
// Test-side builders. The engine asserts that declared dimension states match
// the resolved policy applicability, so these builders derive the states from
// MvpDefaultEvaluationProfile exactly like the H2.8 preparer does.
// ---------------------------------------------------------------------------

PitchObservation _associated(
  int expectedIndex,
  int expectedPitch,
  int observedEvent,
  int observedPitch,
) {
  return PitchObservation(
    associationState: AssociationState.associated,
    expectedNoteIndex: expectedIndex,
    expectedPitch: expectedPitch,
    expectedGroupIndex: 0,
    observedEventIndex: observedEvent,
    observedPitch: observedPitch,
    observedType: MusicalSemanticType.noteAttack,
  );
}

PitchObservation _pitchMissing(int expectedIndex, int expectedPitch) {
  return PitchObservation(
    associationState: AssociationState.expectedUnmatched,
    expectedNoteIndex: expectedIndex,
    expectedPitch: expectedPitch,
    expectedGroupIndex: 0,
    observedEventIndex: null,
    observedPitch: null,
    observedType: null,
  );
}

PitchObservation _extra(int observedEvent, int observedPitch) {
  return PitchObservation(
    associationState: AssociationState.observedUnmatched,
    expectedNoteIndex: null,
    expectedPitch: null,
    expectedGroupIndex: null,
    observedEventIndex: observedEvent,
    observedPitch: observedPitch,
    observedType: MusicalSemanticType.noteAttack,
  );
}

TimingObservation _timingAssociated(
  int expectedIndex,
  int offsetMs,
  int observedEvent,
  int observedTs,
) {
  return TimingObservation(
    associationState: AssociationState.associated,
    expectedNoteIndex: expectedIndex,
    expectedOnsetOffsetMs: offsetMs,
    observedEventIndex: observedEvent,
    observedOnsetTimestampMs: observedTs,
  );
}

TimingObservation _timingObservedUnmatched(int observedEvent, int observedTs) {
  return TimingObservation(
    associationState: AssociationState.observedUnmatched,
    expectedNoteIndex: null,
    expectedOnsetOffsetMs: null,
    observedEventIndex: observedEvent,
    observedOnsetTimestampMs: observedTs,
  );
}

OrderElement _el(int index, int pitch, int position) {
  return OrderElement(index: index, pitch: pitch, sequencePosition: position);
}

OrderAssociation _pair(
  int expectedIndex,
  int expectedPitch,
  int expectedPos,
  int observedEvent,
  int observedPitch,
  int observedPos,
) {
  return OrderAssociation(
    expectedNoteIndex: expectedIndex,
    expectedPitch: expectedPitch,
    expectedSequencePosition: expectedPos,
    observedEventIndex: observedEvent,
    observedPitch: observedPitch,
    observedSequencePosition: observedPos,
  );
}

OrderObservation _orderCorrect() {
  return OrderObservation(
    expectedOrder: [_el(0, 60, 0), _el(1, 64, 1), _el(2, 67, 2)],
    observedOrder: [_el(0, 60, 0), _el(1, 64, 1), _el(2, 67, 2)],
    associatedPairs: [
      _pair(0, 60, 0, 0, 60, 0),
      _pair(1, 64, 1, 1, 64, 1),
      _pair(2, 67, 2, 2, 67, 2),
    ],
  );
}

OrderObservation _orderWithObservedPositions(List<int> observedPositions) {
  return OrderObservation(
    expectedOrder: [_el(0, 60, 0), _el(1, 64, 1), _el(2, 67, 2)],
    observedOrder: [
      for (var i = 0; i < observedPositions.length; i++)
        _el(i, [60, 64, 67][i], i),
    ],
    associatedPairs: [
      for (var i = 0; i < observedPositions.length; i++)
        _pair(i, [60, 64, 67][i], i, i, [60, 64, 67][i], observedPositions[i]),
    ],
  );
}

IoiEntry _ioi(int from, int to, int ms) {
  return IoiEntry(fromEventIndex: from, toEventIndex: to, ioiMs: ms);
}

SimultaneityGroup _group({
  required int expectedGroupIndex,
  List<int> expectedMembers = const [0],
  List<int> expectedPitches = const [60],
  List<int> observedEvents = const [],
  List<int> observedOnsets = const [],
  List<int> unmatchedExpected = const [],
  int? span,
}) {
  return SimultaneityGroup(
    expectedGroupIndex: expectedGroupIndex,
    expectedOnsetOffsetMs: 0,
    expectedMemberIndices: expectedMembers,
    expectedMemberPitches: expectedPitches,
    observedAssociatedEventIndices: observedEvents,
    observedOnsetTimestampsMs: observedOnsets,
    unmatchedExpectedMemberIndices: unmatchedExpected,
    minObservedOnsetMs: observedOnsets.isEmpty
        ? null
        : observedOnsets.reduce(min),
    maxObservedOnsetMs: observedOnsets.isEmpty
        ? null
        : observedOnsets.reduce(max),
    observedSpanMs: span,
  );
}

int min(int a, int b) => a < b ? a : b;
int max(int a, int b) => a > b ? a : b;

RetrievalLatencyObservation _retrievalUnavailable() {
  return RetrievalLatencyObservation(
    availability: ObservationAvailability.unavailable,
    reason: 'NO_RUNTIME_PERFORMANCE_ANCHOR',
    performanceAnchorTimestampMs: null,
    performanceAnchorContext: null,
    firstObservedNoteEventIndex: null,
    firstObservedNoteTimestampMs: null,
    latencyDurationMs: null,
  );
}

PitchEvaluationInput _neutralPitch(TargetMode mode) {
  if (!MvpDefaultEvaluationProfile.instance.isDimensionEnabled(
    mode,
    EvaluationDimension.pitch,
  )) {
    return PitchEvaluationInput(
      dimensionState: EvaluationDimensionState.notApplicable,
      dataAvailability: DataAvailability.unavailable,
      observations: [],
    );
  }
  return PitchEvaluationInput(
    dimensionState: EvaluationDimensionState.enabled,
    dataAvailability: DataAvailability.available,
    observations: [_associated(0, 60, 0, 60)],
  );
}

TimingEvaluationInput _neutralTiming(TargetMode mode) {
  if (!MvpDefaultEvaluationProfile.instance.isDimensionEnabled(
    mode,
    EvaluationDimension.timing,
  )) {
    return TimingEvaluationInput(
      dimensionState: EvaluationDimensionState.notApplicable,
      dataAvailability: DataAvailability.unavailable,
      observations: [],
    );
  }
  return TimingEvaluationInput(
    dimensionState: EvaluationDimensionState.enabled,
    dataAvailability: DataAvailability.available,
    observations: [_timingAssociated(0, 0, 0, 1000)],
  );
}

OrderEvaluationInput _neutralOrder(TargetMode mode) {
  if (!MvpDefaultEvaluationProfile.instance.isDimensionEnabled(
    mode,
    EvaluationDimension.order,
  )) {
    return OrderEvaluationInput(
      dimensionState: EvaluationDimensionState.notApplicable,
      dataAvailability: DataAvailability.unavailable,
      order: OrderObservation(
        expectedOrder: [],
        observedOrder: [],
        associatedPairs: [],
      ),
    );
  }
  return OrderEvaluationInput(
    dimensionState: EvaluationDimensionState.enabled,
    dataAvailability: DataAvailability.available,
    order: _orderCorrect(),
  );
}

IoiEvaluationInput _neutralIoi(TargetMode mode) {
  if (!MvpDefaultEvaluationProfile.instance.isDimensionEnabled(
    mode,
    EvaluationDimension.ioi,
  )) {
    return IoiEvaluationInput(
      dimensionState: EvaluationDimensionState.notApplicable,
      dataAvailability: DataAvailability.unavailable,
      expected: [],
      observed: [],
    );
  }
  return IoiEvaluationInput(
    dimensionState: EvaluationDimensionState.enabled,
    dataAvailability: DataAvailability.available,
    expected: [_ioi(0, 1, 500), _ioi(1, 2, 500)],
    observed: [_ioi(0, 1, 500), _ioi(1, 2, 500)],
  );
}

SimultaneityEvaluationInput _neutralSimultaneity(TargetMode mode) {
  if (!MvpDefaultEvaluationProfile.instance.isDimensionEnabled(
    mode,
    EvaluationDimension.simultaneity,
  )) {
    return SimultaneityEvaluationInput(
      dimensionState: EvaluationDimensionState.notApplicable,
      dataAvailability: DataAvailability.unavailable,
      groups: [],
    );
  }
  return SimultaneityEvaluationInput(
    dimensionState: EvaluationDimensionState.enabled,
    dataAvailability: DataAvailability.available,
    groups: [_group(expectedGroupIndex: 0)],
  );
}

RetrievalLatencyEvaluationInput _neutralRetrieval() {
  return RetrievalLatencyEvaluationInput(
    dimensionState: EvaluationDimensionState.enabled,
    dataAvailability: DataAvailability.unavailable,
    observation: _retrievalUnavailable(),
  );
}

EvaluationInput _input(
  TargetMode mode, {
  PitchEvaluationInput? pitch,
  TimingEvaluationInput? timing,
  OrderEvaluationInput? order,
  IoiEvaluationInput? ioi,
  SimultaneityEvaluationInput? simultaneity,
  RetrievalLatencyEvaluationInput? retrievalLatency,
}) {
  return EvaluationInput(
    evaluationProfileId: MvpDefaultEvaluationProfile.profileId,
    evaluationProfileVersion: MvpDefaultEvaluationProfile.contractVersion,
    targetId: 'target-1',
    sessionId: 'session-1',
    mode: mode,
    alignmentAlgorithmVersion: '1',
    observationExtractionAlgorithmVersion: '1',
    preparationAlgorithmVersion: '1',
    pitch: pitch ?? _neutralPitch(mode),
    timing: timing ?? _neutralTiming(mode),
    order: order ?? _neutralOrder(mode),
    ioi: ioi ?? _neutralIoi(mode),
    simultaneity: simultaneity ?? _neutralSimultaneity(mode),
    retrievalLatency: retrievalLatency ?? _neutralRetrieval(),
    policy: EvaluationPolicySnapshot(
      profileId: MvpDefaultEvaluationProfile.profileId,
      profileVersion: MvpDefaultEvaluationProfile.contractVersion,
    ),
    ignoredNonNoteEventRefs: [],
    ignoredIntegrityAnomalyEventRefs: [],
    ignoredOtherSessionEventRefs: [],
  );
}

PolicyResolutionContext _ctx(
  TargetMode mode, {
  LearnerLevelKey? level = LearnerLevelKey.beginner,
}) {
  return PolicyResolutionContext(
    profileId: MvpDefaultEvaluationProfile.profileId,
    profileVersion: MvpDefaultEvaluationProfile.contractVersion,
    mode: mode,
    learnerLevel: level,
    tempoBpm: 90,
  );
}

EvaluationResult _run(
  EvaluationInput input, {
  EvaluationPolicyProfile? policy,
  LearnerLevelKey? level = LearnerLevelKey.beginner,
}) {
  return const EvaluationEngine().evaluate(
    input: input,
    policy: policy ?? EvaluationPolicyProfile.instance,
    context: _ctx(input.mode, level: level),
  );
}

EvaluatedResult _evaluated(EvaluationInput input) {
  final result = _run(input);
  expect(result, isA<EvaluatedResult>());
  return result as EvaluatedResult;
}

DimensionResult _dim(EvaluationResult result, EvaluationDimension dimension) {
  return result.dimensions.firstWhere((entry) => entry.dimension == dimension);
}

EvaluatedResult _timingResult(int deviationMs) {
  return _evaluated(
    _input(
      TargetMode.block,
      timing: TimingEvaluationInput(
        dimensionState: EvaluationDimensionState.enabled,
        dataAvailability: DataAvailability.available,
        observations: [
          _timingAssociated(0, 0, 0, 1000),
          _timingAssociated(1, 0, 1, 1000 + deviationMs),
        ],
      ),
    ),
  );
}

SeverityTier _timingSeverity(int deviationMs) {
  return _dim(_timingResult(deviationMs), EvaluationDimension.timing).severity;
}

SeverityTier _simultaneitySeverity(LearnerLevelKey level, int spanMs) {
  final result = _run(
    _input(
      TargetMode.block,
      simultaneity: SimultaneityEvaluationInput(
        dimensionState: EvaluationDimensionState.enabled,
        dataAvailability: DataAvailability.available,
        groups: [
          _group(
            expectedGroupIndex: 0,
            expectedMembers: [0, 1],
            expectedPitches: [60, 64],
            observedEvents: [0, 1],
            observedOnsets: [1000, 1000 + spanMs],
            span: spanMs,
          ),
        ],
      ),
    ),
    level: level,
  );
  return _dim(result, EvaluationDimension.simultaneity).severity;
}

SeverityTier _ioiSeverity(int deviation) {
  final result = _run(
    _input(
      TargetMode.arpeggio,
      ioi: IoiEvaluationInput(
        dimensionState: EvaluationDimensionState.enabled,
        dataAvailability: DataAvailability.available,
        expected: [_ioi(0, 1, 500), _ioi(1, 2, 500)],
        observed: [_ioi(0, 1, 500 - deviation), _ioi(1, 2, 500 + deviation)],
      ),
    ),
  );
  return _dim(result, EvaluationDimension.ioi).severity;
}

void main() {
  const engine = EvaluationEngine();

  // -------------------------------------------------------------------------
  // H2.9J result states
  // -------------------------------------------------------------------------

  test(
    'H2.9J-1 - zero associations => NOT_ENOUGH_PERFORMANCE (never 0 stars)',
    () {
      final result = _run(
        _input(
          TargetMode.block,
          pitch: PitchEvaluationInput(
            dimensionState: EvaluationDimensionState.enabled,
            dataAvailability: DataAvailability.available,
            observations: [_extra(0, 60), _extra(1, 64)],
          ),
          timing: TimingEvaluationInput(
            dimensionState: EvaluationDimensionState.enabled,
            dataAvailability: DataAvailability.available,
            observations: [
              _timingObservedUnmatched(0, 1000),
              _timingObservedUnmatched(1, 1100),
            ],
          ),
          simultaneity: SimultaneityEvaluationInput(
            dimensionState: EvaluationDimensionState.enabled,
            dataAvailability: DataAvailability.available,
            groups: [_group(expectedGroupIndex: 0)],
          ),
        ),
      );

      expect(result, isA<NotEnoughPerformanceResult>());
      expect(result.state, EvaluationResultState.notEnoughPerformance);
      expect(result.isEvaluated, isFalse);
      expect(result.toMap().containsKey('stars'), isFalse);
      expect(result.errorVector, isEmpty);
    },
  );

  test('H2.9J-2 - at least one required-note association => EVALUATED', () {
    final result = _run(_input(TargetMode.block));
    expect(result, isA<EvaluatedResult>());
    expect(result.state, EvaluationResultState.evaluated);
    expect(result.isEvaluated, isTrue);
  });

  test('H2.9J-3 - catastrophic but evaluable performance receives 0 evaluated '
      'stars (not NEP, not a failure verdict)', () {
    final result = _evaluated(
      _input(
        TargetMode.block,
        pitch: PitchEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          observations: [
            _associated(0, 60, 0, 62),
            _associated(1, 64, 1, 65),
            _associated(2, 67, 2, 69),
          ],
        ),
        timing: TimingEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          observations: [
            _timingAssociated(0, 0, 0, 1000),
            _timingAssociated(1, 0, 1, 1021),
          ],
        ),
        simultaneity: SimultaneityEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          groups: [
            _group(
              expectedGroupIndex: 0,
              expectedMembers: [0, 1],
              expectedPitches: [60, 64],
              observedEvents: [0, 1],
              observedOnsets: [1000, 1041],
              span: 41,
            ),
          ],
        ),
      ),
    );
    expect(result.stars, 0);
    expect(result.toMap()['stars'], 0);
  });

  // -------------------------------------------------------------------------
  // H2.9J identity / applicability boundary
  // -------------------------------------------------------------------------

  test('H2.9J-4 - input/policy identity mismatch fails deterministically and '
      'never falls back', () {
    final input = _input(TargetMode.block);
    expect(
      () => engine.evaluate(
        input: input,
        policy: EvaluationPolicyProfile.instance,
        context: PolicyResolutionContext(
          profileId: 'other_profile',
          profileVersion: MvpDefaultEvaluationProfile.contractVersion,
          mode: input.mode,
          learnerLevel: LearnerLevelKey.beginner,
          tempoBpm: 90,
        ),
      ),
      throwsFormatException,
    );
  });

  test('H2.9J-5 - input/context mode mismatch fails deterministically', () {
    final input = _input(TargetMode.block);
    expect(
      () => engine.evaluate(
        input: input,
        policy: EvaluationPolicyProfile.instance,
        context: _ctx(TargetMode.arpeggio),
      ),
      throwsFormatException,
    );
  });

  test('H2.9J-6 - dimension applicability that disagrees with the resolved '
      'policy fails deterministically', () {
    final input = _input(
      TargetMode.block,
      order: OrderEvaluationInput(
        dimensionState: EvaluationDimensionState.enabled,
        dataAvailability: DataAvailability.available,
        order: _orderCorrect(),
      ),
    );
    expect(() => _run(input), throwsFormatException);
  });

  test('H2.9J-7 - simultaneity evaluation without a learner level in the '
      'resolution context fails deterministically', () {
    final input = _input(TargetMode.block);
    expect(() => _run(input, level: null), throwsFormatException);
  });

  // -------------------------------------------------------------------------
  // H2.9J pitch
  // -------------------------------------------------------------------------

  test('H2.9J-8 - exact pitch match yields no pitch error and 5 stars', () {
    final result = _evaluated(_input(TargetMode.block));
    final pitch = _dim(result, EvaluationDimension.pitch);
    expect(pitch.severity, SeverityTier.none);
    expect(pitch.metrics['wrong_note_count'], 0);
    expect(
      result.errorVector.where(
        (e) => e.reasonCode == ErrorVectorReasonCode.pitchWrong,
      ),
      isEmpty,
    );
    expect(result.stars, 5);
  });

  test('H2.9J-9 - one wrong required note => MINOR', () {
    final result = _evaluated(
      _input(
        TargetMode.block,
        pitch: PitchEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          observations: [_associated(0, 60, 0, 62)],
        ),
      ),
    );
    final pitch = _dim(result, EvaluationDimension.pitch);
    expect(pitch.severity, SeverityTier.minor);
    expect(pitch.metrics['wrong_note_count'], 1);
    final entry = result.errorVector.singleWhere(
      (e) => e.reasonCode == ErrorVectorReasonCode.pitchWrong,
    );
    expect(entry.severity, SeverityTier.minor);
    expect(entry.count, 1);
    expect(entry.expectedValue, 60);
    expect(entry.observedValue, 62);
  });

  test('H2.9J-10 - two wrong required notes => MODERATE', () {
    final result = _evaluated(
      _input(
        TargetMode.block,
        pitch: PitchEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          observations: [_associated(0, 60, 0, 62), _associated(1, 64, 1, 65)],
        ),
      ),
    );
    expect(
      _dim(result, EvaluationDimension.pitch).severity,
      SeverityTier.moderate,
    );
    expect(
      _dim(result, EvaluationDimension.pitch).metrics['wrong_note_count'],
      2,
    );
  });

  test('H2.9J-11 - three or more wrong required notes => MAJOR', () {
    final result = _evaluated(
      _input(
        TargetMode.block,
        pitch: PitchEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          observations: [
            _associated(0, 60, 0, 62),
            _associated(1, 64, 1, 65),
            _associated(2, 67, 2, 69),
          ],
        ),
      ),
    );
    expect(
      _dim(result, EvaluationDimension.pitch).severity,
      SeverityTier.major,
    );
  });

  test('H2.9J-12 - one extra note is NEGLIGIBLE and never trims', () {
    final result = _evaluated(
      _input(
        TargetMode.block,
        pitch: PitchEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          observations: [_associated(0, 60, 0, 60), _extra(1, 72)],
        ),
      ),
    );
    expect(_dim(result, EvaluationDimension.pitch).severity, SeverityTier.none);
    final entry = result.errorVector.singleWhere(
      (e) => e.reasonCode == ErrorVectorReasonCode.pitchExtra,
    );
    expect(entry.severity, SeverityTier.negligible);
    expect(result.stars, 5);
  });

  test('H2.9J-13 - two extra notes => MINOR with a whole-star trim', () {
    final result = _evaluated(
      _input(
        TargetMode.block,
        pitch: PitchEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          observations: [
            _associated(0, 60, 0, 60),
            _extra(1, 72),
            _extra(2, 74),
          ],
        ),
      ),
    );
    final entry = result.errorVector.singleWhere(
      (e) => e.reasonCode == ErrorVectorReasonCode.pitchExtra,
    );
    expect(entry.severity, SeverityTier.minor);
    expect(result.stars, 4);
  });

  test('H2.9J-14 - three or more extra notes => MODERATE', () {
    final result = _evaluated(
      _input(
        TargetMode.block,
        pitch: PitchEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          observations: [
            _associated(0, 60, 0, 60),
            _extra(1, 72),
            _extra(2, 74),
            _extra(3, 76),
          ],
        ),
      ),
    );
    final entry = result.errorVector.singleWhere(
      (e) => e.reasonCode == ErrorVectorReasonCode.pitchExtra,
    );
    expect(entry.severity, SeverityTier.moderate);
    expect(result.stars, 3);
  });

  test('H2.9J-15 - a missing required note is a separate, non-severity error '
      'and applies the ceiling only during aggregation', () {
    final result = _evaluated(
      _input(
        TargetMode.block,
        pitch: PitchEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          observations: [_associated(0, 60, 0, 60), _pitchMissing(1, 64)],
        ),
      ),
    );
    expect(_dim(result, EvaluationDimension.pitch).severity, SeverityTier.none);
    expect(
      _dim(result, EvaluationDimension.pitch).metrics['missing_note_count'],
      1,
    );
    final entry = result.errorVector.singleWhere(
      (e) => e.reasonCode == ErrorVectorReasonCode.pitchMissing,
    );
    expect(entry.severity, SeverityTier.none);
    expect(result.stars, 4);
  });

  test('H2.9J-16 - no rematching: an unassociated note stays extra, never a '
      'pitch mismatch', () {
    final result = _evaluated(
      _input(
        TargetMode.block,
        pitch: PitchEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          observations: [_associated(0, 60, 0, 60), _extra(1, 64)],
        ),
      ),
    );
    expect(
      _dim(result, EvaluationDimension.pitch).metrics['wrong_note_count'],
      0,
    );
    expect(
      result.errorVector.any(
        (e) => e.reasonCode == ErrorVectorReasonCode.pitchWrong,
      ),
      isFalse,
    );
    expect(
      result.errorVector.any(
        (e) => e.reasonCode == ErrorVectorReasonCode.pitchExtra,
      ),
      isTrue,
    );
  });

  // -------------------------------------------------------------------------
  // H2.9J timing
  // -------------------------------------------------------------------------

  test('H2.9J-17 - timing severity below/at/above the 4/8/15 bands', () {
    expect(_timingSeverity(19), SeverityTier.negligible);
    expect(_timingSeverity(20), SeverityTier.negligible);
    expect(_timingSeverity(21), SeverityTier.minor);
    expect(_timingSeverity(40), SeverityTier.minor);
    expect(_timingSeverity(41), SeverityTier.moderate);
    expect(_timingSeverity(75), SeverityTier.moderate);
    expect(_timingSeverity(76), SeverityTier.major);
  });

  test('H2.9J-18 - the first observed note is the start anchor and its own '
      'lateness is never penalised', () {
    final result = _evaluated(
      _input(
        TargetMode.block,
        timing: TimingEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          observations: [
            _timingAssociated(0, 0, 0, 9000),
            _timingAssociated(1, 0, 1, 9020),
          ],
        ),
      ),
    );
    final timing = _dim(result, EvaluationDimension.timing);
    expect(timing.metrics['anchor_note_index'], 0);
    expect(timing.metrics['deviating_note_count'], 1);
    // The anchor's observed timestamp is irrelevant by construction, so the
    // relative +20 ms deviation is the only thing graded (negligible).
    expect(timing.severity, SeverityTier.negligible);
  });

  test('H2.9J-19 - tolerance and severity are distinct policy concepts', () {
    final result = _timingResult(21);
    final timing = _dim(result, EvaluationDimension.timing);
    expect(timing.severity, SeverityTier.minor);
    expect(timing.metrics['reference_interval_ms'], 500);
    expect(timing.metrics['reference_tolerance_ms'], 25);
  });

  test('H2.9J-20 - a timing error carries the raw signed deviation and an '
      'early/late reason code', () {
    final late = _evaluated(
      _input(
        TargetMode.block,
        timing: TimingEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          observations: [
            _timingAssociated(0, 0, 0, 1000),
            _timingAssociated(1, 0, 1, 1076),
          ],
        ),
      ),
    );
    final lateEntry = late.errorVector.singleWhere(
      (e) => e.reasonCode == ErrorVectorReasonCode.timingLate,
    );
    expect(lateEntry.signedDelta, 76);
    expect(lateEntry.severity, SeverityTier.major);

    final early = _evaluated(
      _input(
        TargetMode.block,
        timing: TimingEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          observations: [
            _timingAssociated(0, 0, 0, 1000),
            _timingAssociated(1, 0, 1, 924),
          ],
        ),
      ),
    );
    final earlyEntry = early.errorVector.singleWhere(
      (e) => e.reasonCode == ErrorVectorReasonCode.timingEarly,
    );
    expect(earlyEntry.signedDelta, -76);
    expect(earlyEntry.severity, SeverityTier.major);
  });

  test('H2.9J-21 - notes without prescribed timing do not participate', () {
    final result = _evaluated(
      _input(
        TargetMode.block,
        timing: TimingEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          observations: [
            _timingAssociated(0, 0, 0, 1000),
            TimingObservation(
              associationState: AssociationState.associated,
              expectedNoteIndex: 1,
              expectedOnsetOffsetMs: null,
              observedEventIndex: 1,
              observedOnsetTimestampMs: 1234,
            ),
          ],
        ),
      ),
    );
    final timing = _dim(result, EvaluationDimension.timing);
    expect(timing.metrics['evaluated_note_count'], 1);
    expect(timing.severity, SeverityTier.none);
  });

  // -------------------------------------------------------------------------
  // H2.9J order
  // -------------------------------------------------------------------------

  OrderEvaluationInput orderInput(OrderObservation observation) {
    return OrderEvaluationInput(
      dimensionState: EvaluationDimensionState.enabled,
      dataAvailability: DataAvailability.available,
      order: observation,
    );
  }

  test('H2.9J-22 - correct order => NONE', () {
    final result = _evaluated(
      _input(TargetMode.arpeggio, order: orderInput(_orderCorrect())),
    );
    expect(_dim(result, EvaluationDimension.order).severity, SeverityTier.none);
    expect(
      _dim(result, EvaluationDimension.order).metrics['inversion_count'],
      0,
    );
  });

  test('H2.9J-23 - adjacent inversion => MINOR; partial => MODERATE; full '
      'reversal => MAJOR', () {
    final adjacent = _orderWithObservedPositions([1, 0, 2]);
    final partial = _orderWithObservedPositions([2, 0, 1]);
    final full = _orderWithObservedPositions([2, 1, 0]);

    final adjacentResult = _evaluated(
      _input(TargetMode.arpeggio, order: orderInput(adjacent)),
    );
    expect(
      _dim(adjacentResult, EvaluationDimension.order).severity,
      SeverityTier.minor,
    );
    expect(
      adjacentResult.errorVector.any(
        (e) => e.reasonCode == ErrorVectorReasonCode.orderAdjacentInversion,
      ),
      isTrue,
    );

    final partialResult = _evaluated(
      _input(TargetMode.arpeggio, order: orderInput(partial)),
    );
    expect(
      _dim(partialResult, EvaluationDimension.order).severity,
      SeverityTier.moderate,
    );
    expect(
      partialResult.errorVector.any(
        (e) => e.reasonCode == ErrorVectorReasonCode.orderPartialInversion,
      ),
      isTrue,
    );

    final fullResult = _evaluated(
      _input(TargetMode.arpeggio, order: orderInput(full)),
    );
    expect(
      _dim(fullResult, EvaluationDimension.order).severity,
      SeverityTier.major,
    );
    expect(
      fullResult.errorVector.any(
        (e) => e.reasonCode == ErrorVectorReasonCode.orderFullReversal,
      ),
      isTrue,
    );
  });

  test('H2.9J-24 - order is independent of pitch correctness and reports '
      'severity so policy decides star impact', () {
    final result = _evaluated(
      _input(
        TargetMode.arpeggio,
        pitch: PitchEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          observations: [
            _associated(0, 60, 0, 62),
            _associated(1, 64, 1, 64),
            _associated(2, 67, 2, 67),
          ],
        ),
        order: orderInput(_orderWithObservedPositions([1, 0, 2])),
      ),
    );
    expect(
      _dim(result, EvaluationDimension.pitch).severity,
      SeverityTier.minor,
    );
    expect(
      _dim(result, EvaluationDimension.order).severity,
      SeverityTier.minor,
    );
    // Worst error (pitch single wrong => MINOR) establishes base 4; the order
    // MINOR is an additional trim source => 3. No ad-hoc order subtraction.
    expect(result.stars, 3);
  });

  // -------------------------------------------------------------------------
  // H2.9J IOI
  // -------------------------------------------------------------------------

  test('H2.9J-25 - IOI severity below/at/above the 5/10/20 bands, compared '
      'against the learner mean', () {
    expect(_ioiSeverity(20), SeverityTier.negligible);
    expect(_ioiSeverity(25), SeverityTier.negligible);
    expect(_ioiSeverity(26), SeverityTier.minor);
    expect(_ioiSeverity(50), SeverityTier.minor);
    expect(_ioiSeverity(51), SeverityTier.moderate);
    expect(_ioiSeverity(99), SeverityTier.moderate);
    expect(_ioiSeverity(100), SeverityTier.moderate);
    expect(_ioiSeverity(101), SeverityTier.major);
  });

  test('H2.9J-26 - IOI carries the learner mean and interval detail, and does '
      'not double-charge Timing', () {
    final result = _evaluated(
      _input(
        TargetMode.arpeggio,
        ioi: IoiEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          expected: [_ioi(0, 1, 500), _ioi(1, 2, 500)],
          observed: [_ioi(0, 1, 474), _ioi(1, 2, 526)],
        ),
      ),
    );
    final ioi = _dim(result, EvaluationDimension.ioi);
    expect(ioi.severity, SeverityTier.minor);
    expect(ioi.metrics['mean_interval_ms'], 500);
    final entry = result.errorVector.singleWhere(
      (e) => e.reasonCode == ErrorVectorReasonCode.ioiInconsistent,
    );
    expect(entry.expectedValue, 500);
    expect(entry.signedDelta, 26);
    expect(EvaluationPolicyProfile.instance.ioi.doubleChargesTiming, isFalse);
  });

  test('H2.9J-27 - a perfect IOI never triggers anyway, even when timing is '
      'bad; the dimensions stay distinct', () {
    final result = _evaluated(
      _input(
        TargetMode.arpeggio,
        timing: TimingEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          observations: [
            _timingAssociated(0, 0, 0, 1000),
            _timingAssociated(1, 0, 1, 1100),
          ],
        ),
        ioi: IoiEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          expected: [_ioi(0, 1, 500), _ioi(1, 2, 500)],
          observed: [_ioi(0, 1, 500), _ioi(1, 2, 500)],
        ),
      ),
    );
    expect(
      _dim(result, EvaluationDimension.timing).severity,
      SeverityTier.major,
    );
    expect(_dim(result, EvaluationDimension.ioi).severity, SeverityTier.none);
    expect(
      result.errorVector.any(
        (e) => e.reasonCode == ErrorVectorReasonCode.ioiInconsistent,
      ),
      isFalse,
    );
  });

  // -------------------------------------------------------------------------
  // H2.9J simultaneity
  // -------------------------------------------------------------------------

  test('H2.9J-28 - beginner simultaneity boundaries below/at/above 40/80', () {
    expect(
      _simultaneitySeverity(LearnerLevelKey.beginner, 39),
      SeverityTier.negligible,
    );
    expect(
      _simultaneitySeverity(LearnerLevelKey.beginner, 40),
      SeverityTier.negligible,
    );
    expect(
      _simultaneitySeverity(LearnerLevelKey.beginner, 41),
      SeverityTier.minor,
    );
    expect(
      _simultaneitySeverity(LearnerLevelKey.beginner, 80),
      SeverityTier.minor,
    );
    expect(
      _simultaneitySeverity(LearnerLevelKey.beginner, 81),
      SeverityTier.major,
    );
  });

  test(
    'H2.9J-29 - intermediate simultaneity boundaries below/at/above 30/60',
    () {
      expect(
        _simultaneitySeverity(LearnerLevelKey.intermediate, 29),
        SeverityTier.negligible,
      );
      expect(
        _simultaneitySeverity(LearnerLevelKey.intermediate, 30),
        SeverityTier.negligible,
      );
      expect(
        _simultaneitySeverity(LearnerLevelKey.intermediate, 31),
        SeverityTier.minor,
      );
      expect(
        _simultaneitySeverity(LearnerLevelKey.intermediate, 60),
        SeverityTier.minor,
      );
      expect(
        _simultaneitySeverity(LearnerLevelKey.intermediate, 61),
        SeverityTier.major,
      );
    },
  );

  test('H2.9J-30 - advanced simultaneity boundaries below/at/above 20/40', () {
    expect(
      _simultaneitySeverity(LearnerLevelKey.advanced, 19),
      SeverityTier.negligible,
    );
    expect(
      _simultaneitySeverity(LearnerLevelKey.advanced, 20),
      SeverityTier.negligible,
    );
    expect(
      _simultaneitySeverity(LearnerLevelKey.advanced, 21),
      SeverityTier.minor,
    );
    expect(
      _simultaneitySeverity(LearnerLevelKey.advanced, 40),
      SeverityTier.minor,
    );
    expect(
      _simultaneitySeverity(LearnerLevelKey.advanced, 41),
      SeverityTier.major,
    );
  });

  test('H2.9J-31 - a missing chord member does not invalidate simultaneity; '
      'the missing note is evaluated separately', () {
    final result = _evaluated(
      _input(
        TargetMode.block,
        pitch: PitchEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          observations: [
            _associated(0, 60, 0, 60),
            _associated(1, 64, 1, 64),
            _pitchMissing(2, 67),
          ],
        ),
        simultaneity: SimultaneityEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          groups: [
            _group(
              expectedGroupIndex: 0,
              expectedMembers: [0, 1, 2],
              expectedPitches: [60, 64, 67],
              observedEvents: [0, 1],
              observedOnsets: [1000, 1010],
              unmatchedExpected: [2],
              span: 10,
            ),
          ],
        ),
      ),
    );
    expect(
      _dim(result, EvaluationDimension.simultaneity).severity,
      SeverityTier.negligible,
    );
    expect(
      _dim(result, EvaluationDimension.pitch).metrics['missing_note_count'],
      1,
    );
    expect(
      result.errorVector.any(
        (e) => e.reasonCode == ErrorVectorReasonCode.pitchMissing,
      ),
      isTrue,
    );
  });

  test(
    'H2.9J-32 - extra notes are excluded from required-note simultaneity',
    () {
      final result = _evaluated(
        _input(
          TargetMode.block,
          pitch: PitchEvaluationInput(
            dimensionState: EvaluationDimensionState.enabled,
            dataAvailability: DataAvailability.available,
            observations: [
              _associated(0, 60, 0, 60),
              _associated(1, 64, 1, 64),
              _extra(2, 72),
            ],
          ),
          simultaneity: SimultaneityEvaluationInput(
            dimensionState: EvaluationDimensionState.enabled,
            dataAvailability: DataAvailability.available,
            groups: [
              _group(
                expectedGroupIndex: 0,
                expectedMembers: [0, 1],
                expectedPitches: [60, 64],
                observedEvents: [0, 1],
                observedOnsets: [1000, 1005],
                span: 5,
              ),
            ],
          ),
        ),
      );
      expect(
        _dim(result, EvaluationDimension.simultaneity).severity,
        SeverityTier.negligible,
      );
      expect(
        EvaluationPolicyProfile.instance.simultaneity.excludesExtraNotes,
        isTrue,
      );
      expect(
        result.errorVector
            .singleWhere(
              (e) => e.reasonCode == ErrorVectorReasonCode.simultaneitySpread,
            )
            .count,
        1,
      );
    },
  );

  test('H2.9J-33 - simultaneity with fewer than two observed members is not '
      'graded at all', () {
    final result = _evaluated(
      _input(
        TargetMode.block,
        simultaneity: SimultaneityEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          groups: [_group(expectedGroupIndex: 0)],
        ),
      ),
    );
    expect(
      _dim(result, EvaluationDimension.simultaneity).severity,
      SeverityTier.none,
    );
    expect(
      _dim(result, EvaluationDimension.simultaneity).metrics['group_count'],
      1,
    );
    expect(
      _dim(
        result,
        EvaluationDimension.simultaneity,
      ).metrics['spread_group_count'],
      0,
    );
  });

  test('H2.9J-34 - arpeggio => simultaneity is NOT_APPLICABLE', () {
    final result = _evaluated(_input(TargetMode.arpeggio));
    expect(
      _dim(result, EvaluationDimension.simultaneity).state,
      EvaluationDimensionState.notApplicable,
    );
    expect(
      _dim(result, EvaluationDimension.simultaneity).severity,
      SeverityTier.none,
    );
  });

  // -------------------------------------------------------------------------
  // H2.9J retrieval latency
  // -------------------------------------------------------------------------

  test('H2.9J-35 - retrieval latency enabled + unavailable yields no severity '
      'and no star impact', () {
    final result = _evaluated(_input(TargetMode.block));
    final retrieval = _dim(result, EvaluationDimension.retrievalLatency);
    expect(retrieval.state, EvaluationDimensionState.enabled);
    expect(retrieval.dataAvailability, DataAvailability.unavailable);
    expect(retrieval.severity, SeverityTier.none);
    final entry = result.errorVector.singleWhere(
      (e) => e.reasonCode == ErrorVectorReasonCode.retrievalLatencyUnavailable,
    );
    expect(entry.severity, SeverityTier.none);
    expect(result.stars, 5);
  });

  // -------------------------------------------------------------------------
  // H2.9J missing-note ceilings
  // -------------------------------------------------------------------------

  test(
    'H2.9J-36 - missing-note ceilings 0/1/2/3/4/5+ cap at none/4/3/2/1/1',
    () {
      EvaluatedResult build(int missing) {
        return _evaluated(
          _input(
            TargetMode.block,
            pitch: PitchEvaluationInput(
              dimensionState: EvaluationDimensionState.enabled,
              dataAvailability: DataAvailability.available,
              observations: [
                _associated(0, 60, 0, 60),
                for (var i = 1; i <= missing; i++) _pitchMissing(i, 60 + i * 4),
              ],
            ),
          ),
        );
      }

      expect(build(0).stars, 5);
      expect(build(1).stars, 4);
      expect(build(2).stars, 3);
      expect(build(3).stars, 2);
      expect(build(4).stars, 1);
      expect(build(5).stars, 1);
    },
  );

  test('H2.9J-37 - the missing-note ceiling is applied after base and trims '
      'and only ever reduces or holds quality', () {
    // Timing MINOR gives base 4; two missing notes cap quality at 3.
    final result = _evaluated(
      _input(
        TargetMode.block,
        pitch: PitchEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          observations: [
            _associated(0, 60, 0, 60),
            _pitchMissing(1, 64),
            _pitchMissing(2, 67),
          ],
        ),
        timing: TimingEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          observations: [
            _timingAssociated(0, 0, 0, 1000),
            _timingAssociated(1, 0, 1, 1021),
          ],
        ),
      ),
    );
    expect(result.stars, 3);

    // The same performance without the missing notes keeps base 4.
    final noMissing = _evaluated(
      _input(
        TargetMode.block,
        timing: TimingEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          observations: [
            _timingAssociated(0, 0, 0, 1000),
            _timingAssociated(1, 0, 1, 1021),
          ],
        ),
      ),
    );
    expect(noMissing.stars, 4);
  });

  // -------------------------------------------------------------------------
  // H2.9J star aggregation
  // -------------------------------------------------------------------------

  test('H2.9J-38 - base stars follow the worst severity: 5/4/3/2', () {
    expect(_evaluated(_input(TargetMode.block)).stars, 5);
    expect(_timingResult(21).stars, 4);
    expect(_timingResult(41).stars, 3);
    expect(_timingResult(76).stars, 2);
  });

  test('H2.9J-39 - the worst error never trims itself; an additional '
      'MINOR trim is a whole star', () {
    final result = _evaluated(
      _input(
        TargetMode.block,
        simultaneity: SimultaneityEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          groups: [
            _group(
              expectedGroupIndex: 0,
              expectedMembers: [0, 1],
              expectedPitches: [60, 64],
              observedEvents: [0, 1],
              observedOnsets: [1000, 1041],
              span: 41,
            ),
          ],
        ),
      ),
    );
    // Simultaneity MINOR is the worst and only source => base 4, no trim.
    expect(result.stars, 4);
  });

  test('H2.9J-40 - two tied MINOR dimensions yield one trim', () {
    final result = _evaluated(
      _input(
        TargetMode.block,
        timing: TimingEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          observations: [
            _timingAssociated(0, 0, 0, 1000),
            _timingAssociated(1, 0, 1, 1021),
          ],
        ),
        simultaneity: SimultaneityEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          groups: [
            _group(
              expectedGroupIndex: 0,
              expectedMembers: [0, 1],
              expectedPitches: [60, 64],
              observedEvents: [0, 1],
              observedOnsets: [1000, 1041],
              span: 41,
            ),
          ],
        ),
      ),
    );
    expect(result.stars, 3);
  });

  test('H2.9J-41 - trims are capped at the configured maximum of two', () {
    final result = _evaluated(
      _input(
        TargetMode.arpeggio,
        pitch: PitchEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          observations: [
            _associated(0, 60, 0, 62),
            _associated(1, 64, 1, 65),
            _associated(2, 67, 2, 69),
          ],
        ),
        timing: TimingEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          observations: [
            _timingAssociated(0, 0, 0, 1000),
            _timingAssociated(1, 0, 1, 1021),
          ],
        ),
        order: orderInput(_orderWithObservedPositions([1, 0, 2])),
        ioi: IoiEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          expected: [_ioi(0, 1, 500), _ioi(1, 2, 500)],
          observed: [_ioi(0, 1, 474), _ioi(1, 2, 526)],
        ),
      ),
    );
    // Pitch MAJOR base 2; timing/order/IOI would all trim but the cap is 2.
    expect(result.stars, 0);
  });

  test('H2.9J-42 - NEGLIGIBLE errors never trim', () {
    final result = _evaluated(
      _input(
        TargetMode.block,
        timing: TimingEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          observations: [
            _timingAssociated(0, 0, 0, 1000),
            _timingAssociated(1, 0, 1, 1020),
          ],
        ),
      ),
    );
    expect(result.stars, 5);
  });

  test('H2.9J-43 - a NEGLIGIBLE extra isolated error cannot reduce stars', () {
    final result = _evaluated(
      _input(
        TargetMode.block,
        pitch: PitchEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          observations: [_associated(0, 60, 0, 60), _extra(1, 72)],
        ),
      ),
    );
    expect(result.stars, 5);
  });

  // -------------------------------------------------------------------------
  // H2.9J NOT_APPLICABLE vs UNAVAILABLE (neither penalises)
  // -------------------------------------------------------------------------

  test('H2.9J-44 - NOT_APPLICABLE dimensions (block order/IOI) never '
      'contribute severity', () {
    final result = _evaluated(_input(TargetMode.block));
    expect(
      _dim(result, EvaluationDimension.order).state,
      EvaluationDimensionState.notApplicable,
    );
    expect(
      _dim(result, EvaluationDimension.ioi).state,
      EvaluationDimensionState.notApplicable,
    );
    expect(_dim(result, EvaluationDimension.order).severity, SeverityTier.none);
    expect(_dim(result, EvaluationDimension.ioi).severity, SeverityTier.none);
    expect(result.stars, 5);
  });

  test('H2.9J-45 - UNAVAILABLE data availability never creates a penalty', () {
    final result = _evaluated(
      _input(TargetMode.block, retrievalLatency: _neutralRetrieval()),
    );
    expect(result.stars, 5);
  });

  // -------------------------------------------------------------------------
  // H2.9J determinism, immutability and architectural isolation
  // -------------------------------------------------------------------------

  test('H2.9J-46 - identical input/policy/context always yields an identical '
      'result including serialisation', () {
    final input = _input(
      TargetMode.block,
      pitch: PitchEvaluationInput(
        dimensionState: EvaluationDimensionState.enabled,
        dataAvailability: DataAvailability.available,
        observations: [
          _associated(0, 60, 0, 62),
          _pitchMissing(1, 64),
          _extra(2, 72),
        ],
      ),
      timing: TimingEvaluationInput(
        dimensionState: EvaluationDimensionState.enabled,
        dataAvailability: DataAvailability.available,
        observations: [
          _timingAssociated(0, 0, 0, 1000),
          _timingAssociated(1, 0, 1, 1021),
        ],
      ),
    );
    final policy = EvaluationPolicyProfile.instance;
    final context = _ctx(TargetMode.block);

    Map<String, Object?>? firstMap;
    for (var i = 0; i < 25; i++) {
      final result = engine.evaluate(
        input: input,
        policy: policy,
        context: context,
      );
      final serialized = result.toMap();
      if (i == 0) {
        firstMap = serialized;
      } else {
        // Determinism is meaningful at the serialized-value level: the engine
        // builds fresh immutable value objects per run, so value equality is
        // asserted on the deep-equal serialization.
        expect(serialized, firstMap);
      }
    }
  });

  test('H2.9J-47 - evaluating does not mutate the input', () {
    final input = _input(
      TargetMode.block,
      pitch: PitchEvaluationInput(
        dimensionState: EvaluationDimensionState.enabled,
        dataAvailability: DataAvailability.available,
        observations: [
          _associated(0, 60, 0, 62),
          _pitchMissing(1, 64),
          _extra(2, 72),
        ],
      ),
    );
    final before = input.toMap();
    for (var i = 0; i < 5; i++) {
      _run(input);
    }
    expect(input.toMap(), before);
  });

  test('H2.9J-48 - evaluating does not mutate the policy', () {
    final policy = EvaluationPolicyProfile.instance;
    final before = policy.toMap();
    final input = _input(TargetMode.block);
    for (var i = 0; i < 5; i++) {
      _run(input, policy: policy);
    }
    expect(policy.toMap(), before);
  });

  test('H2.9J-49 - the result is a sealed EvaluationResult with exactly six '
      'dimension results and no external learning-state surface', () {
    final result = _evaluated(_input(TargetMode.block));
    expect(result.dimensions, hasLength(6));
    expect(
      result.dimensions.map((d) => d.dimension),
      EvaluationDimension.values,
    );
    // The engine exposes no evidence/mastery/scheduler/session vocabulary.
    final serialized = result.toMap().toString();
    for (final forbidden in [
      'mastery',
      'evidence',
      'scheduler',
      'priority',
      'session_',
      'progress',
    ]) {
      expect(
        serialized.toLowerCase().contains(forbidden),
        isFalse,
        reason: 'result must not carry $forbidden semantics',
      );
    }
  });

  // -------------------------------------------------------------------------
  // H2.9J invariant battery (section 23)
  // -------------------------------------------------------------------------

  test('H2.9J-50 - invariants 1..15 hold across representative inputs', () {
    final inputs = <EvaluationInput>[
      _input(TargetMode.block),
      _input(
        TargetMode.block,
        pitch: PitchEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          observations: [_associated(0, 60, 0, 62)],
        ),
      ),
      _input(
        TargetMode.block,
        pitch: PitchEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          observations: [
            _associated(0, 60, 0, 60),
            _pitchMissing(1, 64),
            _pitchMissing(2, 67),
          ],
        ),
      ),
      _input(
        TargetMode.block,
        pitch: PitchEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          observations: [_extra(0, 60)],
        ),
      ),
      _input(
        TargetMode.arpeggio,
        order: orderInput(_orderWithObservedPositions([2, 1, 0])),
        ioi: IoiEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          expected: [_ioi(0, 1, 500), _ioi(1, 2, 500)],
          observed: [_ioi(0, 1, 400), _ioi(1, 2, 600)],
        ),
      ),
    ];

    for (final input in inputs) {
      final result = _run(input);

      if (result is EvaluatedResult) {
        // 1: stars always within 0..5 for EVALUATED.
        expect(result.stars, inInclusiveRange(0, 5));
        // 15: >=1 association produced an EVALUATED result.
        final associations = input.pitch.observations
            .where((o) => o.associationState == AssociationState.associated)
            .length;
        expect(associations, greaterThanOrEqualTo(1));
      } else {
        // 2: NEP never carries a star value.
        expect(result is NotEnoughPerformanceResult, isTrue);
        expect(result.toMap().containsKey('stars'), isFalse);
        // 14: zero associations here could not turn into 0-star EVALUATED.
        final associations = input.pitch.observations
            .where((o) => o.associationState == AssociationState.associated)
            .length;
        expect(associations, 0);
      }

      // 3: N/A dimensions never contribute severity.
      for (final dimension in result.dimensions) {
        if (dimension.state == EvaluationDimensionState.notApplicable) {
          expect(dimension.severity, SeverityTier.none);
        }
      }

      // 4 / 5 / 6 / 7 / 8 are exercised by dedicated tests above.

      // 9: deterministic within this run (single evaluation).
      // 10: error vector entries carry only descriptive fields (no stars,
      //     mastery, scheduler, evidence or priority vocabulary).
      for (final entry in result.errorVector) {
        expect(entry.dimension, isA<EvaluationDimension>());
        final serialized = entry.toMap();
        final forbidden = <String>[
          'stars',
          'trim',
          'mastery',
          'scheduler',
          'evidence',
          'priority',
        ];
        for (final key in serialized.keys) {
          expect(forbidden.contains(key), isFalse, reason: 'key: $key');
        }
        expect(entry.toString().contains('mastery'), isFalse);
      }

      // 13: no aggregate PASS/FAIL anywhere.
      expect(
        result.toMap().keys.any((k) => k == 'pass' || k == 'fail'),
        isFalse,
      );
    }
  });

  // -------------------------------------------------------------------------
  // H2.9J policy consumption: the engine grades through policy, never through
  // duplicated constants.
  // -------------------------------------------------------------------------

  test('H2.9J-51 - a modified timing policy changes the result for identical '
      'input, proving grading reads the policy', () {
    final base = EvaluationPolicyProfile.instance;
    final stricterBands = SeverityBandTable(
      bands: [
        SeverityBand(
          severity: SeverityTier.negligible,
          upperBound: 1,
          upperBoundary: PolicyBoundary.inclusive,
        ),
        SeverityBand(
          severity: SeverityTier.minor,
          upperBound: 3,
          upperBoundary: PolicyBoundary.inclusive,
        ),
        SeverityBand(
          severity: SeverityTier.moderate,
          upperBound: 5,
          upperBoundary: PolicyBoundary.inclusive,
        ),
        SeverityBand(severity: SeverityTier.major),
      ],
    );
    stricterBands.validate();

    final stricter = EvaluationPolicyProfile(
      profileIdValue: base.profileIdValue,
      contractVersionValue: base.contractVersionValue,
      policyVersionValue: base.policyVersionValue,
      provenance: base.provenance,
      pitch: base.pitch,
      timing: TimingPolicySpec(
        unavailableHandling: base.timing.unavailableHandling,
        firstNoteIsStartReference: base.timing.firstNoteIsStartReference,
        firstNoteLatenessPenalized: base.timing.firstNoteLatenessPenalized,
        tightensWithTempo: base.timing.tightensWithTempo,
        tempoDependencyKind: base.timing.tempoDependencyKind,
        baseTolerance: base.timing.baseTolerance,
        toleranceRatio: base.timing.toleranceRatio,
        severityBands: stricterBands,
        severityReferenceIntervalMs: base.timing.severityReferenceIntervalMs,
      ),
      order: base.order,
      simultaneity: base.simultaneity,
      ioi: base.ioi,
      retrievalLatency: base.retrievalLatency,
      stars: base.stars,
      evaluability: base.evaluability,
      resultState: base.resultState,
      errorVector: base.errorVector,
      applicability: base.applicability,
      notApplicableHandling: base.notApplicableHandling,
      appliedResolutionDepth: base.appliedResolutionDepth,
      unresolvedPrecedenceLayers: base.unresolvedPrecedenceLayers,
    );

    final input = _input(
      TargetMode.block,
      timing: TimingEvaluationInput(
        dimensionState: EvaluationDimensionState.enabled,
        dataAvailability: DataAvailability.available,
        observations: [
          _timingAssociated(0, 0, 0, 1000),
          _timingAssociated(1, 0, 1, 1021),
        ],
      ),
    );

    final underBase = _run(input, policy: base) as EvaluatedResult;
    final underStricter = _run(input, policy: stricter) as EvaluatedResult;
    // 21 ms at the 500 ms reference is 4.2%: MINOR under the base policy
    // (base 4) but MODERATE under the stricter policy (base 3).
    expect(underBase.stars, 4);
    expect(underStricter.stars, 3);
  });

  // -------------------------------------------------------------------------
  // H2.9K evaluation-engine conformance audit - additional coverage
  // -------------------------------------------------------------------------

  test('H2.9K-1 - enabled pitch with UNAVAILABLE data still yields '
      'NOT_ENOUGH_PERFORMANCE: the structural authority never invents '
      'associations, for both target modes', () {
    for (final mode in TargetMode.values) {
      final result = _run(
        _input(
          mode,
          pitch: PitchEvaluationInput(
            dimensionState: EvaluationDimensionState.enabled,
            dataAvailability: DataAvailability.unavailable,
            observations: [],
          ),
        ),
      );
      expect(result, isA<NotEnoughPerformanceResult>());
      expect(result.state, EvaluationResultState.notEnoughPerformance);
      expect(result.toMap().containsKey('stars'), isFalse);
      expect(result.errorVector, isEmpty);
    }
  });

  test('H2.9K-2 - arpeggio timing scales the same absolute deviation by the '
      'expected interval from the first prescribed note: proportional, not a '
      'fixed literal threshold', () {
    // Note 1 is +21 ms at a 200 ms interval (10.5% -> MODERATE); note 2 is
    // +21 ms at a 1000 ms interval (2.1% -> NEGLIGIBLE). Identical absolute
    // deviation, different severity, proving the engine grades through the
    // policy's proportional bands and anchors on the earliest expected onset.
    final result = _evaluated(
      _input(
        TargetMode.arpeggio,
        timing: TimingEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          observations: [
            _timingAssociated(0, 0, 0, 1000),
            _timingAssociated(1, 200, 1, 1221),
            _timingAssociated(2, 1000, 2, 2021),
          ],
        ),
      ),
    );
    final timing = _dim(result, EvaluationDimension.timing);
    expect(timing.metrics['anchor_note_index'], 0);
    expect(timing.metrics['evaluated_note_count'], 3);
    expect(timing.metrics['reference_interval_ms'], 1000);
    expect(timing.metrics['reference_tolerance_ms'], 50);
    expect(timing.severity, SeverityTier.moderate);
    final late = result.errorVector.singleWhere(
      (e) => e.reasonCode == ErrorVectorReasonCode.timingLate,
    );
    expect(late.severity, SeverityTier.moderate);
    expect(late.signedDelta, 21);
    expect(late.count, 2);
    expect(
      late.context!['expected_note_indices'],
      <Object?>[1, 2],
    );
  });

  test('H2.9K-3 - Timing perfect while IOI deviates: IOI drives the result '
      'alone (reverse of H2.9J-27), confirming the dimensions never '
      'double-charge', () {
    final result = _evaluated(
      _input(
        TargetMode.arpeggio,
        timing: TimingEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          observations: [
            _timingAssociated(0, 0, 0, 1000),
            _timingAssociated(1, 500, 1, 1500),
            _timingAssociated(2, 1000, 2, 2000),
          ],
        ),
        ioi: IoiEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          expected: [_ioi(0, 1, 500), _ioi(1, 2, 500)],
          observed: [_ioi(0, 1, 399), _ioi(1, 2, 601)],
        ),
      ),
    );
    expect(
      _dim(result, EvaluationDimension.timing).severity,
      SeverityTier.none,
    );
    expect(_dim(result, EvaluationDimension.ioi).severity, SeverityTier.major);
    expect(
      result.errorVector.any(
        (e) => e.reasonCode == ErrorVectorReasonCode.timingLate,
      ),
      isFalse,
    );
    final ioi = result.errorVector.singleWhere(
      (e) => e.reasonCode == ErrorVectorReasonCode.ioiInconsistent,
    );
    expect(ioi.severity, SeverityTier.major);
    expect(ioi.signedDelta, 101);
    // IOI MAJOR is the only source: base 2, no trims.
    expect(result.stars, 2);
  });

  test('H2.9K-4 - a perfectly simultaneous chord (span 0) classifies as '
      'NEGLIGIBLE under the inclusive 0..40 ms beginner band and never trims',
      () {
    final result = _evaluated(
      _input(
        TargetMode.block,
        simultaneity: SimultaneityEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          groups: [
            _group(
              expectedGroupIndex: 0,
              expectedMembers: [0, 1],
              expectedPitches: [60, 64],
              observedEvents: [0, 1],
              observedOnsets: [1000, 1000],
              span: 0,
            ),
          ],
        ),
      ),
    );
    expect(
      _dim(result, EvaluationDimension.simultaneity).severity,
      SeverityTier.negligible,
    );
    expect(
      _dim(
        result,
        EvaluationDimension.simultaneity,
      ).metrics['spread_group_count'],
      1,
    );
    expect(result.stars, 5);
  });

  test('H2.9K-5 - order inversion classes are count-based over the full pair '
      'set: adjacent MINOR, partial MODERATE, full MAJOR for four notes', () {
    final adjacent = _evaluated(
      _input(
        TargetMode.arpeggio,
        order: OrderEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          order: OrderObservation(
            expectedOrder: [
              _el(0, 60, 0),
              _el(1, 62, 1),
              _el(2, 64, 2),
              _el(3, 67, 3),
            ],
            observedOrder: [
              _el(0, 60, 0),
              _el(1, 62, 1),
              _el(2, 64, 2),
              _el(3, 67, 3),
            ],
            associatedPairs: [
              _pair(0, 60, 0, 1, 60, 1),
              _pair(1, 62, 1, 0, 62, 0),
              _pair(2, 64, 2, 2, 64, 2),
              _pair(3, 67, 3, 3, 67, 3),
            ],
          ),
        ),
      ),
    );
    expect(
      _dim(adjacent, EvaluationDimension.order).severity,
      SeverityTier.minor,
    );

    final partial = _evaluated(
      _input(
        TargetMode.arpeggio,
        order: OrderEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          order: OrderObservation(
            expectedOrder: [
              _el(0, 60, 0),
              _el(1, 62, 1),
              _el(2, 64, 2),
              _el(3, 67, 3),
            ],
            observedOrder: [
              _el(0, 60, 0),
              _el(1, 62, 1),
              _el(2, 64, 2),
              _el(3, 67, 3),
            ],
            associatedPairs: [
              _pair(0, 60, 0, 2, 60, 2),
              _pair(1, 62, 1, 0, 62, 0),
              _pair(2, 64, 2, 1, 64, 1),
              _pair(3, 67, 3, 3, 67, 3),
            ],
          ),
        ),
      ),
    );
    expect(
      _dim(partial, EvaluationDimension.order).severity,
      SeverityTier.moderate,
    );

    final full = _evaluated(
      _input(
        TargetMode.arpeggio,
        order: OrderEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          order: OrderObservation(
            expectedOrder: [
              _el(0, 60, 0),
              _el(1, 62, 1),
              _el(2, 64, 2),
              _el(3, 67, 3),
            ],
            observedOrder: [
              _el(0, 60, 0),
              _el(1, 62, 1),
              _el(2, 64, 2),
              _el(3, 67, 3),
            ],
            associatedPairs: [
              _pair(0, 60, 0, 3, 60, 3),
              _pair(1, 62, 1, 2, 62, 2),
              _pair(2, 64, 2, 1, 64, 1),
              _pair(3, 67, 3, 0, 67, 0),
            ],
          ),
        ),
      ),
    );
    expect(
      _dim(full, EvaluationDimension.order).severity,
      SeverityTier.major,
    );
  });

  test('H2.9K-6 - retrieval latency is enabled + UNAVAILABLE for arpeggio too '
      'and never produces severity, star impact, or a fabricated anchor', () {
    for (final mode in TargetMode.values) {
      final result = _evaluated(_input(mode));
      final retrieval = _dim(result, EvaluationDimension.retrievalLatency);
      expect(retrieval.state, EvaluationDimensionState.enabled);
      expect(retrieval.dataAvailability, DataAvailability.unavailable);
      expect(retrieval.severity, SeverityTier.none);
      final entry = result.errorVector.singleWhere(
        (e) =>
            e.reasonCode == ErrorVectorReasonCode.retrievalLatencyUnavailable,
      );
      expect(entry.severity, SeverityTier.none);
      expect(entry.context!['performance_anchor_absent'], isTrue);
      expect(result.stars, 5);
    }
  });

  test('H2.9K-7 - the missing-note ceiling never raises stars above base: a '
      'MAJOR base of 2 stays 2 with one missing note, and a base of 4 holds '
      'under the 4-star cap', () {
    EvaluatedResult baseWithMissing(int wrongCount, int missingCount) {
      return _evaluated(
        _input(
          TargetMode.block,
          pitch: PitchEvaluationInput(
            dimensionState: EvaluationDimensionState.enabled,
            dataAvailability: DataAvailability.available,
            observations: [
              for (var i = 0; i < wrongCount; i++)
                _associated(i, 60 + i * 4, i, 62 + i * 4),
              for (var i = 0; i < missingCount; i++)
                _pitchMissing(wrongCount + i, 60 + (wrongCount + i) * 4),
            ],
          ),
        ),
      );
    }

    // Three wrong notes => MAJOR base 2; one missing cap is 4, so the ceiling
    // must not lift the result back up.
    expect(baseWithMissing(3, 1).stars, 2);

    // One MINOR timing error => base 4; one missing cap is exactly 4, so the
    // ceiling holds the value it would already have.
    final held = _evaluated(
      _input(
        TargetMode.block,
        pitch: PitchEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          observations: [
            _associated(0, 60, 0, 60),
            _pitchMissing(1, 64),
          ],
        ),
        timing: TimingEvaluationInput(
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          observations: [
            _timingAssociated(0, 0, 0, 1000),
            _timingAssociated(1, 0, 1, 1021),
          ],
        ),
      ),
    );
    expect(held.stars, 4);
  });
}
