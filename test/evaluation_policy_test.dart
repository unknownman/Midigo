import 'package:flutter_test/flutter_test.dart';
import 'package:miditutor/midi/domain/evaluation_input.dart';
import 'package:miditutor/midi/domain/evaluation_policy.dart';
import 'package:miditutor/midi/domain/expected_musical_target.dart';

void main() {
  final EvaluationPolicyProfile profile = EvaluationPolicyProfile.instance;

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
    expect(profile.stars.missingNote.perAdditionalMissingCapStars, isNull);
    expect(profile.stars.extraNote.imposesHardCap, isFalse);
    expect(profile.stars.extraNote.hardCapStars, isNull);
    expect(profile.stars.lessonStarCapacity, 10);
    expect(profile.stars.accumulation, StarAccumulationKind.cappedProgress);
  });

  test('T4 - no invented threshold: all policy values stay unresolved', () {
    expect(profile.containsResolvedDimensionThresholds, isFalse);
    expect(profile.timing.baseTolerance, isNull);
    expect(profile.ioi.tolerance, isNull);
    for (final tolerance in profile.simultaneity.levelTolerances.values) {
      expect(tolerance.isResolved, isFalse);
    }
    expect(profile.stars.minorTrimCount, isNull);
    expect(profile.stars.anyBandBoundaryResolved, isFalse);
    for (final band in profile.stars.bands) {
      expect(band.upperBoundary, isNull);
    }

    final msValues = <int>[];
    _collectThresholdValues(profile.toMap(), msValues);
    expect(
      msValues,
      isEmpty,
      reason: 'no numeric evaluation threshold may be materialized',
    );
  });

  test('T5 - tempo-dependent timing: direction decided, model unresolved', () {
    expect(profile.timing.tempoDependencyKind, isNull);
    expect(profile.timing.tightensWithTempo, isTrue);
  });

  test('T6 - level-sensitive simultaneity: vocabulary present, values '
      'unresolved, immutable', () {
    expect(
      profile.simultaneity.levelTolerances.keys,
      containsAll(<LearnerLevelKey>[
        LearnerLevelKey.beginner,
        LearnerLevelKey.intermediate,
        LearnerLevelKey.advanced,
      ]),
    );
    expect(
      profile.simultaneity.levelTolerances[LearnerLevelKey.beginner]!.ms,
      isNull,
    );
    expect(
      profile.simultaneity.levelTolerances[LearnerLevelKey.intermediate]!.ms,
      isNull,
    );
    expect(
      profile.simultaneity.levelTolerances[LearnerLevelKey.advanced]!.ms,
      isNull,
    );
    expect(
      () => (profile.simultaneity.levelTolerances as dynamic).clear(),
      throwsUnsupportedError,
    );
  });

  test(
    'T7 - deterministic resolution mirrors locked profile applicability',
    () {
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
      expect(block.containsResolvedDimensionThresholds, isFalse);

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

      final arpeggio = resolver.resolve(
        profile: profile,
        context: const PolicyResolutionContext(
          profileId: 'mvp_default_v1',
          profileVersion: 'v1.1',
          mode: TargetMode.arpeggio,
        ),
      );
      for (final dimension in EvaluationDimension.values) {
        final resolved = arpeggio.dimensions.firstWhere(
          (d) => d.dimension == dimension,
        );
        final expected =
            MvpDefaultEvaluationProfile.instance.isDimensionEnabled(
              TargetMode.arpeggio,
              dimension,
            )
            ? EvaluationDimensionState.enabled
            : EvaluationDimensionState.notApplicable;
        expect(
          resolved.state,
          expected,
          reason:
              'arpeggio applicability of $dimension must mirror the profile',
        );
      }

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

      final blockAgainSameContext = resolver.resolve(
        profile: profile,
        context: const PolicyResolutionContext(
          profileId: 'mvp_default_v1',
          profileVersion: 'v1.1',
          mode: TargetMode.block,
        ),
      );
      final blockAgainSameContext2 = resolver.resolve(
        profile: profile,
        context: const PolicyResolutionContext(
          profileId: 'mvp_default_v1',
          profileVersion: 'v1.1',
          mode: TargetMode.block,
        ),
      );
      expect(
        blockAgainSameContext == blockAgainSameContext2,
        isTrue,
        reason: 'identical context must resolve identically every time',
      );

      expect(
        block == blockAgainSameContext,
        isFalse,
        reason: 'learning context does not alter profile applicability',
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

    final EvaluationPolicyProfile other = EvaluationPolicyProfile.build();
    expect(
      () => (other.unresolvedPrecedenceLayers as dynamic).clear(),
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
}

void _collectThresholdValues(Map<String, Object?> map, List<int> values) {
  for (final entry in map.entries) {
    final value = entry.value;
    final bool isThresholdKey = entry.key == 'ms' || entry.key.endsWith('_ms');
    if (isThresholdKey && value is int) {
      values.add(value);
    } else if (value is Map<String, Object?>) {
      _collectThresholdValues(value, values);
    } else if (value is List) {
      for (final item in value) {
        if (item is Map<String, Object?>) {
          _collectThresholdValues(item, values);
        }
      }
    }
  }
}
