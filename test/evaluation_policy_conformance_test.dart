// H2.9I — Evaluation Policy Conformance & Boundary Validation.
//
// Validation-only: this file proves the materialized `mvp_default_v1` profile
// faithfully represents the locked H2.9G policy contract. It implements no
// evaluation, no star runtime, and no Error Vector generation. Expected values
// are derived from the locked contract, not from implementation internals;
// boundary probes are labelled below / at / above.

import 'package:flutter_test/flutter_test.dart';
import 'package:miditutor/midi/domain/evaluation_contract.dart';
import 'package:miditutor/midi/domain/evaluation_dimension_observations.dart';
import 'package:miditutor/midi/domain/evaluation_input.dart';
import 'package:miditutor/midi/domain/evaluation_policy.dart';
import 'package:miditutor/midi/domain/expected_musical_target.dart';

void main() {
  final EvaluationPolicyProfile profile = EvaluationPolicyProfile.instance;
  const EvaluationPolicyResolver resolver = EvaluationPolicyResolver();

  PolicyResolutionContext contextFor(
    TargetMode mode,
    LearnerLevelKey level,
    int tempoBpm,
  ) => PolicyResolutionContext(
    profileId: 'mvp_default_v1',
    profileVersion: 'v1.1',
    mode: mode,
    learnerLevel: level,
    tempoBpm: tempoBpm,
  );

  // ---------------------------------------------------------------------------
  // §5 identity conformance
  // ---------------------------------------------------------------------------

  test('H2.9I-1 - known identity resolves successfully for both modes', () {
    expect(profile.profileIdValue, 'mvp_default_v1');
    expect(profile.contractVersionValue, 'v1.1');
    expect(MvpDefaultEvaluationProfile.profileId, 'mvp_default_v1');

    for (final mode in TargetMode.values) {
      final resolved = resolver.resolve(
        profile: profile,
        context: contextFor(mode, LearnerLevelKey.beginner, 120),
      );
      expect(resolved.profile, profile);
      expect(resolved.mode, mode);
      expect(resolved.containsResolvedDimensionThresholds, isTrue);
    }
  });

  test('H2.9I-2 - unknown profile id fails deterministically, never falls '
      'back', () {
    for (final unknownId in <String>['mvp_default_v999', 'nonexistent']) {
      expect(
        () => resolver.resolve(
          profile: profile,
          context: PolicyResolutionContext(
            profileId: unknownId,
            profileVersion: 'v1.1',
            mode: TargetMode.block,
          ),
        ),
        throwsFormatException,
        reason: 'unknown id $unknownId must not resolve to mvp_default_v1',
      );
    }
    final tampered = _profileFromMap(<String, Object?>{
      ...profile.toMap(),
      'profile_id': 'mvp_default_v999',
    });
    expect(tampered.validate, throwsFormatException);
  });

  test(
    'H2.9I-3 - unknown/incompatible contract version fails deterministically',
    () {
      for (final version in <String>['v0.9', 'v2', 'v1.2']) {
        expect(
          () => resolver.resolve(
            profile: profile,
            context: PolicyResolutionContext(
              profileId: 'mvp_default_v1',
              profileVersion: version,
              mode: TargetMode.arpeggio,
            ),
          ),
          throwsFormatException,
          reason: 'contract version $version must not be accepted silently',
        );
      }
      expect(
        () => _profileFromMap(<String, Object?>{
          ...profile.toMap(),
          'contract_version': 'v2',
        }).validate(),
        throwsFormatException,
      );
    },
  );

  test(
    'H2.9I-4 - resolution never defaults an unknown identity to a known one',
    () {
      expect(
        () => resolver.resolve(
          profile: profile,
          context: PolicyResolutionContext(
            profileId: 'mvp_default_v999',
            profileVersion: 'v1.1',
            mode: TargetMode.block,
          ),
        ),
        throwsFormatException,
      );
      final resolved = resolver.resolve(
        profile: profile,
        context: contextFor(TargetMode.block, LearnerLevelKey.beginner, 120),
      );
      expect(resolved.profile.profileIdValue, 'mvp_default_v1');
    },
  );

  // ---------------------------------------------------------------------------
  // §6 serialization conformance
  // ---------------------------------------------------------------------------

  test('H2.9I-5 - serialize -> deserialize -> validate -> resolve is value '
      'equivalent', () {
    final returned = _profileFromMap(profile.toMap());
    expect(returned.validate, returnsNormally);
    expect(returned.pitch, profile.pitch);
    expect(returned.timing, profile.timing);
    expect(returned.order, profile.order);
    expect(returned.simultaneity, profile.simultaneity);
    expect(returned.ioi, profile.ioi);
    expect(returned.retrievalLatency, profile.retrievalLatency);
    expect(returned.stars, profile.stars);
    expect(returned.evaluability, profile.evaluability);
    expect(returned.resultState, profile.resultState);
    expect(returned.errorVector, profile.errorVector);
    expect(returned.applicability, profile.applicability);
    expect(returned, profile);
    expect(returned.hashCode, profile.hashCode);
    expect(returned.toMap(), profile.toMap());

    for (final mode in TargetMode.values) {
      final context = contextFor(mode, LearnerLevelKey.intermediate, 90);
      final original = resolver.resolve(profile: profile, context: context);
      final rebuilt = resolver.resolve(profile: returned, context: context);
      expect(rebuilt, original);
      expect(rebuilt.toMap(), original.toMap());
    }
  });

  test('H2.9I-6 - serialized form carries identity, provenance and every '
      'policy section', () {
    final map = profile.toMap();
    expect(map['profile_id'], 'mvp_default_v1');
    expect(map['contract_version'], 'v1.1');
    expect(map['policy_version'], 'v1');

    final provenance = map['provenance']! as Map<String, Object?>;
    expect(provenance['source_kind'], isNotNull);
    expect(provenance['source_path'], isNotNull);
    expect(provenance['source_identifier'], isNotNull);

    final dimensions = map['dimensions']! as Map<String, Object?>;
    expect(dimensions.keys.toSet(), <String>{
      'pitch',
      'timing',
      'order',
      'simultaneity',
      'ioi',
      'retrieval_latency',
    });
    for (final entry in dimensions.entries) {
      expect(entry.value, isA<Map<String, Object?>>(), reason: entry.key);
    }

    expect(map.containsKey('stars'), isTrue);
    expect(map.containsKey('evaluability'), isTrue);
    expect(map.containsKey('result_state'), isTrue);
    expect(map.containsKey('error_vector'), isTrue);
    expect(map.containsKey('applicability'), isTrue);
    expect(map['not_applicable_handling'], 'DISTINCT');
    expect(map['applied_resolution_depth'], 'PROFILE');
  });

  test('H2.9I-7 - full serialization is deterministic and total', () {
    final a = profile.toMap();
    final b = EvaluationPolicyProfile.build().toMap();
    expect(b, a);

    final baseStars = a['stars']! as Map<String, Object?>;
    final baseStarsMap = baseStars['base_stars']! as Map<String, Object?>;
    expect(
      baseStarsMap.keys.toSet(),
      SeverityTier.values.map((t) => t.serialName).toSet(),
    );

    final simultaneity =
        (a['dimensions']! as Map<String, Object?>)['simultaneity']!
            as Map<String, Object?>;
    final levelTables =
        simultaneity['level_severity_ms']! as Map<String, Object?>;
    expect(
      levelTables.keys.toSet(),
      LearnerLevelKey.values.map((l) => l.serialName).toSet(),
    );

    final errorVector = a['error_vector']! as Map<String, Object?>;
    final reasonCodes = errorVector['reason_codes']! as List<Object?>;
    expect(reasonCodes.length, ErrorVectorReasonCode.values.length);
    expect(reasonCodes.toSet().length, reasonCodes.length);
  });

  // ---------------------------------------------------------------------------
  // §7 deterministic resolution
  // ---------------------------------------------------------------------------

  test(
    'H2.9I-8 - identical context resolves to identical policy every time',
    () {
      var first = <ResolvedEvaluationPolicy>[];
      for (var i = 0; i < 25; i++) {
        first.add(
          resolver.resolve(
            profile: profile,
            context: contextFor(
              TargetMode.arpeggio,
              LearnerLevelKey.advanced,
              180,
            ),
          ),
        );
      }
      final baseline = first.first;
      for (final resolved in first) {
        expect(resolved, baseline);
        expect(resolved.hashCode, baseline.hashCode);
        expect(resolved.toMap(), baseline.toMap());
      }
    },
  );

  test('H2.9I-9 - repeated construction and serialization differ by no byte '
      'and no field', () {
    for (var i = 0; i < 10; i++) {
      final rebuilt = EvaluationPolicyProfile.build();
      expect(rebuilt, profile);
      expect(rebuilt.toMap(), profile.toMap());
    }
  });

  // ---------------------------------------------------------------------------
  // §8 applicability conformance
  // ---------------------------------------------------------------------------

  test('H2.9I-10 - block applicability is exactly pitch/timing/simultaneity/'
      'retrieval-latency', () {
    final applicability = profile.applicability;
    expect(applicability.enabled[TargetMode.block], <EvaluationDimension>{
      EvaluationDimension.pitch,
      EvaluationDimension.timing,
      EvaluationDimension.simultaneity,
      EvaluationDimension.retrievalLatency,
    });
    expect(applicability.notApplicable[TargetMode.block], <EvaluationDimension>{
      EvaluationDimension.order,
      EvaluationDimension.ioi,
    });
    expect(
      applicability.stateFor(TargetMode.block, EvaluationDimension.order),
      EvaluationDimensionState.notApplicable,
    );
    expect(
      applicability.stateFor(TargetMode.block, EvaluationDimension.ioi),
      EvaluationDimensionState.notApplicable,
    );
  });

  test('H2.9I-11 - arpeggio applicability is exactly pitch/order/timing/ioi/'
      'retrieval-latency', () {
    final applicability = profile.applicability;
    expect(applicability.enabled[TargetMode.arpeggio], <EvaluationDimension>{
      EvaluationDimension.pitch,
      EvaluationDimension.order,
      EvaluationDimension.timing,
      EvaluationDimension.ioi,
      EvaluationDimension.retrievalLatency,
    });
    expect(
      applicability.notApplicable[TargetMode.arpeggio],
      <EvaluationDimension>{EvaluationDimension.simultaneity},
    );
    expect(
      applicability.stateFor(
        TargetMode.arpeggio,
        EvaluationDimension.simultaneity,
      ),
      EvaluationDimensionState.notApplicable,
    );
  });

  test('H2.9I-12 - NOT_APPLICABLE is not PASS, FAIL or UNAVAILABLE', () {
    expect(
      EvaluationDimensionState.notApplicable,
      isNot(EvaluationDimensionState.enabled),
    );
    expect(
      EvaluationDimensionState.notApplicable,
      isNot(EvaluationDimensionState.unavailable),
    );
    expect(profile.notApplicableHandling, NotApplicableHandling.distinct);
    expect(profile.resultState.producesAggregatePassFail, isFalse);
    expect(
      profile.resultState.lifecycleStatesOutsideResult,
      isNot(contains('PASS')),
    );
    expect(
      profile.resultState.lifecycleStatesOutsideResult,
      isNot(contains('FAIL')),
    );

    final resolved = resolver.resolve(
      profile: profile,
      context: contextFor(TargetMode.block, LearnerLevelKey.beginner, 120),
    );
    for (final dimension in resolved.dimensions) {
      expect(
        dimension.state,
        isNot(EvaluationDimensionState.unavailable),
        reason: 'the MVP profile never resolves a dimension to UNAVAILABLE',
      );
    }
  });

  // ---------------------------------------------------------------------------
  // §9 enabled + unavailable (retrieval latency) conformance
  // ---------------------------------------------------------------------------

  test('H2.9I-13 - retrieval latency is enabled, unavailable, and carries no '
      'severity, penalty or star contribution', () {
    final latency = profile.retrievalLatency;
    expect(latency.enabledForAllModes, isTrue);
    expect(
      profile.applicability.stateFor(
        TargetMode.block,
        EvaluationDimension.retrievalLatency,
      ),
      EvaluationDimensionState.enabled,
    );
    expect(
      profile.applicability.stateFor(
        TargetMode.arpeggio,
        EvaluationDimension.retrievalLatency,
      ),
      EvaluationDimensionState.enabled,
    );

    expect(latency.producesSeverity, isFalse);
    expect(latency.producesStarImpact, isFalse);
    expect(latency.unavailableHandling, UnavailableHandling.noPenalty);
    expect(
      latency.unavailableReasonCode.serialName,
      'RETRIEVAL_LATENCY_UNAVAILABLE',
    );
    expect(
      ErrorVectorReasonCode.retrievalLatencyUnavailable.serialName,
      'RETRIEVAL_LATENCY_UNAVAILABLE',
    );
    expect(profile.resultState.notEnoughPerformanceEqualsZeroStars, isFalse);

    final unavailable = RetrievalLatencyObservation(
      availability: ObservationAvailability.unavailable,
      reason: 'RETRIEVAL_LATENCY_UNAVAILABLE',
      performanceAnchorTimestampMs: null,
      performanceAnchorContext: null,
      firstObservedNoteEventIndex: null,
      firstObservedNoteTimestampMs: null,
      latencyDurationMs: null,
    );
    expect(unavailable.toMap()['availability'], 'UNAVAILABLE');
    expect(
      () => RetrievalLatencyObservation(
        availability: ObservationAvailability.unavailable,
        reason: 'RETRIEVAL_LATENCY_UNAVAILABLE',
        performanceAnchorTimestampMs: 0,
        performanceAnchorContext: null,
        firstObservedNoteEventIndex: null,
        firstObservedNoteTimestampMs: null,
        latencyDurationMs: null,
      ),
      throwsFormatException,
      reason:
          'an unavailable observation must never '
          'carry a fabricated anchor',
    );
  });

  // ---------------------------------------------------------------------------
  // §10 evaluability conformance
  // ---------------------------------------------------------------------------

  test('H2.9I-14 - zero required associations means NOT_ENOUGH_PERFORMANCE '
      '(Case A)', () {
    expect(profile.evaluability.requiresStructuralAssociation, isTrue);
    expect(
      profile.evaluability.zeroAssociationsMeansNotEnoughPerformance,
      isTrue,
    );
    expect(
      profile.resultState.insufficientDataState,
      EvaluationResultState.notEnoughPerformance,
    );
    expect(_resultStateFor(0), EvaluationResultState.notEnoughPerformance);
  });

  test('H2.9I-15 - one required association with all remaining pitches wrong '
      'is still evaluable (Case B)', () {
    expect(profile.evaluability.basedOnPitchCorrectness, isFalse);
    expect(profile.evaluability.associationAuthority, 'H2.6');
    expect(_resultStateFor(1), EvaluationResultState.evaluated);
    expect(_resultStateFor(7), EvaluationResultState.evaluated);
    expect(
      profile.pitch.wrongNoteSeverity.classify(3),
      SeverityTier.major,
      reason:
          'wrong pitches are graded severities, never '
          'NOT_ENOUGH_PERFORMANCE',
    );
    expect(profile.resultState.evaluatedMinStars, 0);
    expect(profile.resultState.evaluatedMaxStars, 5);
  });

  // ---------------------------------------------------------------------------
  // §11 NOT_ENOUGH_PERFORMANCE vs 0★ / 1★
  // ---------------------------------------------------------------------------

  test('H2.9I-16 - NOT_ENOUGH_PERFORMANCE is distinct from EVALUATED 0 and '
      'EVALUATED 1', () {
    expect(
      EvaluationResultState.notEnoughPerformance,
      isNot(EvaluationResultState.evaluated),
    );
    expect(
      EvaluationResultState.notEnoughPerformance.serialName,
      isNot(EvaluationResultState.evaluated.serialName),
    );
    expect(profile.resultState.notEnoughPerformanceEqualsZeroStars, isFalse);
    expect(profile.resultState.evaluatedMinStars, 0);
    expect(profile.stars.baseStars[SeverityTier.major], 2);

    final map = _profileFromMap(profile.toMap()).resultState.toMap();
    expect(map['insufficient_data_state'], 'NOT_ENOUGH_PERFORMANCE');
    expect(map['insufficient_data_state'], isNot('EVALUATED'));
    expect(
      profile.resultState.toMap()['insufficient_data_state'],
      'NOT_ENOUGH_PERFORMANCE',
    );

    expect(profile.stars.baseStars.containsKey(SeverityTier.none), isTrue);
    for (final stars in <int>[0, 1, 2]) {
      expect(
        StarQualityPolicy.standardBands.any((band) => band.stars == stars),
        isTrue,
        reason: '$stars is a valid evaluated star value',
      );
    }
  });

  // ---------------------------------------------------------------------------
  // §12 pitch policy conformance
  // ---------------------------------------------------------------------------

  test('H2.9I-17 - wrong-pitch exact cardinalities 0/1/2/3/4/5+', () {
    final table = profile.pitch.wrongNoteSeverity;
    expect(table.classify(0), SeverityTier.none);
    expect(table.classify(1), SeverityTier.minor);
    expect(table.classify(2), SeverityTier.moderate);
    expect(table.classify(3), SeverityTier.major);
    expect(table.classify(4), SeverityTier.major);
    expect(table.classify(5), SeverityTier.major);
    expect(table.classify(50), SeverityTier.major);
  });

  test('H2.9I-18 - pitch is exact MIDI identity, one-to-one, no tolerance, no '
      'spelling, no rematch', () {
    final pitch = profile.pitch;
    expect(pitch.exactMidiIdentity, isTrue);
    expect(pitch.oneToOneMatching, isTrue);
    expect(pitch.toleranceApplied, isFalse);
    expect(pitch.spellingComparison, isFalse);
    expect(pitch.rematchingAllowed, isFalse);
    expect(pitch.alignmentAuthority, 'H2.6');
    expect(pitch.extraNotesArePitchErrors, isFalse);
  });

  test('H2.9I-19 - extras are not counted as wrong required pitches and '
      'missing notes are not converted into wrong-pitch errors', () {
    final pitch = profile.pitch;
    final extraTable = profile.stars.extraNote.severityByCount;
    expect(extraTable.classify(1), SeverityTier.negligible);
    expect(extraTable.classify(2), SeverityTier.minor);
    expect(extraTable.classify(3), SeverityTier.moderate);
    expect(pitch.extraNotesArePitchErrors, isFalse);
    expect(
      ErrorVectorReasonCode.pitchExtra,
      isNot(ErrorVectorReasonCode.pitchWrong),
    );
    expect(
      ErrorVectorReasonCode.pitchMissing,
      isNot(ErrorVectorReasonCode.pitchWrong),
    );
    expect(
      ErrorVectorReasonCode.pitchMissing,
      isNot(ErrorVectorReasonCode.pitchExtra),
    );
    expect(profile.stars.missingNote.capTable.capForCount(2), 3);
  });

  // ---------------------------------------------------------------------------
  // §13 extra-note conformance
  // ---------------------------------------------------------------------------

  test(
    'H2.9I-20 - extra-note exact cardinalities 0/1/2/3/4+ with no hard cap',
    () {
      final extra = profile.stars.extraNote;
      expect(extra.severityByCount.classify(0), SeverityTier.none);
      expect(extra.severityByCount.classify(1), SeverityTier.negligible);
      expect(extra.severityByCount.classify(2), SeverityTier.minor);
      expect(extra.severityByCount.classify(3), SeverityTier.moderate);
      expect(extra.severityByCount.classify(4), SeverityTier.moderate);
      expect(extra.severityByCount.classify(100), SeverityTier.moderate);
      expect(extra.imposesHardCap, isFalse);
      expect(extra.hardCapStars, isNull);
      expect(extra.excludedFromSimultaneity, isTrue);
    },
  );

  test('H2.9I-21 - one extra note alone is NEGLIGIBLE and never trims', () {
    expect(profile.stars.minimumTrimSeverity, SeverityTier.minor);
    expect(_simulateStars(profile.stars, const [SeverityTier.negligible]), 5);
    expect(
      _simulateStars(profile.stars, const <SeverityTier>[
        SeverityTier.negligible,
        SeverityTier.negligible,
      ]),
      5,
      reason: 'an extra-note cluster that stays NEGLIGIBLE must not trim',
    );
  });

  // ---------------------------------------------------------------------------
  // §14 missing-note conformance
  // ---------------------------------------------------------------------------

  test('H2.9I-22 - missing-note exact boundaries 0/1/2/3/4/5+', () {
    final table = profile.stars.missingNote.capTable;
    expect(table.capForCount(0), isNull);
    expect(table.capForCount(1), 4);
    expect(table.capForCount(2), 3);
    expect(table.capForCount(3), 2);
    expect(table.capForCount(4), 1);
    expect(table.capForCount(5), 1);
    expect(table.capForCount(20), 1);
  });

  test('H2.9I-23 - missing cap is a final ceiling applied after base + trims '
      'and never raises stars', () {
    final missing = profile.stars.missingNote;
    expect(missing.appliedAfterBaseAndTrims, isTrue);
    expect(missing.isCeilingNotSeverity, isTrue);
    expect(missing.invalidatesSimultaneity, isFalse);

    for (var missingCount = 0; missingCount <= 12; missingCount++) {
      expect(
        _simulateWithMissing(profile.stars, const [
          SeverityTier.minor,
        ], missingCount),
        lessThanOrEqualTo(
          _simulateStars(profile.stars, const [SeverityTier.minor]),
        ),
        reason: 'a missing-note ceiling must never raise quality',
      );
    }

    expect(_simulateWithMissing(profile.stars, const <SeverityTier>[], 1), 4);
    expect(_simulateWithMissing(profile.stars, const <SeverityTier>[], 2), 3);
    expect(_simulateWithMissing(profile.stars, const <SeverityTier>[], 3), 2);
    expect(_simulateWithMissing(profile.stars, const <SeverityTier>[], 4), 1);
    expect(
      _simulateWithMissing(profile.stars, const [
        SeverityTier.major,
        SeverityTier.minor,
      ], 1),
      1,
      reason: 'base 2 -> 1 trim -> 1; the 4-cap does not raise it',
    );
  });

  // ---------------------------------------------------------------------------
  // §15 timing tolerance conformance
  // ---------------------------------------------------------------------------

  test('H2.9I-24 - toleranceMs = round(expectedIntervalMs * 5%) at 60/120/180 '
      'BPM', () {
    final tolerance = profile.timing.toleranceRatio;
    expect(tolerance.percent, 5);
    expect(tolerance.rounding, ToleranceRoundingMode.nearest);
    expect(tolerance.toleranceMs(60000 / 60), 50);
    expect(tolerance.toleranceMs(60000 / 120), 25);
    expect(tolerance.toleranceMs(60000 / 180), 17);
    expect(tolerance.toleranceMs(1000), 50);
    expect(tolerance.toleranceMs(500), 25);
    expect(tolerance.toleranceMs(333), 17);
  });

  test('H2.9I-25 - tolerance is proportional over intermediate tempos, not a '
      'lookup table', () {
    final tolerance = profile.timing.toleranceRatio;
    expect(tolerance.toleranceMs(60000 / 90), 33);
    expect(tolerance.toleranceMs(60000 / 144), 21);
    expect(tolerance.toleranceMs(60000 / 72), 42);
    expect(tolerance.toleranceMs(400), 20);
    expect(tolerance.toleranceMs(333), 17);
    expect(tolerance.toleranceMs(400), isNot(tolerance.toleranceMs(333)));
    expect(
      profile.timing.tempoDependencyKind,
      TimingTempoDependencyKind.normalizedRatio,
    );
  });

  // ---------------------------------------------------------------------------
  // §16 timing severity boundaries
  // ---------------------------------------------------------------------------

  test('H2.9I-26 - timing severity percentage boundaries below/at/above', () {
    final bands = profile.timing.severityBands;
    expect(bands.classify(3.9999), SeverityTier.negligible, reason: 'below 4%');
    expect(bands.classify(4), SeverityTier.negligible, reason: 'at 4%');
    expect(bands.classify(4.0001), SeverityTier.minor, reason: 'above 4%');
    expect(bands.classify(7.9999), SeverityTier.minor, reason: 'below 8%');
    expect(bands.classify(8), SeverityTier.minor, reason: 'at 8%');
    expect(bands.classify(8.0001), SeverityTier.moderate, reason: 'above 8%');
    expect(bands.classify(14.9999), SeverityTier.moderate, reason: 'below 15%');
    expect(bands.classify(15), SeverityTier.moderate, reason: 'at 15%');
    expect(bands.classify(15.0001), SeverityTier.major, reason: 'above 15%');
  });

  test('H2.9I-27 - timing severity absolute boundaries at 500 ms '
      'below/at/above', () {
    final timing = profile.timing;
    expect(timing.severityReferenceIntervalMs, 500);
    expect(
      timing.classifySeverity(deviationMs: 19.99, expectedIntervalMs: 500),
      SeverityTier.negligible,
    );
    expect(
      timing.classifySeverity(deviationMs: 20, expectedIntervalMs: 500),
      SeverityTier.negligible,
    );
    expect(
      timing.classifySeverity(deviationMs: 20.01, expectedIntervalMs: 500),
      SeverityTier.minor,
    );
    expect(
      timing.classifySeverity(deviationMs: 39.99, expectedIntervalMs: 500),
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
      timing.classifySeverity(deviationMs: 74.99, expectedIntervalMs: 500),
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
  });

  test('H2.9I-28 - the same proportional boundaries scale with tempo', () {
    final timing = profile.timing;
    expect(
      timing.classifySeverity(deviationMs: 40, expectedIntervalMs: 1000),
      SeverityTier.negligible,
    );
    expect(
      timing.classifySeverity(deviationMs: 40.01, expectedIntervalMs: 1000),
      SeverityTier.minor,
    );
    expect(
      timing.classifySeverity(deviationMs: 15.01, expectedIntervalMs: 100),
      SeverityTier.major,
    );
  });

  // ---------------------------------------------------------------------------
  // §17 tolerance vs severity separation
  // ---------------------------------------------------------------------------

  test(
    'H2.9I-29 - tolerance and severity bands are separate policy concepts',
    () {
      final timing = profile.timing;
      expect(timing.toleranceRatio.percent, 5);
      expect(timing.severityBands.bands, isNotEmpty);
      expect(timing.baseTolerance, isNull);
      expect(
        timing.toleranceRatio.toleranceMs(500),
        25,
        reason: 'tolerance is projected from an interval',
      );
      expect(
        timing.classifySeverity(deviationMs: 10, expectedIntervalMs: 500),
        SeverityTier.negligible,
        reason: 'a within-tolerance deviation still gets a severity label',
      );
      expect(
        timing.classifySeverity(deviationMs: 25, expectedIntervalMs: 500),
        SeverityTier.minor,
      );
      expect(
        timing.severityBands.toMap(),
        isNot(timing.toleranceRatio.toMap()),
      );
    },
  );

  // ---------------------------------------------------------------------------
  // §18 first-note anchor
  // ---------------------------------------------------------------------------

  test('H2.9I-30 - first note is the learner start anchor and lateness is not '
      'penalized', () {
    expect(profile.timing.firstNoteIsStartReference, isTrue);
    expect(profile.timing.firstNoteLatenessPenalized, isFalse);
    expect(timingMap()['first_note_is_start_reference'], isTrue);
    expect(timingMap()['first_note_lateness_penalized'], isFalse);
  });

  // ---------------------------------------------------------------------------
  // §19 order conformance
  // ---------------------------------------------------------------------------

  test('H2.9I-31 - inversion classes are distinct descriptive severities', () {
    final order = profile.order;
    expect(order.adjacentInversionSeverity, SeverityTier.minor);
    expect(order.partialInversionSeverity, SeverityTier.moderate);
    expect(order.fullReversalSeverity, SeverityTier.major);
    expect(
      order.adjacentInversionSeverity,
      isNot(order.partialInversionSeverity),
    );
    expect(order.partialInversionSeverity, isNot(order.fullReversalSeverity));
    expect(order.adjacentInversionSeverity, isNot(order.fullReversalSeverity));
  });

  test('H2.9I-32 - order severity is descriptive, not an automatic star '
      'verdict', () {
    final order = profile.order;
    expect(order.impactTier, OrderImpactTier.lowerThanPrimaryPitch);
    expect(order.independentOfPitch, isTrue);
    expect(order.rematchingAllowed, isFalse);
    final orderMap = order.toMap();
    expect(orderMap.containsKey('severity_bands'), isFalse);
    expect(orderMap.containsKey('threshold_ms'), isFalse);
    expect(orderMap.containsKey('star_verdict'), isFalse);
    expect(
      profile.stars.primarySeverityModel,
      PrimarySeverityModel.worstErrorWithMinorTrims,
      reason:
          'star impact is the shared star policy, not a per-dimension '
          'verdict',
    );
  });

  // ---------------------------------------------------------------------------
  // §20 IOI conformance
  // ---------------------------------------------------------------------------

  test('H2.9I-33 - IOI percentage boundaries below/at/above 5/10/20', () {
    final bands = profile.ioi.severityBands;
    expect(bands.classify(4.999), SeverityTier.negligible, reason: 'below 5');
    expect(bands.classify(5), SeverityTier.negligible, reason: 'at 5');
    expect(bands.classify(5.001), SeverityTier.minor, reason: 'above 5');
    expect(bands.classify(9.999), SeverityTier.minor, reason: 'below 10');
    expect(bands.classify(10), SeverityTier.minor, reason: 'at 10');
    expect(bands.classify(10.001), SeverityTier.moderate, reason: 'above 10');
    expect(bands.classify(19.999), SeverityTier.moderate, reason: 'below 20');
    expect(bands.classify(20), SeverityTier.moderate, reason: 'at 20');
    expect(bands.classify(20.001), SeverityTier.major, reason: 'above 20');
  });

  test('H2.9I-34 - IOI is configured independently from Timing', () {
    final ioi = profile.ioi;
    expect(ioi.comparisonBasis, 'learner_mean_interval');
    expect(ioi.doubleChargesTiming, isFalse);
    expect(ioi.tolerance, isNull);
    expect(
      ioi.severityBands,
      isNot(profile.timing.severityBands),
      reason: 'IOI bands are distinct data from timing bands',
    );
    expect(
      ioi.severityBands.toMap(),
      isNot(profile.timing.severityBands.toMap()),
    );
    expect(
      profile.timing.tempoDependencyKind,
      TimingTempoDependencyKind.normalizedRatio,
    );
  });

  // ---------------------------------------------------------------------------
  // §21 double-charge protection
  // ---------------------------------------------------------------------------

  test('H2.9I-35 - timing and IOI remain distinct dimensions with distinct '
      'reason codes', () {
    final timing = profile.timing;
    final ioi = profile.ioi;
    expect(
      timing.classifySeverity(deviationMs: 50, expectedIntervalMs: 500),
      SeverityTier.moderate,
    );
    expect(ioi.classifySeverity(6), SeverityTier.minor);
    expect(ioi.doubleChargesTiming, isFalse);
    expect(ErrorVectorReasonCode.timingEarly, isNotNull);
    expect(
      ErrorVectorReasonCode.timingLate,
      isNot(ErrorVectorReasonCode.ioiInconsistent),
    );
    expect(
      ErrorVectorReasonCode.ioiInconsistent,
      isNot(ErrorVectorReasonCode.timingEarly),
    );
    expect(
      ErrorVectorReasonCode.timingEarly,
      isNot(ErrorVectorReasonCode.timingLate),
    );
  });

  // ---------------------------------------------------------------------------
  // §22 simultaneity conformance
  // ---------------------------------------------------------------------------

  test('H2.9I-36 - beginner simultaneity boundaries below/at/above 40/80', () {
    final simultaneity = profile.simultaneity;
    expect(
      simultaneity.classifySeverity(LearnerLevelKey.beginner, 39.99),
      SeverityTier.negligible,
    );
    expect(
      simultaneity.classifySeverity(LearnerLevelKey.beginner, 40),
      SeverityTier.negligible,
    );
    expect(
      simultaneity.classifySeverity(LearnerLevelKey.beginner, 40.01),
      SeverityTier.minor,
    );
    expect(
      simultaneity.classifySeverity(LearnerLevelKey.beginner, 79.99),
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
  });

  test(
    'H2.9I-37 - intermediate simultaneity boundaries below/at/above 30/60',
    () {
      final simultaneity = profile.simultaneity;
      expect(
        simultaneity.classifySeverity(LearnerLevelKey.intermediate, 29.99),
        SeverityTier.negligible,
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
        simultaneity.classifySeverity(LearnerLevelKey.intermediate, 59.99),
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
    },
  );

  test('H2.9I-38 - advanced simultaneity boundaries below/at/above 20/40', () {
    final simultaneity = profile.simultaneity;
    expect(
      simultaneity.classifySeverity(LearnerLevelKey.advanced, 19.99),
      SeverityTier.negligible,
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
      simultaneity.classifySeverity(LearnerLevelKey.advanced, 39.99),
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

  test('H2.9I-39 - learner level is resolved from the existing '
      'policy-resolution context', () {
    for (final level in LearnerLevelKey.values) {
      final resolved = resolver.resolve(
        profile: profile,
        context: contextFor(TargetMode.block, level, 120),
      );
      expect(resolved.learnerLevel, level);
      expect(resolved.tempoBpm, 120);
      expect(level, isIn(profile.simultaneity.levelSeverityMs.keys));
      const toleranceSpecs = <String, int>{
        'BEGINNER': 40,
        'INTERMEDIATE': 30,
        'ADVANCED': 20,
      };
      expect(
        toleranceSpecs[level.serialName],
        profile.simultaneity.levelSeverityMs[level]!.bands.first.upperBound,
      );
    }
  });

  // ---------------------------------------------------------------------------
  // §23 missing members vs simultaneity; §24 extra notes vs simultaneity
  // ---------------------------------------------------------------------------

  test('H2.9I-40 - missing members do not invalidate simultaneity and extra '
      'notes are excluded from required-note simultaneity', () {
    expect(profile.simultaneity.missingMembersDoNotInvalidate, isTrue);
    expect(profile.stars.missingNote.invalidatesSimultaneity, isFalse);
    expect(profile.simultaneity.excludesExtraNotes, isTrue);
    expect(profile.stars.extraNote.excludedFromSimultaneity, isTrue);
    expect(
      profile.stars.missingNote.capTable.capForCount(1),
      isNotNull,
      reason: 'missing notes are represented separately',
    );
  });

  // ---------------------------------------------------------------------------
  // §25 star curve conformance
  // ---------------------------------------------------------------------------

  test(
    'H2.9I-41 - base star curve is exactly 5/5/4/3/2 and never fractional',
    () {
      expect(profile.stars.baseStars[SeverityTier.none], 5);
      expect(profile.stars.baseStars[SeverityTier.negligible], 5);
      expect(profile.stars.baseStars[SeverityTier.minor], 4);
      expect(profile.stars.baseStars[SeverityTier.moderate], 3);
      expect(profile.stars.baseStars[SeverityTier.major], 2);
      expect(profile.stars.fractionalStars, isFalse);
      expect(profile.stars.allowZeroStars, isTrue);
      expect(profile.stars.accumulation, StarAccumulationKind.cappedProgress);
      for (final tier in SeverityTier.values) {
        expect(profile.stars.baseStars[tier], isNotNull);
      }
      for (final band in StarQualityPolicy.standardBands) {
        expect(band.stars, inInclusiveRange(0, 5));
      }
    },
  );

  // ---------------------------------------------------------------------------
  // §26 trim conformance
  // ---------------------------------------------------------------------------

  test('H2.9I-42 - worst error establishes the base and itself creates no '
      'trim', () {
    expect(profile.stars.worstErrorEstablishesBase, isTrue);
    expect(profile.stars.worstErrorTrims, isFalse);
    expect(profile.stars.minimumTrimSeverity, SeverityTier.minor);
    expect(_simulateStars(profile.stars, const [SeverityTier.major]), 2);
    expect(_simulateStars(profile.stars, const [SeverityTier.minor]), 4);
    expect(_simulateStars(profile.stars, const [SeverityTier.moderate]), 3);
  });

  test('H2.9I-43 - additional dimensions at severity >= MINOR trim whole stars '
      'up to a maximum of two', () {
    expect(profile.stars.minorTrimCount, 2);
    expect(_simulateStars(profile.stars, const [SeverityTier.major]), 2);
    expect(
      _simulateStars(profile.stars, const [
        SeverityTier.major,
        SeverityTier.minor,
      ]),
      1,
    );
    expect(
      _simulateStars(profile.stars, const [
        SeverityTier.major,
        SeverityTier.minor,
        SeverityTier.minor,
      ]),
      0,
    );
    expect(
      _simulateStars(profile.stars, const [
        SeverityTier.major,
        SeverityTier.minor,
        SeverityTier.minor,
        SeverityTier.minor,
        SeverityTier.minor,
        SeverityTier.minor,
      ]),
      0,
      reason:
          'base 2 with three plus additional non-negligible errors still '
          'cap at two trims',
    );
  });

  test('H2.9I-44 - one NEGLIGIBLE extra never trims', () {
    expect(
      profile.stars.extraNote.severityByCount.classify(1),
      SeverityTier.negligible,
    );
    expect(profile.stars.minimumTrimSeverity, SeverityTier.minor);
    expect(_simulateStars(profile.stars, const [SeverityTier.negligible]), 5);
  });

  // ---------------------------------------------------------------------------
  // §27 0★ / 1★ / 2★ distinction
  // ---------------------------------------------------------------------------

  test('H2.9I-45 - 0★ / 1★ / 2★ are valid evaluated star values and 0★ is '
      'neither NEP nor FAILED', () {
    expect(profile.resultState.evaluatedMinStars, 0);
    expect(profile.resultState.evaluatedMaxStars, 5);
    final bandStars = StarQualityPolicy.standardBands
        .map((b) => b.stars)
        .toSet();
    expect(bandStars, containsAll(<int>[0, 1, 2]));
    expect(
      _simulateStars(profile.stars, const [
        SeverityTier.major,
        SeverityTier.minor,
        SeverityTier.minor,
      ]),
      0,
    );
    expect(
      profile.resultState.insufficientDataState,
      EvaluationResultState.notEnoughPerformance,
    );
    expect(profile.resultState.notEnoughPerformanceEqualsZeroStars, isFalse);
    expect(
      profile.resultState.lifecycleStatesOutsideResult,
      contains('FAILED'),
    );
    expect(
      profile.resultState.toMap()['produces_aggregate_pass_fail'],
      isFalse,
    );
  });

  // ---------------------------------------------------------------------------
  // §28 error vector conformance
  // ---------------------------------------------------------------------------

  test('H2.9I-46 - the Error Vector schema exposes exactly the eight decided '
      'diagnostic fields', () {
    const expectedKeys = <String>[
      'dimension',
      'severity',
      'reason_code',
      'expected_value',
      'observed_value',
      'signed_delta',
      'count',
      'context',
    ];
    final entry = ErrorVectorEntry(
      dimension: EvaluationDimension.ioi,
      severity: SeverityTier.moderate,
      reasonCode: ErrorVectorReasonCode.ioiInconsistent,
      expectedValue: 600,
      observedValue: 726,
      signedDelta: 126,
      count: 3,
      context: <String, Object?>{'pair_index': 1},
    );
    expect(entry.toMap().keys.toSet(), expectedKeys.toSet());
    expect(entry.dimension, EvaluationDimension.ioi);
    expect(entry.reasonCode, ErrorVectorReasonCode.ioiInconsistent);
    expect(entry.signedDelta, 126);
    expect(entry.count, 3);
    expect(entry.context, <String, Object?>{'pair_index': 1});

    final back = _errorVectorEntryFromMap(entry.toMap());
    expect(back, entry);
  });

  test('H2.9I-47 - reason-code vocabulary is exactly the closed eleven-code '
      'set', () {
    const lockedCodes = <String>[
      'PITCH_WRONG',
      'PITCH_MISSING',
      'PITCH_EXTRA',
      'TIMING_EARLY',
      'TIMING_LATE',
      'ORDER_ADJACENT_INVERSION',
      'ORDER_PARTIAL_INVERSION',
      'ORDER_FULL_REVERSAL',
      'IOI_INCONSISTENT',
      'SIMULTANEITY_SPREAD',
      'RETRIEVAL_LATENCY_UNAVAILABLE',
    ];
    expect(
      profile.errorVector.reasonCodes.map((c) => c.serialName).toSet(),
      lockedCodes.toSet(),
    );
    expect(ErrorVectorReasonCode.values.length, lockedCodes.length);
  });

  test('H2.9I-48 - Error Vector carries no stars, weights, mastery, scheduler, '
      'evidence or review', () {
    expect(profile.errorVector.descriptiveOnly, isTrue);
    expect(profile.errorVector.carriesStarsOrWeights, isFalse);
    expect(profile.errorVector.mutatesMasteryEvidence, isFalse);
    final map = profile.errorVector.toMap();
    expect(map.keys, isNot(contains('stars')));
    expect(map.keys, isNot(contains('weights')));
    expect(map.keys, isNot(contains('scheduler')));
    expect(map.keys, isNot(contains('evidence')));
    expect(map.keys, isNot(contains('review')));
    expect(map.keys, isNot(contains('mastery')));
  });

  // ---------------------------------------------------------------------------
  // §29 result-state conformance
  // ---------------------------------------------------------------------------

  test('H2.9I-49 - result vocabulary is exactly NOT_ENOUGH_PERFORMANCE and '
      'EVALUATED with stars 0..5', () {
    expect(
      EvaluationResultState.values.map((s) => s.serialName).toSet(),
      <String>{'NOT_ENOUGH_PERFORMANCE', 'EVALUATED'},
    );
    expect(
      profile.resultState.insufficientDataState,
      EvaluationResultState.notEnoughPerformance,
    );
    expect(profile.resultState.evaluatedMinStars, 0);
    expect(profile.resultState.evaluatedMaxStars, 5);
    expect(profile.resultState.producesAggregatePassFail, isFalse);
  });

  test('H2.9I-50 - lifecycle states remain outside the result and no PASS/FAIL '
      'aggregate exists', () {
    expect(
      profile.resultState.lifecycleStatesOutsideResult,
      containsAll(<String>['INVALIDATED', 'ABANDONED', 'FAILED']),
    );
    expect(
      profile.resultState.lifecycleStatesOutsideResult,
      isNot(contains('PASS')),
    );
    expect(profile.resultState.toMap().keys, isNot(contains('pass')));
    expect(profile.resultState.toMap().keys, isNot(contains('fail')));
    expect(
      profile.resultState.toMap()['produces_aggregate_pass_fail'],
      isFalse,
    );
  });

  // ---------------------------------------------------------------------------
  // §30 lesson star policy conformance
  // ---------------------------------------------------------------------------

  test('H2.9I-51 - lesson capacity 10 and tempo threshold 4 are policy values '
      'that support 12 -> display 10/10 without decay', () {
    expect(profile.stars.lessonStarCapacity, 10);
    expect(profile.stars.tempoProgressionThresholdStars, 4);
    expect(profile.stars.lessonStarsMonotonic, isTrue);
    expect(profile.stars.lessonStarsDecay, isFalse);
    expect(profile.stars.lessonStarsSeparateFromMastery, isTrue);
    expect(profile.stars.accumulation, StarAccumulationKind.cappedProgress);

    expect(_lessonDisplay(3), 3);
    expect(_lessonDisplay(7), 7);
    expect(_lessonDisplay(12), 10);
    expect(_lessonDisplay(30), 10);
  });

  // ---------------------------------------------------------------------------
  // §31 cross-dimension invariants
  // ---------------------------------------------------------------------------

  test('H2.9I-52 - invariants 1..13 hold concurrently', () {
    final stars = profile.stars;

    // INV-1 NOT_APPLICABLE -> no contribution (+/-).
    expect(profile.notApplicableHandling, NotApplicableHandling.distinct);
    expect(
      profile.applicability.stateFor(
        TargetMode.block,
        EvaluationDimension.order,
      ),
      EvaluationDimensionState.notApplicable,
    );
    expect(
      profile.applicability.stateFor(TargetMode.block, EvaluationDimension.ioi),
      EvaluationDimensionState.notApplicable,
    );
    expect(profile.resultState.producesAggregatePassFail, isFalse);

    // INV-2 UNAVAILABLE -> no automatic failure.
    expect(
      profile.retrievalLatency.unavailableHandling,
      UnavailableHandling.noPenalty,
    );
    expect(profile.retrievalLatency.producesSeverity, isFalse);
    expect(profile.retrievalLatency.producesStarImpact, isFalse);

    // INV-3 zero structural associations -> NOT_ENOUGH_PERFORMANCE.
    // INV-4 one or more -> evaluable.
    expect(_resultStateFor(0), EvaluationResultState.notEnoughPerformance);
    expect(_resultStateFor(1), EvaluationResultState.evaluated);
    expect(
      profile.evaluability.zeroAssociationsMeansNotEnoughPerformance,
      isTrue,
    );
    expect(profile.evaluability.requiresStructuralAssociation, isTrue);

    // INV-5 missing cap -> final ceiling.
    expect(stars.missingNote.appliedAfterBaseAndTrims, isTrue);
    expect(stars.missingNote.isCeilingNotSeverity, isTrue);

    // INV-6 extra notes -> never a hard cap.
    expect(stars.extraNote.imposesHardCap, isFalse);

    // INV-7 worst severity -> base; worst severity itself no trim.
    expect(stars.worstErrorEstablishesBase, isTrue);
    expect(stars.worstErrorTrims, isFalse);

    // INV-8 maximum trims = 2.
    expect(stars.minorTrimCount, 2);

    // INV-9 timing != ioi (distinct dimensions, bandwidths, comparison bases).
    expect(profile.timing.severityBands, isNot(profile.ioi.severityBands));
    expect(
      profile.timing.severityBands.toMap(),
      isNot(profile.ioi.severityBands.toMap()),
    );
    expect(profile.ioi.comparisonBasis, 'learner_mean_interval');

    // INV-10 stars != mastery.
    expect(stars.lessonStarsSeparateFromMastery, isTrue);
    expect(profile.errorVector.mutatesMasteryEvidence, isFalse);

    // INV-11 EvaluationResult != ReviewOutcome.
    expect(profile.resultState.toMap().keys, isNot(contains('review')));
    expect(profile.errorVector.toMap().keys, isNot(contains('review')));

    // INV-12 EvaluationResult != AttemptLifecycleState.
    expect(
      profile.resultState.lifecycleStatesOutsideResult,
      containsAll(<String>['INVALIDATED', 'ABANDONED', 'FAILED']),
    );
    expect(
      profile.resultState.toMap()['produces_aggregate_pass_fail'],
      isFalse,
    );

    // INV-13 Evaluation does not own H2.6 rematching.
    expect(profile.pitch.rematchingAllowed, isFalse);
    expect(profile.order.rematchingAllowed, isFalse);
    expect(profile.pitch.alignmentAuthority, 'H2.6');
    expect(profile.evaluability.associationAuthority, 'H2.6');
  });

  // ---------------------------------------------------------------------------
  // malformed-policy rejection (serialization-sourced)
  // ---------------------------------------------------------------------------

  test('H2.9I-53 - malformed serialized policy data is rejected '
      'deterministically', () {
    final base = profile.toMap();
    final dimensions = base['dimensions']! as Map<String, Object?>;
    final stars = base['stars']! as Map<String, Object?>;
    final missingTierStars = Map<String, Object?>.from(stars);
    missingTierStars['base_stars'] = <String, Object?>{
      'NONE': 5,
      'NEGLIGIBLE': 5,
      'MINOR': 4,
      'MODERATE': 3,
    };

    expect(
      () => _profileFromMap(<String, Object?>{
        ...base,
        'contract_version': 'nope',
      }).validate(),
      throwsFormatException,
      reason: 'an incompatible contract version must be rejected',
    );
    expect(
      () => _profileFromMap(<String, Object?>{
        ...base,
        'profile_id': 'mvp_default_v999',
      }).validate(),
      throwsFormatException,
      reason: 'an unknown profile identity must be rejected',
    );
    expect(
      () => _profileFromMap(<String, Object?>{
        ...base,
        'applicability': <String, Object?>{
          'block': <String, Object?>{
            'enabled': <String>['pitch', 'timing'],
            'not_applicable': <String>['pitch', 'order'],
          },
          'arpeggio': <String, Object?>{
            'enabled': <String>['pitch', 'timing'],
            'not_applicable': <String>['simultaneity'],
          },
        },
      }).validate(),
      throwsFormatException,
      reason: 'ambiguous applicability must be rejected',
    );
    expect(
      () => _profileFromMap(<String, Object?>{
        ...base,
        'stars': missingTierStars,
      }).validate(),
      throwsFormatException,
      reason: 'a missing base-star tier must be rejected',
    );
    expect(
      () => _profileFromMap(<String, Object?>{
        ...base,
        'dimensions': Map<String, Object?>.from(dimensions)..remove('pitch'),
      }),
      throwsFormatException,
      reason: 'a missing dimension policy must be rejected while parsing',
    );
  });
}

// ---------------------------------------------------------------------------
// Test-side articulation of locked contract rules. These are validation
// helpers only; none is production evaluation.
// ---------------------------------------------------------------------------

Map<String, Object?> timingMap() =>
    EvaluationPolicyProfile.instance.timing.toMap();

EvaluationResultState _resultStateFor(int requiredAssociations) =>
    requiredAssociations == 0
    ? EvaluationResultState.notEnoughPerformance
    : EvaluationResultState.evaluated;

int _lessonDisplay(int earnedStars) {
  final capacity = EvaluationPolicyProfile.instance.stars.lessonStarCapacity!;
  return earnedStars > capacity ? capacity : earnedStars;
}

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

// ---------------------------------------------------------------------------
// Test-only serialization deserializer. The policy layer is one-way
// materialized data; this helper reconstructs objects from `toMap()` output to
// prove §6 round-trip value equivalence without adding production code.
// ---------------------------------------------------------------------------

String _reqString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) {
    throw FormatException('missing required serialized key $key');
  }
  return value as String;
}

bool _reqBool(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) {
    throw FormatException('missing required serialized key $key');
  }
  return value as bool;
}

Map<String, Object?> _reqMap(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) {
    throw FormatException('missing required serialized key $key');
  }
  return value as Map<String, Object?>;
}

SeverityTier _severityFrom(String serial) => switch (serial) {
  'NONE' => SeverityTier.none,
  'NEGLIGIBLE' => SeverityTier.negligible,
  'MINOR' => SeverityTier.minor,
  'MODERATE' => SeverityTier.moderate,
  'MAJOR' => SeverityTier.major,
  _ => throw FormatException('unknown severity $serial'),
};

PolicyBoundary? _boundaryFrom(Object? value) => switch (value) {
  null => null,
  'INCLUSIVE' => PolicyBoundary.inclusive,
  'EXCLUSIVE' => PolicyBoundary.exclusive,
  _ => throw FormatException('unknown boundary $value'),
};

LearnerLevelKey _levelFrom(String serial) => switch (serial) {
  'BEGINNER' => LearnerLevelKey.beginner,
  'INTERMEDIATE' => LearnerLevelKey.intermediate,
  'ADVANCED' => LearnerLevelKey.advanced,
  _ => throw FormatException('unknown learner level $serial'),
};

EvaluationDimension _dimensionFrom(String serial) => switch (serial) {
  'pitch' => EvaluationDimension.pitch,
  'timing' => EvaluationDimension.timing,
  'order' => EvaluationDimension.order,
  'simultaneity' => EvaluationDimension.simultaneity,
  'ioi' => EvaluationDimension.ioi,
  'retrieval_latency' => EvaluationDimension.retrievalLatency,
  _ => throw FormatException('unknown dimension $serial'),
};

TargetMode _modeFrom(String name) => name == 'block'
    ? TargetMode.block
    : name == 'arpeggio'
    ? TargetMode.arpeggio
    : throw FormatException('unknown mode $name');

UnavailableHandling _unavailableFrom(Object? value) => switch (value) {
  'NO_PENALTY' => UnavailableHandling.noPenalty,
  'REDUCES_STARS' => UnavailableHandling.reducesStars,
  'INVALIDATES_ATTEMPT' => UnavailableHandling.invalidatesAttempt,
  _ => throw FormatException('unknown unavailable handling $value'),
};

ErrorVectorReasonCode _reasonFrom(String serial) => switch (serial) {
  'PITCH_WRONG' => ErrorVectorReasonCode.pitchWrong,
  'PITCH_MISSING' => ErrorVectorReasonCode.pitchMissing,
  'PITCH_EXTRA' => ErrorVectorReasonCode.pitchExtra,
  'TIMING_EARLY' => ErrorVectorReasonCode.timingEarly,
  'TIMING_LATE' => ErrorVectorReasonCode.timingLate,
  'ORDER_ADJACENT_INVERSION' => ErrorVectorReasonCode.orderAdjacentInversion,
  'ORDER_PARTIAL_INVERSION' => ErrorVectorReasonCode.orderPartialInversion,
  'ORDER_FULL_REVERSAL' => ErrorVectorReasonCode.orderFullReversal,
  'IOI_INCONSISTENT' => ErrorVectorReasonCode.ioiInconsistent,
  'SIMULTANEITY_SPREAD' => ErrorVectorReasonCode.simultaneitySpread,
  'RETRIEVAL_LATENCY_UNAVAILABLE' =>
    ErrorVectorReasonCode.retrievalLatencyUnavailable,
  _ => throw FormatException('unknown reason code $serial'),
};

TimingTempoDependencyKind _tempoKindFrom(Object? value) => switch (value) {
  'NORMALIZED_RATIO' => TimingTempoDependencyKind.normalizedRatio,
  _ => throw FormatException('unknown tempo dependency kind $value'),
};

List<SeverityBand> _bandsFromMap(Map<String, Object?> map) =>
    ((map['bands']! as List<Object?>).map((item) {
      final band = item! as Map<String, Object?>;
      return SeverityBand(
        severity: _severityFrom(band['severity']! as String),
        upperBound: band['upper_bound'] as num?,
        upperBoundary: _boundaryFrom(band['upper_boundary']),
      );
    })).toList(growable: false);

SeverityBandTable _tableFromMap(Map<String, Object?> map) =>
    SeverityBandTable(bands: _bandsFromMap(map));

ToleranceSpec? _toleranceFromMap(Map<String, Object?>? map) {
  if (map == null) {
    return null;
  }
  return ToleranceSpec(
    ms: map['ms'] as int?,
    boundary: _boundaryFrom(map['boundary']),
  );
}

ProportionalTolerance _proportionalFromMap(Map<String, Object?> map) =>
    ProportionalTolerance(
      percent: map['percent']! as int,
      rounding: switch (map['rounding']) {
        'NEAREST' => ToleranceRoundingMode.nearest,
        _ => throw FormatException('unknown rounding ${map['rounding']}'),
      },
    );

Map<LearnerLevelKey, SeverityBandTable> _levelTablesFromMap(Object? value) {
  final raw = value! as Map<String, Object?>;
  return Map.unmodifiable(<LearnerLevelKey, SeverityBandTable>{
    for (final entry in raw.entries)
      _levelFrom(entry.key): _tableFromMap(
        entry.value! as Map<String, Object?>,
      ),
  });
}

Map<LearnerLevelKey, ToleranceSpec> _levelTolerancesFromMap(Object? value) {
  final raw = value! as Map<String, Object?>;
  return Map.unmodifiable(<LearnerLevelKey, ToleranceSpec>{
    for (final entry in raw.entries)
      _levelFrom(entry.key): _toleranceFromMap(
        entry.value! as Map<String, Object?>,
      )!,
  });
}

MissingNoteCapTable _capTableFromMap(Map<String, Object?> map) =>
    MissingNoteCapTable(
      caps: ((map['caps']! as List<Object?>).map((item) {
        final cap = item! as Map<String, Object?>;
        return MissingNoteCap(
          minimumMissingCount: cap['minimum_missing_count']! as int,
          maxStars: cap['max_stars'] as int?,
        );
      })).toList(growable: false),
    );

MissingNoteStarPolicy _missingNoteFromMap(Map<String, Object?> map) =>
    MissingNoteStarPolicy(
      countSensitive: _reqBool(map, 'count_sensitive'),
      oneMissingNoteCapStars: map['one_missing_note_cap_stars'] as int?,
      perAdditionalMissingCapStars:
          map['per_additional_missing_cap_stars'] as int?,
      capTable: _capTableFromMap(_reqMap(map, 'cap_table')),
      appliedAfterBaseAndTrims: _reqBool(map, 'applied_after_base_and_trims'),
      isCeilingNotSeverity: _reqBool(map, 'is_ceiling_not_severity'),
      invalidatesSimultaneity: _reqBool(map, 'invalidates_simultaneity'),
    );

ExtraNoteStarPolicy _extraNoteFromMap(Map<String, Object?> map) =>
    ExtraNoteStarPolicy(
      imposesHardCap: _reqBool(map, 'imposes_hard_cap'),
      hardCapStars: map['hard_cap_stars'] as int?,
      excludedFromSimultaneity: _reqBool(map, 'excluded_from_simultaneity'),
      severityByCount: _tableFromMap(_reqMap(map, 'severity_by_count')),
    );

StarQualityPolicy _starQualityFromMap(Map<String, Object?> map) {
  final baseStarsRaw = map['base_stars']! as Map<String, Object?>;
  return StarQualityPolicy(
    primarySeverityModel: switch (map['primary_severity_model']) {
      'WORST_ERROR_WITH_MINOR_TRIMS' =>
        PrimarySeverityModel.worstErrorWithMinorTrims,
      _ => throw FormatException(
        'unknown primary severity model ${map['primary_severity_model']}',
      ),
    },
    allowZeroStars: _reqBool(map, 'allow_zero_stars'),
    minorTrimCount: map['minor_trim_count'] as int?,
    missingNote: _missingNoteFromMap(_reqMap(map, 'missing_note')),
    extraNote: _extraNoteFromMap(_reqMap(map, 'extra_note')),
    lessonStarCapacity: map['lesson_star_capacity'] as int?,
    accumulation: switch (map['accumulation']) {
      'CAPPED_PROGRESS' => StarAccumulationKind.cappedProgress,
      _ => throw FormatException('unknown accumulation ${map['accumulation']}'),
    },
    baseStars: <SeverityTier, int>{
      for (final entry in baseStarsRaw.entries)
        _severityFrom(entry.key): entry.value! as int,
    },
    minimumTrimSeverity: _severityFrom(
      _reqString(map, 'minimum_trim_severity'),
    ),
    worstErrorEstablishesBase: _reqBool(map, 'worst_error_establishes_base'),
    worstErrorTrims: _reqBool(map, 'worst_error_trims'),
    fractionalStars: _reqBool(map, 'fractional_stars'),
    lessonStarsMonotonic: _reqBool(map, 'lesson_stars_monotonic'),
    lessonStarsDecay: _reqBool(map, 'lesson_stars_decay'),
    lessonStarsSeparateFromMastery: _reqBool(
      map,
      'lesson_stars_separate_from_mastery',
    ),
    tempoProgressionThresholdStars:
        map['tempo_progression_threshold_stars'] as int?,
    bands: ((map['bands']! as List<Object?>).map((item) {
      final band = item! as Map<String, Object?>;
      return StarBand(
        stars: band['stars']! as int,
        upperBoundary: _boundaryFrom(band['upper_boundary']),
      );
    })).toList(growable: false),
  );
}

PitchPolicySpec _pitchFromMap(Map<String, Object?> map) => PitchPolicySpec(
  unavailableHandling: _unavailableFrom(map['unavailable_handling']),
  exactMidiIdentity: _reqBool(map, 'exact_midi_identity'),
  oneToOneMatching: _reqBool(map, 'one_to_one_matching'),
  toleranceApplied: _reqBool(map, 'tolerance_applied'),
  spellingComparison: _reqBool(map, 'spelling_comparison'),
  rematchingAllowed: _reqBool(map, 'rematching_allowed'),
  alignmentAuthority: _reqString(map, 'alignment_authority'),
  extraNotesArePitchErrors: _reqBool(map, 'extra_notes_are_pitch_errors'),
  wrongNoteSeverity: _tableFromMap(_reqMap(map, 'wrong_note_severity')),
);

TimingPolicySpec _timingFromMap(Map<String, Object?> map) => TimingPolicySpec(
  unavailableHandling: _unavailableFrom(map['unavailable_handling']),
  firstNoteIsStartReference: _reqBool(map, 'first_note_is_start_reference'),
  firstNoteLatenessPenalized: _reqBool(map, 'first_note_lateness_penalized'),
  tightensWithTempo: _reqBool(map, 'tightens_with_tempo'),
  tempoDependencyKind: _tempoKindFrom(map['tempo_dependency_kind']),
  baseTolerance: _toleranceFromMap(
    map['base_tolerance'] as Map<String, Object?>?,
  ),
  toleranceRatio: _proportionalFromMap(_reqMap(map, 'tolerance_ratio')),
  severityBands: _tableFromMap(_reqMap(map, 'severity_bands')),
  severityReferenceIntervalMs: map['severity_reference_interval_ms']! as num,
);

OrderPolicySpec _orderFromMap(Map<String, Object?> map) => OrderPolicySpec(
  unavailableHandling: _unavailableFrom(map['unavailable_handling']),
  impactTier: switch (map['impact_tier']) {
    'LOWER_THAN_PRIMARY_PITCH' => OrderImpactTier.lowerThanPrimaryPitch,
    _ => throw FormatException('unknown impact tier ${map['impact_tier']}'),
  },
  adjacentInversionSeverity: _severityFrom(
    _reqString(map, 'adjacent_inversion_severity'),
  ),
  partialInversionSeverity: _severityFrom(
    _reqString(map, 'partial_inversion_severity'),
  ),
  fullReversalSeverity: _severityFrom(
    _reqString(map, 'full_reversal_severity'),
  ),
  independentOfPitch: _reqBool(map, 'independent_of_pitch'),
  rematchingAllowed: _reqBool(map, 'rematching_allowed'),
);

IoiPolicySpec _ioiFromMap(Map<String, Object?> map) => IoiPolicySpec(
  unavailableHandling: _unavailableFrom(map['unavailable_handling']),
  tolerance: _toleranceFromMap(map['tolerance'] as Map<String, Object?>?),
  severityBands: _tableFromMap(_reqMap(map, 'severity_bands')),
  comparisonBasis: _reqString(map, 'comparison_basis'),
  doubleChargesTiming: _reqBool(map, 'double_charges_timing'),
);

SimultaneityPolicySpec _simultaneityFromMap(Map<String, Object?> map) =>
    SimultaneityPolicySpec(
      unavailableHandling: _unavailableFrom(map['unavailable_handling']),
      levelTolerances: _levelTolerancesFromMap(map['level_tolerances']),
      levelSeverityMs: _levelTablesFromMap(map['level_severity_ms']),
      missingMembersDoNotInvalidate: _reqBool(
        map,
        'missing_members_do_not_invalidate',
      ),
      excludesExtraNotes: _reqBool(map, 'excludes_extra_notes'),
    );

RetrievalLatencyPolicySpec _retrievalFromMap(Map<String, Object?> map) =>
    RetrievalLatencyPolicySpec(
      unavailableHandling: _unavailableFrom(map['unavailable_handling']),
      enabledForAllModes: _reqBool(map, 'enabled_for_all_modes'),
      producesSeverity: _reqBool(map, 'produces_severity'),
      producesStarImpact: _reqBool(map, 'produces_star_impact'),
      unavailableReasonCode: _reasonFrom(
        _reqString(map, 'unavailable_reason_code'),
      ),
    );

EvaluabilityPolicy _evaluabilityFromMap(Map<String, Object?> map) =>
    EvaluabilityPolicy(
      requiresStructuralAssociation: _reqBool(
        map,
        'requires_structural_association',
      ),
      basedOnPitchCorrectness: _reqBool(map, 'based_on_pitch_correctness'),
      zeroAssociationsMeansNotEnoughPerformance: _reqBool(
        map,
        'zero_associations_means_not_enough_performance',
      ),
      associationAuthority: _reqString(map, 'association_authority'),
    );

ResultStatePolicy _resultStateFromMap(Map<String, Object?> map) =>
    ResultStatePolicy(
      insufficientDataState: switch (map['insufficient_data_state']) {
        'NOT_ENOUGH_PERFORMANCE' => EvaluationResultState.notEnoughPerformance,
        'EVALUATED' => EvaluationResultState.evaluated,
        _ => throw FormatException(
          'unknown result state ${map['insufficient_data_state']}',
        ),
      },
      evaluatedMinStars: map['evaluated_min_stars']! as int,
      evaluatedMaxStars: map['evaluated_max_stars']! as int,
      producesAggregatePassFail: _reqBool(map, 'produces_aggregate_pass_fail'),
      notEnoughPerformanceEqualsZeroStars: _reqBool(
        map,
        'not_enough_performance_equals_zero_stars',
      ),
      lifecycleStatesOutsideResult:
          ((map['lifecycle_states_outside_result']! as List<Object?>).map(
            (s) => s! as String,
          )).toList(growable: false),
    );

ErrorVectorPolicy _errorVectorPolicyFromMap(Map<String, Object?> map) =>
    ErrorVectorPolicy(
      reasonCodes: ((map['reason_codes']! as List<Object?>).map(
        (s) => _reasonFrom(s! as String),
      )).toList(growable: false),
      descriptiveOnly: _reqBool(map, 'descriptive_only'),
      carriesStarsOrWeights: _reqBool(map, 'carries_stars_or_weights'),
      mutatesMasteryEvidence: _reqBool(map, 'mutates_mastery_evidence'),
    );

ErrorVectorEntry _errorVectorEntryFromMap(Map<String, Object?> map) =>
    ErrorVectorEntry(
      dimension: _dimensionFrom(_reqString(map, 'dimension')),
      severity: _severityFrom(_reqString(map, 'severity')),
      reasonCode: _reasonFrom(_reqString(map, 'reason_code')),
      expectedValue: map['expected_value'],
      observedValue: map['observed_value'],
      signedDelta: map['signed_delta'] as num?,
      count: map['count'] as int?,
      context: (map['context'] as Map<String, Object?>?) == null
          ? null
          : Map<String, Object?>.from(map['context']! as Map<String, Object?>),
    );

EvaluationPolicyApplicability _applicabilityFromMap(Map<String, Object?> map) {
  final enabled = <TargetMode, Set<EvaluationDimension>>{};
  final notApplicable = <TargetMode, Set<EvaluationDimension>>{};
  for (final name in <String>['block', 'arpeggio']) {
    final mode = _modeFrom(name);
    final entry = map[name]! as Map<String, Object?>;
    enabled[mode] = ((entry['enabled']! as List<Object?>).map(
      (s) => _dimensionFrom(s! as String),
    )).toSet();
    notApplicable[mode] = ((entry['not_applicable']! as List<Object?>).map(
      (s) => _dimensionFrom(s! as String),
    )).toSet();
  }
  return EvaluationPolicyApplicability(
    enabled: enabled,
    notApplicable: notApplicable,
  );
}

PolicyResolutionLayer _layerFrom(String serial) => switch (serial) {
  'PROFILE' => PolicyResolutionLayer.profile,
  'LEARNER_LEVEL' => PolicyResolutionLayer.learnerLevel,
  'SKILL' => PolicyResolutionLayer.skill,
  'EXERCISE_MODE' => PolicyResolutionLayer.exerciseMode,
  'TEMPO_RANGE' => PolicyResolutionLayer.tempoRange,
  'DIMENSION_OVERRIDE' => PolicyResolutionLayer.dimensionOverride,
  _ => throw FormatException('unknown resolution layer $serial'),
};

EvaluationPolicyProfile _profileFromMap(Map<String, Object?> map) {
  final provenance = _reqMap(map, 'provenance');
  final dimensions = _reqMap(map, 'dimensions');
  return EvaluationPolicyProfile(
    profileIdValue: _reqString(map, 'profile_id'),
    contractVersionValue: _reqString(map, 'contract_version'),
    policyVersionValue: _reqString(map, 'policy_version'),
    provenance: ContractSourceProvenance(
      sourceKind: _reqString(provenance, 'source_kind'),
      sourcePath: _reqString(provenance, 'source_path'),
      sourceIdentifier: _reqString(provenance, 'source_identifier'),
    ),
    pitch: _pitchFromMap(_reqMap(dimensions, 'pitch')),
    timing: _timingFromMap(_reqMap(dimensions, 'timing')),
    order: _orderFromMap(_reqMap(dimensions, 'order')),
    simultaneity: _simultaneityFromMap(_reqMap(dimensions, 'simultaneity')),
    ioi: _ioiFromMap(_reqMap(dimensions, 'ioi')),
    retrievalLatency: _retrievalFromMap(
      _reqMap(dimensions, 'retrieval_latency'),
    ),
    stars: _starQualityFromMap(_reqMap(map, 'stars')),
    evaluability: _evaluabilityFromMap(_reqMap(map, 'evaluability')),
    resultState: _resultStateFromMap(_reqMap(map, 'result_state')),
    errorVector: _errorVectorPolicyFromMap(_reqMap(map, 'error_vector')),
    applicability: _applicabilityFromMap(_reqMap(map, 'applicability')),
    notApplicableHandling: switch (map['not_applicable_handling']) {
      'DISTINCT' => NotApplicableHandling.distinct,
      'AUTO_SUCCESS' => NotApplicableHandling.autoSuccess,
      _ => throw FormatException(
        'unknown not-applicable handling ${map['not_applicable_handling']}',
      ),
    },
    appliedResolutionDepth: switch (map['applied_resolution_depth']) {
      'PROFILE' => PolicyResolutionLayer.profile,
      _ => throw FormatException(
        'unknown applied resolution depth ${map['applied_resolution_depth']}',
      ),
    },
    unresolvedPrecedenceLayers:
        ((map['unresolved_precedence_layers']! as List<Object?>).map(
          (s) => _layerFrom(s! as String),
        )).toSet(),
  );
}
