import 'package:flutter_test/flutter_test.dart';
import 'package:miditutor/midi/domain/evaluation_input.dart';
import 'package:miditutor/midi/domain/evaluation_policy.dart';
import 'package:miditutor/midi/domain/expected_musical_target.dart';

void main() {
  final EvaluationPolicyProfile profile = EvaluationPolicyProfile.instance;

  // ---------------------------------------------------------------------------
  // H2.9D identity / boundary / immutability invariants (still valid)
  // ---------------------------------------------------------------------------

  test(
    'T1 - identity and deterministic construction: mvp_default_v1 / v1.1 / v1',
    () {
      expect(EvaluationPolicyProfile.profileId, 'mvp_default_v1');
      expect(EvaluationPolicyProfile.contractVersion, 'v1.1');
      expect(EvaluationPolicyProfile.policyVersion, 'v1');
      expect(profile.profileIdValue, 'mvp_default_v1');
      expect(profile.contractVersionValue, 'v1.1');
      expect(profile.policyVersionValue, 'v1');

      final EvaluationPolicyProfile other = EvaluationPolicyProfile.build();
      expect(identical(other, profile), isFalse);
      expect(other == profile, isTrue);
      expect(other.hashCode, profile.hashCode);
      expect(other.toMap(), profile.toMap());
      profile.validate();
    },
  );

  test('T2 - boundaries are explicit and value-gated', () {
    expect(PolicyBoundary.values, <PolicyBoundary>[
      PolicyBoundary.inclusive,
      PolicyBoundary.exclusive,
    ]);
    expect(PolicyBoundary.inclusive.serialName, 'INCLUSIVE');
    expect(PolicyBoundary.exclusive.serialName, 'EXCLUSIVE');

    expect(
      () => ToleranceSpec(ms: 50),
      throwsFormatException,
      reason: 'a value requires an explicit boundary',
    );
    expect(
      () => ToleranceSpec(boundary: PolicyBoundary.inclusive),
      throwsFormatException,
      reason: 'a boundary without a value is not representable',
    );
    final resolved = ToleranceSpec(ms: 50, boundary: PolicyBoundary.inclusive);
    expect(resolved.isResolved, isTrue);
  });

  test('T3 - decided product semantics are materialized as policy data', () {
    expect(profile.pitch.unavailableHandling, UnavailableHandling.noPenalty);
    expect(profile.timing.firstNoteIsStartReference, isTrue);
    expect(profile.timing.tightensWithTempo, isTrue);
    expect(profile.order.impactTier, OrderImpactTier.lowerThanPrimaryPitch);
    expect(profile.simultaneity.missingMembersDoNotInvalidate, isTrue);
    expect(profile.simultaneity.excludesExtraNotes, isTrue);
    expect(profile.notApplicableHandling, NotApplicableHandling.distinct);
    expect(
      profile.stars.primarySeverityModel,
      PrimarySeverityModel.worstErrorWithMinorTrims,
    );
    expect(profile.stars.allowZeroStars, isTrue);
    expect(profile.stars.missingNote.countSensitive, isTrue);
    expect(profile.stars.missingNote.oneMissingNoteCapStars, 4);
    expect(profile.stars.extraNote.imposesHardCap, isFalse);
    expect(profile.stars.extraNote.hardCapStars, isNull);
    expect(profile.stars.lessonStarCapacity, 10);
    expect(profile.stars.accumulation, StarAccumulationKind.cappedProgress);
  });

  test(
    'T6 - level-sensitive simultaneity: vocabulary present and immutable',
    () {
      expect(
        profile.simultaneity.levelTolerances.keys,
        containsAll(<LearnerLevelKey>[
          LearnerLevelKey.beginner,
          LearnerLevelKey.intermediate,
          LearnerLevelKey.advanced,
        ]),
      );
      expect(
        () => (profile.simultaneity.levelTolerances as dynamic).clear(),
        throwsUnsupportedError,
      );
      expect(
        () => (profile.simultaneity.levelSeverityMs as dynamic).clear(),
        throwsUnsupportedError,
      );
    },
  );

  test('T8 - immutability: profile collections cannot mutate after '
      'construction', () {
    expect(
      () => (profile.stars.bands as dynamic).clear(),
      throwsUnsupportedError,
    );
    expect(
      () => (profile.dimensionSpecs as dynamic).clear(),
      throwsUnsupportedError,
    );
    expect(
      () => (profile.stars.baseStars as dynamic).clear(),
      throwsUnsupportedError,
    );
    expect(
      () => (profile.applicability.enabled as dynamic).clear(),
      throwsUnsupportedError,
    );

    final EvaluationPolicyProfile other = EvaluationPolicyProfile.build();
    expect(
      () => (other.unresolvedPrecedenceLayers as dynamic).clear(),
      throwsUnsupportedError,
    );
    expect(
      () => (other.errorVector.reasonCodes as dynamic).clear(),
      throwsUnsupportedError,
    );
  });

  test('T9 - unresolved precedence layers are explicit and no default is '
      'hidden', () {
    expect(profile.appliedResolutionDepth, PolicyResolutionLayer.profile);
    expect(
      profile.unresolvedPrecedenceLayers,
      containsAll(<PolicyResolutionLayer>[
        PolicyResolutionLayer.learnerLevel,
        PolicyResolutionLayer.skill,
        PolicyResolutionLayer.exerciseMode,
        PolicyResolutionLayer.tempoRange,
        PolicyResolutionLayer.dimensionOverride,
      ]),
    );
    expect(
      profile.unresolvedPrecedenceLayers,
      isNot(contains(PolicyResolutionLayer.profile)),
    );
  });

  // ---------------------------------------------------------------------------
  // H2.9H materialization tests
  // ---------------------------------------------------------------------------

  test('H2.9H-T4 - thresholds are fully materialized as policy data', () {
    expect(profile.containsResolvedDimensionThresholds, isTrue);
    expect(profile.timing.severityBands.bands, isNotEmpty);
    expect(profile.ioi.severityBands.bands, isNotEmpty);
    expect(profile.simultaneity.levelSeverityMs.length, 3);
    expect(profile.stars.minorTrimCount, 2);
    expect(profile.pitch.wrongNoteSeverity.bands, isNotEmpty);
    expect(profile.stars.extraNote.severityByCount.bands, isNotEmpty);
    expect(profile.stars.missingNote.capTable.caps, isNotEmpty);
    // The legacy unresolved slots remain unresolved on purpose.
    expect(profile.timing.baseTolerance, isNull);
    expect(profile.ioi.tolerance, isNull);
    expect(profile.stars.anyBandBoundaryResolved, isFalse);
  });

  test('H2.9H-T5 - tempo-dependent timing model is materialized', () {
    expect(
      profile.timing.tempoDependencyKind,
      TimingTempoDependencyKind.normalizedRatio,
    );
    expect(profile.timing.tightensWithTempo, isTrue);
    expect(profile.timing.toleranceRatio.percent, 5);
    expect(profile.timing.firstNoteIsStartReference, isTrue);
    expect(profile.timing.firstNoteLatenessPenalized, isFalse);
  });

  test('H2.9H-T7 - deterministic resolution mirrors locked applicability', () {
    const resolver = EvaluationPolicyResolver();

    final block = resolver.resolve(
      profile: profile,
      context: const PolicyResolutionContext(
        profileId: 'mvp_default_v1',
        profileVersion: 'v1.1',
        mode: TargetMode.block,
        learnerLevel: LearnerLevelKey.beginner,
        tempoBpm: 120,
      ),
    );
    expect(identical(block.profile, profile), isTrue);
    expect(block.mode, TargetMode.block);
    expect(block.learnerLevel, LearnerLevelKey.beginner);
    expect(block.tempoBpm, 120);
    expect(block.containsResolvedDimensionThresholds, isTrue);

    for (final dimension in EvaluationDimension.values) {
      final resolved = block.dimensions.firstWhere(
        (d) => d.dimension == dimension,
      );
      final expected =
          MvpDefaultEvaluationProfile.instance.isDimensionEnabled(
            TargetMode.block,
            dimension,
          )
          ? EvaluationDimensionState.enabled
          : EvaluationDimensionState.notApplicable;
      expect(
        resolved.state,
        expected,
        reason: 'block applicability of $dimension must mirror the profile',
      );
    }

    final blockAgain = resolver.resolve(
      profile: profile,
      context: const PolicyResolutionContext(
        profileId: 'mvp_default_v1',
        profileVersion: 'v1.1',
        mode: TargetMode.block,
        learnerLevel: LearnerLevelKey.beginner,
        tempoBpm: 120,
      ),
    );
    expect(blockAgain == block, isTrue);
    expect(blockAgain.toMap(), block.toMap());
    expect(blockAgain.hashCode, block.hashCode);

    expect(
      () => resolver.resolve(
        profile: profile,
        context: const PolicyResolutionContext(
          profileId: 'unknown_profile',
          profileVersion: 'v9',
          mode: TargetMode.block,
        ),
      ),
      throwsFormatException,
      reason: 'unknown policy identity must fail deterministically',
    );
  });

  test('H2.9H-T8 - pitch policy is exact, one-to-one and has no tolerance', () {
    expect(profile.pitch.exactMidiIdentity, isTrue);
    expect(profile.pitch.oneToOneMatching, isTrue);
    expect(profile.pitch.toleranceApplied, isFalse);
    expect(profile.pitch.spellingComparison, isFalse);
    expect(profile.pitch.rematchingAllowed, isFalse);
    expect(profile.pitch.alignmentAuthority, 'H2.6');
    expect(profile.pitch.extraNotesArePitchErrors, isFalse);

    final table = profile.pitch.wrongNoteSeverity;
    expect(table.classify(0), SeverityTier.none);
    expect(table.classify(1), SeverityTier.minor);
    expect(table.classify(2), SeverityTier.moderate);
    expect(table.classify(3), SeverityTier.major);
    expect(table.classify(99), SeverityTier.major);
  });

  test('H2.9H-T9 - extra-note policy severity and absent hard cap', () {
    final note = profile.stars.extraNote;
    expect(note.imposesHardCap, isFalse);
    expect(note.hardCapStars, isNull);
    expect(note.excludedFromSimultaneity, isTrue);
    expect(note.severityByCount.classify(0), SeverityTier.none);
    expect(note.severityByCount.classify(1), SeverityTier.negligible);
    expect(note.severityByCount.classify(2), SeverityTier.minor);
    expect(note.severityByCount.classify(3), SeverityTier.moderate);
    expect(note.severityByCount.classify(50), SeverityTier.moderate);
  });

  test('H2.9H-T10 - missing-note star ceilings apply after base + trims', () {
    final missing = profile.stars.missingNote;
    expect(missing.appliedAfterBaseAndTrims, isTrue);
    expect(missing.isCeilingNotSeverity, isTrue);
    expect(missing.invalidatesSimultaneity, isFalse);
    expect(missing.capTable.capForCount(0), isNull);
    expect(missing.capTable.capForCount(1), 4);
    expect(missing.capTable.capForCount(2), 3);
    expect(missing.capTable.capForCount(3), 2);
    expect(missing.capTable.capForCount(4), 1);
    expect(missing.capTable.capForCount(9), 1);
  });

  test('H2.9H-T11 - timing tolerance and severity boundaries (multiple '
      'tempos)', () {
    final timing = profile.timing;

    // Tolerance: round(expectedInterval * 5%).
    expect(timing.toleranceRatio.toleranceMs(1000), 50); // 60 BPM
    expect(timing.toleranceRatio.toleranceMs(500), 25); // 120 BPM
    expect(timing.toleranceRatio.toleranceMs(333), 17); // 180 BPM

    // Absolute boundaries at the 500 ms reference interval.
    expect(
      timing.classifySeverity(deviationMs: 20, expectedIntervalMs: 500),
      SeverityTier.negligible,
    );
    expect(
      timing.classifySeverity(deviationMs: 20.01, expectedIntervalMs: 500),
      SeverityTier.minor,
    );
    expect(
      timing.classifySeverity(deviationMs: 40, expectedIntervalMs: 500),
      SeverityTier.minor,
    );
    expect(
      timing.classifySeverity(deviationMs: 40.01, expectedIntervalMs: 500),
      SeverityTier.moderate,
    );
    expect(
      timing.classifySeverity(deviationMs: 75, expectedIntervalMs: 500),
      SeverityTier.moderate,
    );
    expect(
      timing.classifySeverity(deviationMs: 75.01, expectedIntervalMs: 500),
      SeverityTier.major,
    );

    // The same proportional boundaries scale with tempo.
    expect(
      timing.classifySeverity(deviationMs: 40, expectedIntervalMs: 1000),
      SeverityTier.negligible,
    );
    expect(
      timing.classifySeverity(deviationMs: 80.01, expectedIntervalMs: 1000),
      SeverityTier.moderate,
    );
    expect(
      timing.classifySeverity(deviationMs: 30, expectedIntervalMs: 333),
      SeverityTier.moderate,
    );
  });

  test('H2.9H-T12 - IOI severity boundaries', () {
    final ioi = profile.ioi.severityBands;
    expect(ioi.classify(5), SeverityTier.negligible);
    expect(ioi.classify(5.01), SeverityTier.minor);
    expect(ioi.classify(10), SeverityTier.minor);
    expect(ioi.classify(10.01), SeverityTier.moderate);
    expect(ioi.classify(20), SeverityTier.moderate);
    expect(ioi.classify(20.01), SeverityTier.major);
    expect(profile.ioi.comparisonBasis, 'learner_mean_interval');
    expect(profile.ioi.doubleChargesTiming, isFalse);
  });

  test('H2.9H-T13 - simultaneity severity boundaries per learner level', () {
    final simultaneity = profile.simultaneity;

    expect(
      simultaneity.classifySeverity(LearnerLevelKey.beginner, 40),
      SeverityTier.negligible,
    );
    expect(
      simultaneity.classifySeverity(LearnerLevelKey.beginner, 40.01),
      SeverityTier.minor,
    );
    expect(
      simultaneity.classifySeverity(LearnerLevelKey.beginner, 80),
      SeverityTier.minor,
    );
    expect(
      simultaneity.classifySeverity(LearnerLevelKey.beginner, 80.01),
      SeverityTier.major,
    );

    expect(
      simultaneity.classifySeverity(LearnerLevelKey.intermediate, 30),
      SeverityTier.negligible,
    );
    expect(
      simultaneity.classifySeverity(LearnerLevelKey.intermediate, 30.01),
      SeverityTier.minor,
    );
    expect(
      simultaneity.classifySeverity(LearnerLevelKey.intermediate, 60),
      SeverityTier.minor,
    );
    expect(
      simultaneity.classifySeverity(LearnerLevelKey.intermediate, 60.01),
      SeverityTier.major,
    );

    expect(
      simultaneity.classifySeverity(LearnerLevelKey.advanced, 20),
      SeverityTier.negligible,
    );
    expect(
      simultaneity.classifySeverity(LearnerLevelKey.advanced, 20.01),
      SeverityTier.minor,
    );
    expect(
      simultaneity.classifySeverity(LearnerLevelKey.advanced, 40),
      SeverityTier.minor,
    );
    expect(
      simultaneity.classifySeverity(LearnerLevelKey.advanced, 40.01),
      SeverityTier.major,
    );
  });

  test('H2.9H-T14 - order severities and lower-than-pitch impact', () {
    final order = profile.order;
    expect(order.adjacentInversionSeverity, SeverityTier.minor);
    expect(order.partialInversionSeverity, SeverityTier.moderate);
    expect(order.fullReversalSeverity, SeverityTier.major);
    expect(order.independentOfPitch, isTrue);
    expect(order.rematchingAllowed, isFalse);
    expect(order.impactTier, OrderImpactTier.lowerThanPrimaryPitch);
  });

  test(
    'H2.9H-T15 - star aggregation data reproduces the decided star curve',
    () {
      final stars = profile.stars;
      expect(stars.baseStars[SeverityTier.none], 5);
      expect(stars.baseStars[SeverityTier.negligible], 5);
      expect(stars.baseStars[SeverityTier.minor], 4);
      expect(stars.baseStars[SeverityTier.moderate], 3);
      expect(stars.baseStars[SeverityTier.major], 2);
      expect(stars.minimumTrimSeverity, SeverityTier.minor);
      expect(stars.minorTrimCount, 2);
      expect(stars.worstErrorEstablishesBase, isTrue);
      expect(stars.worstErrorTrims, isFalse);
      expect(stars.fractionalStars, isFalse);
      expect(stars.lessonStarsMonotonic, isTrue);
      expect(stars.lessonStarsDecay, isFalse);
      expect(stars.lessonStarsSeparateFromMastery, isTrue);
      expect(stars.tempoProgressionThresholdStars, 4);

      expect(_simulateStars(stars, const <SeverityTier>[]), 5);
      expect(_simulateStars(stars, const [SeverityTier.minor]), 4);
      expect(_simulateStars(stars, const [SeverityTier.moderate]), 3);
      expect(_simulateStars(stars, const [SeverityTier.major]), 2);
      expect(
        _simulateStars(stars, const [SeverityTier.major, SeverityTier.minor]),
        1,
      );
      expect(
        _simulateStars(stars, const [
          SeverityTier.major,
          SeverityTier.minor,
          SeverityTier.minor,
        ]),
        0,
      );
      expect(
        _simulateStars(stars, const [SeverityTier.negligible]),
        5,
        reason: 'a lone negligible extra note must not trim',
      );
      expect(
        _simulateStars(stars, const [
          SeverityTier.major,
          SeverityTier.minor,
          SeverityTier.minor,
          SeverityTier.minor,
          SeverityTier.minor,
        ]),
        0,
        reason: 'trims are capped at two whole stars',
      );

      // Missing-note ceiling is applied after base + trims.
      expect(_simulateWithMissing(stars, const <SeverityTier>[], 1), 4);
      expect(_simulateWithMissing(stars, const <SeverityTier>[], 4), 1);
      expect(
        _simulateWithMissing(stars, const [
          SeverityTier.major,
          SeverityTier.minor,
          SeverityTier.minor,
        ], 1),
        0,
      );
    },
  );

  test('H2.9H-T16 - retrieval latency: enabled, unavailable, no penalty', () {
    final latency = profile.retrievalLatency;
    expect(latency.enabledForAllModes, isTrue);
    expect(latency.producesSeverity, isFalse);
    expect(latency.producesStarImpact, isFalse);
    expect(latency.unavailableHandling, UnavailableHandling.noPenalty);
    expect(
      latency.unavailableReasonCode,
      ErrorVectorReasonCode.retrievalLatencyUnavailable,
    );
    expect(
      latency.unavailableReasonCode.serialName,
      'RETRIEVAL_LATENCY_UNAVAILABLE',
    );
  });

  test('H2.9H-T17 - result state and evaluability preserve NEP != 0 stars', () {
    expect(
      profile.resultState.insufficientDataState,
      EvaluationResultState.notEnoughPerformance,
    );
    expect(profile.resultState.evaluatedMinStars, 0);
    expect(profile.resultState.evaluatedMaxStars, 5);
    expect(profile.resultState.producesAggregatePassFail, isFalse);
    expect(profile.resultState.notEnoughPerformanceEqualsZeroStars, isFalse);
    expect(
      profile.resultState.lifecycleStatesOutsideResult,
      containsAll(<String>['INVALIDATED', 'ABANDONED', 'FAILED']),
    );

    expect(profile.evaluability.requiresStructuralAssociation, isTrue);
    expect(profile.evaluability.basedOnPitchCorrectness, isFalse);
    expect(
      profile.evaluability.zeroAssociationsMeansNotEnoughPerformance,
      isTrue,
    );
    expect(profile.evaluability.associationAuthority, 'H2.6');
  });

  test('H2.9H-T18 - error vector policy and entry are descriptive only', () {
    expect(
      profile.errorVector.reasonCodes.toSet(),
      ErrorVectorReasonCode.values.toSet(),
    );
    expect(profile.errorVector.descriptiveOnly, isTrue);
    expect(profile.errorVector.carriesStarsOrWeights, isFalse);
    expect(profile.errorVector.mutatesMasteryEvidence, isFalse);
    expect(ErrorVectorReasonCode.pitchWrong.serialName, 'PITCH_WRONG');
    expect(
      ErrorVectorReasonCode.orderFullReversal.serialName,
      'ORDER_FULL_REVERSAL',
    );

    final entry = ErrorVectorEntry(
      dimension: EvaluationDimension.pitch,
      severity: SeverityTier.minor,
      reasonCode: ErrorVectorReasonCode.pitchWrong,
      expectedValue: 60,
      observedValue: 61,
      signedDelta: 1,
      count: 1,
      context: <String, Object?>{'note_index': 2},
    );
    expect(entry.toMap()['reason_code'], 'PITCH_WRONG');
    expect(
      entry,
      ErrorVectorEntry(
        dimension: EvaluationDimension.pitch,
        severity: SeverityTier.minor,
        reasonCode: ErrorVectorReasonCode.pitchWrong,
        expectedValue: 60,
        observedValue: 61,
        signedDelta: 1,
        count: 1,
        context: <String, Object?>{'note_index': 2},
      ),
    );
    expect(() => (entry.context as dynamic).clear(), throwsUnsupportedError);
    final minimal = ErrorVectorEntry(
      dimension: EvaluationDimension.timing,
      severity: SeverityTier.none,
      reasonCode: ErrorVectorReasonCode.timingEarly,
    );
    expect(minimal.expectedValue, isNull);
    expect(minimal.context, isNull);
  });

  test('H2.9H-T19 - materialized applicability is unambiguous', () {
    final applicability = profile.applicability;
    expect(applicability.validate, returnsNormally);
    expect(
      applicability.stateFor(TargetMode.block, EvaluationDimension.pitch),
      EvaluationDimensionState.enabled,
    );
    expect(
      applicability.stateFor(TargetMode.block, EvaluationDimension.ioi),
      EvaluationDimensionState.notApplicable,
    );
    expect(
      applicability.stateFor(TargetMode.block, EvaluationDimension.order),
      EvaluationDimensionState.notApplicable,
    );
    expect(
      applicability.stateFor(
        TargetMode.arpeggio,
        EvaluationDimension.simultaneity,
      ),
      EvaluationDimensionState.notApplicable,
    );
    expect(
      applicability.stateFor(TargetMode.arpeggio, EvaluationDimension.ioi),
      EvaluationDimensionState.enabled,
    );
  });

  test('H2.9H-T20 - serialization preserves the full materialized profile', () {
    final map = profile.toMap();
    expect(map['profile_id'], 'mvp_default_v1');
    expect(map['contract_version'], 'v1.1');
    expect(map.containsKey('evaluability'), isTrue);
    expect(map.containsKey('result_state'), isTrue);
    expect(map.containsKey('error_vector'), isTrue);
    expect(map.containsKey('applicability'), isTrue);

    final dimensions = map['dimensions']! as Map<String, Object?>;
    final pitch = dimensions['pitch']! as Map<String, Object?>;
    expect(pitch['wrong_note_severity'], isNotNull);
    final timing = dimensions['timing']! as Map<String, Object?>;
    expect(timing['severity_bands'], isNotNull);
    expect(timing['tolerance_ratio'], isNotNull);
    final simultaneity = dimensions['simultaneity']! as Map<String, Object?>;
    expect(simultaneity['level_severity_ms'], isNotNull);

    final stars = map['stars']! as Map<String, Object?>;
    expect(stars['base_stars'], isNotNull);
    expect(stars['minor_trim_count'], 2);

    final rebuilt = EvaluationPolicyProfile.build();
    expect(rebuilt.toMap(), map);
  });

  test('H2.9H-T21 - validation rejects malformed policy data', () {
    // Missing boundary on a bounded band.
    expect(
      () => SeverityBandTable(
        bands: const <SeverityBand>[
          SeverityBand(severity: SeverityTier.minor, upperBound: 5),
          SeverityBand(severity: SeverityTier.major),
        ],
      ).validate(),
      throwsFormatException,
    );

    // Overlapping / non-increasing ranges.
    expect(
      () => SeverityBandTable(
        bands: const <SeverityBand>[
          SeverityBand(
            severity: SeverityTier.minor,
            upperBound: 10,
            upperBoundary: PolicyBoundary.inclusive,
          ),
          SeverityBand(
            severity: SeverityTier.moderate,
            upperBound: 5,
            upperBoundary: PolicyBoundary.inclusive,
          ),
          SeverityBand(severity: SeverityTier.major),
        ],
      ).validate(),
      throwsFormatException,
    );

    // Non-increasing severities.
    expect(
      () => SeverityBandTable(
        bands: const <SeverityBand>[
          SeverityBand(
            severity: SeverityTier.moderate,
            upperBound: 10,
            upperBoundary: PolicyBoundary.inclusive,
          ),
          SeverityBand(severity: SeverityTier.minor),
        ],
      ).validate(),
      throwsFormatException,
    );

    // Missing open-ended band.
    expect(
      () => SeverityBandTable(
        bands: const <SeverityBand>[
          SeverityBand(
            severity: SeverityTier.minor,
            upperBound: 10,
            upperBoundary: PolicyBoundary.inclusive,
          ),
        ],
      ).validate(),
      throwsFormatException,
    );

    // Missing-cap ordering / range.
    expect(
      () => MissingNoteCapTable(
        caps: const <MissingNoteCap>[
          MissingNoteCap(minimumMissingCount: 0, maxStars: null),
          MissingNoteCap(minimumMissingCount: 1, maxStars: 3),
          MissingNoteCap(minimumMissingCount: 2, maxStars: 4),
        ],
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => MissingNoteCapTable(
        caps: const <MissingNoteCap>[
          MissingNoteCap(minimumMissingCount: 0, maxStars: 9),
        ],
      ).validate(),
      throwsFormatException,
    );

    // Unknown learner-level mapping.
    expect(
      () => SimultaneityPolicySpec(
        levelTolerances: <LearnerLevelKey, ToleranceSpec>{
          LearnerLevelKey.beginner: ToleranceSpec(),
        },
        levelSeverityMs: <LearnerLevelKey, SeverityBandTable>{
          LearnerLevelKey.beginner:
              profile.simultaneity.levelSeverityMs[LearnerLevelKey.beginner]!,
        },
        missingMembersDoNotInvalidate: true,
        excludesExtraNotes: true,
      ).validateLevelCoverage(),
      throwsFormatException,
    );

    // Missing / duplicate reason-code definitions.
    expect(
      () => ErrorVectorPolicy(
        reasonCodes: const <ErrorVectorReasonCode>[
          ErrorVectorReasonCode.pitchWrong,
          ErrorVectorReasonCode.pitchWrong,
        ],
        descriptiveOnly: true,
        carriesStarsOrWeights: false,
        mutatesMasteryEvidence: false,
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => ErrorVectorPolicy(
        reasonCodes: const <ErrorVectorReasonCode>[
          ErrorVectorReasonCode.pitchWrong,
        ],
        descriptiveOnly: true,
        carriesStarsOrWeights: false,
        mutatesMasteryEvidence: false,
      ).validate(),
      throwsFormatException,
    );

    // Ambiguous / incomplete applicability.
    expect(
      () => EvaluationPolicyApplicability(
        enabled: <TargetMode, Set<EvaluationDimension>>{
          TargetMode.block: <EvaluationDimension>{EvaluationDimension.pitch},
        },
        notApplicable: <TargetMode, Set<EvaluationDimension>>{
          TargetMode.block: <EvaluationDimension>{EvaluationDimension.pitch},
        },
      ).validate(),
      throwsFormatException,
    );

    // Invalid star values.
    expect(
      () => _starPolicyWith(
        baseStars: const <SeverityTier, int>{
          SeverityTier.none: 5,
          SeverityTier.negligible: 5,
          SeverityTier.minor: 4,
          SeverityTier.moderate: 7,
          SeverityTier.major: 2,
        },
      ).validate(),
      throwsFormatException,
    );

    // Invalid trim count.
    expect(
      () => _starPolicyWith(minorTrimCount: 9).validate(),
      throwsFormatException,
    );

    // Incompatible contract version / identity.
    expect(
      () => _profileWith(contractVersionValue: 'v2').validate(),
      throwsFormatException,
    );
    expect(
      () => _profileWith(profileIdValue: 'other').validate(),
      throwsFormatException,
    );
  });
}

// -----------------------------------------------------------------------------
// Test-side simulation of the decided star aggregation. This is deliberately
// NOT production code: H2.9H materializes policy data and must not implement
// the star runtime. The simulation proves the materialized data yields the
// decided outcomes.
// -----------------------------------------------------------------------------

int _simulateStars(StarQualityPolicy policy, List<SeverityTier> severities) {
  if (severities.isEmpty) {
    return 5;
  }
  var worst = severities.first;
  for (final severity in severities) {
    if (severity.rank > worst.rank) {
      worst = severity;
    }
  }
  var stars = policy.baseStars[worst]!;
  final trimmable = severities
      .where((severity) => severity.atLeast(policy.minimumTrimSeverity))
      .length;
  final worstTrims = worst.atLeast(policy.minimumTrimSeverity) ? 1 : 0;
  var extraTrims = trimmable - worstTrims;
  if (extraTrims < 0) {
    extraTrims = 0;
  }
  final maxTrims = policy.minorTrimCount ?? 0;
  if (extraTrims > maxTrims) {
    extraTrims = maxTrims;
  }
  stars -= extraTrims;
  return stars;
}

int _simulateWithMissing(
  StarQualityPolicy policy,
  List<SeverityTier> severities,
  int missingCount,
) {
  final stars = _simulateStars(policy, severities);
  final cap = policy.missingNote.capTable.capForCount(missingCount);
  if (cap == null) {
    return stars;
  }
  return stars < cap ? stars : cap;
}

EvaluationPolicyProfile _profileWith({
  String? profileIdValue,
  String? contractVersionValue,
  StarQualityPolicy? stars,
}) {
  final source = EvaluationPolicyProfile.instance;
  return EvaluationPolicyProfile(
    profileIdValue: profileIdValue ?? source.profileIdValue,
    contractVersionValue: contractVersionValue ?? source.contractVersionValue,
    policyVersionValue: source.policyVersionValue,
    provenance: source.provenance,
    pitch: source.pitch,
    timing: source.timing,
    order: source.order,
    simultaneity: source.simultaneity,
    ioi: source.ioi,
    retrievalLatency: source.retrievalLatency,
    stars: stars ?? source.stars,
    evaluability: source.evaluability,
    resultState: source.resultState,
    errorVector: source.errorVector,
    applicability: source.applicability,
    notApplicableHandling: source.notApplicableHandling,
    appliedResolutionDepth: source.appliedResolutionDepth,
    unresolvedPrecedenceLayers: source.unresolvedPrecedenceLayers,
  );
}

StarQualityPolicy _starPolicyWith({
  Map<SeverityTier, int>? baseStars,
  int? minorTrimCount,
}) {
  final source = EvaluationPolicyProfile.instance.stars;
  return StarQualityPolicy(
    primarySeverityModel: source.primarySeverityModel,
    allowZeroStars: source.allowZeroStars,
    minorTrimCount: minorTrimCount ?? source.minorTrimCount,
    missingNote: source.missingNote,
    extraNote: source.extraNote,
    lessonStarCapacity: source.lessonStarCapacity,
    accumulation: source.accumulation,
    baseStars: baseStars ?? source.baseStars,
    minimumTrimSeverity: source.minimumTrimSeverity,
    worstErrorEstablishesBase: source.worstErrorEstablishesBase,
    worstErrorTrims: source.worstErrorTrims,
    fractionalStars: source.fractionalStars,
    lessonStarsMonotonic: source.lessonStarsMonotonic,
    lessonStarsDecay: source.lessonStarsDecay,
    lessonStarsSeparateFromMastery: source.lessonStarsSeparateFromMastery,
    tempoProgressionThresholdStars: source.tempoProgressionThresholdStars,
    bands: source.bands,
  );
}
