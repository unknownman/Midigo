import 'evaluation_contract.dart' show ContractSourceProvenance;
import 'evaluation_input.dart'
    show
        EvaluationDimension,
        EvaluationDimensionState,
        MvpDefaultEvaluationProfile;
import 'expected_musical_target.dart' show TargetMode;

/// Explicit inclusive/exclusive selection for any policy boundary.
///
/// Boundary interpretation must never be implicit. Any policy value must
/// declare whether the boundary is inclusive (`<= threshold`) or exclusive
/// (`< threshold`). No product boundary value exists yet, so every boundary
/// slot is currently unresolved (null).
enum PolicyBoundary {
  inclusive,
  exclusive;

  String get serialName => switch (this) {
    PolicyBoundary.inclusive => 'INCLUSIVE',
    PolicyBoundary.exclusive => 'EXCLUSIVE',
  };
}

/// Learner-level vocabulary used by level-sensitive policies (for example
/// chord simultaneity tolerance tightening with level). The vocabulary is
/// materialized; every numeric mapping stays unresolved.
enum LearnerLevelKey {
  beginner,
  intermediate,
  advanced;

  String get serialName => switch (this) {
    LearnerLevelKey.beginner => 'BEGINNER',
    LearnerLevelKey.intermediate => 'INTERMEDIATE',
    LearnerLevelKey.advanced => 'ADVANCED',
  };
}

/// Candidate mathematical models for tempo-dependent timing tolerance.
///
/// The product direction (faster tempo -> tighter tolerance) is recorded by
/// [TimingPolicySpec.tightensWithTempo]; the model that expresses it is NOT
/// chosen by the repository yet. The evaluator must not assume any one model.
enum TimingTempoDependencyKind {
  lookupTable,
  piecewiseRanges,
  normalizedRatio,
  formulaReference,
  tempoCurve;

  String get serialName => switch (this) {
    TimingTempoDependencyKind.lookupTable => 'LOOKUP_TABLE',
    TimingTempoDependencyKind.piecewiseRanges => 'PIECEWISE_RANGES',
    TimingTempoDependencyKind.normalizedRatio => 'NORMALIZED_RATIO',
    TimingTempoDependencyKind.formulaReference => 'FORMULA_REFERENCE',
    TimingTempoDependencyKind.tempoCurve => 'TEMPO_CURVE',
  };
}

/// How an ENABLED + UNAVAILABLE dimension must be handled.
///
/// Decided product direction: no penalty. The evaluator must never translate
/// unavailable data into failure.
enum UnavailableHandling {
  noPenalty,
  reducesStars,
  invalidatesAttempt;

  String get serialName => switch (this) {
    UnavailableHandling.noPenalty => 'NO_PENALTY',
    UnavailableHandling.reducesStars => 'REDUCES_STARS',
    UnavailableHandling.invalidatesAttempt => 'INVALIDATES_ATTEMPT',
  };
}

/// How a NOT_APPLICABLE dimension must be surfaced.
///
/// Decided product direction: remain semantically distinct (for example shown
/// as "Not applicable"); never treated as automatically passed.
enum NotApplicableHandling {
  distinct,
  autoSuccess;

  String get serialName => switch (this) {
    NotApplicableHandling.distinct => 'DISTINCT',
    NotApplicableHandling.autoSuccess => 'AUTO_SUCCESS',
  };
}

/// How the primary star tier is selected from dimension results.
///
/// Decided product direction: the largest error determines the primary quality
/// tier; additional smaller errors may apply minor trims.
enum PrimarySeverityModel {
  worstErrorWithMinorTrims;

  String get serialName => switch (this) {
    PrimarySeverityModel.worstErrorWithMinorTrims =>
      'WORST_ERROR_WITH_MINOR_TRIMS',
  };
}

/// Order impact classification relative to primary pitch errors.
enum OrderImpactTier {
  lowerThanPrimaryPitch;

  String get serialName => switch (this) {
    OrderImpactTier.lowerThanPrimaryPitch => 'LOWER_THAN_PRIMARY_PITCH',
  };
}

/// Lesson-level star accumulation rule.
///
/// Decided: progress is tracked against the lesson's total star capacity. The
/// exact accumulation semantics (cumulative sums vs best-result) remain
/// [unspecified].
enum StarAccumulationKind {
  unspecified,
  cumulative,
  bestResult,
  cappedProgress;

  String get serialName => switch (this) {
    StarAccumulationKind.unspecified => 'UNSPECIFIED',
    StarAccumulationKind.cumulative => 'CUMULATIVE',
    StarAccumulationKind.bestResult => 'BEST_RESULT',
    StarAccumulationKind.cappedProgress => 'CAPPED_PROGRESS',
  };
}

/// Candidate precedence layers for future policy resolution.
///
/// Only [profile] (plus the locked per-mode applicability) is currently
/// resolved. Every deeper layer is explicitly unresolved so that no precedence
/// is silently assumed.
enum PolicyResolutionLayer {
  profile,
  learnerLevel,
  skill,
  exerciseMode,
  tempoRange,
  dimensionOverride;

  String get serialName => switch (this) {
    PolicyResolutionLayer.profile => 'PROFILE',
    PolicyResolutionLayer.learnerLevel => 'LEARNER_LEVEL',
    PolicyResolutionLayer.skill => 'SKILL',
    PolicyResolutionLayer.exerciseMode => 'EXERCISE_MODE',
    PolicyResolutionLayer.tempoRange => 'TEMPO_RANGE',
    PolicyResolutionLayer.dimensionOverride => 'DIMENSION_OVERRIDE',
  };
}

/// A policy tolerance value. Unresolved until the product defines it.
///
/// When [ms] is present, an explicit [PolicyBoundary] is REQUIRED so that
/// inclusive vs exclusive is never ambiguous. A boundary without a value is not
/// representable.
final class ToleranceSpec {
  final int? ms;
  final PolicyBoundary? boundary;

  ToleranceSpec({this.ms, this.boundary}) {
    if (ms != null && boundary == null) {
      throw const FormatException(
        'ToleranceSpec: a value requires an explicit boundary.',
      );
    }
    if (ms == null && boundary != null) {
      throw const FormatException(
        'ToleranceSpec: a boundary without a value is not representable.',
      );
    }
  }

  bool get isResolved => ms != null;

  Map<String, Object?> toMap() => <String, Object?>{
    'ms': ms,
    'boundary': boundary?.serialName,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToleranceSpec && other.ms == ms && other.boundary == boundary;

  @override
  int get hashCode => Object.hash(ms, boundary);
}

/// One band of the 5..0 star quality model.
///
/// The band slot exists so the star model can evolve without the evaluator.
/// [upperBoundary] is the inclusive/exclusive boundary of the band's threshold;
/// it is null until a product value defines the band.
final class StarBand {
  final int stars;
  final PolicyBoundary? upperBoundary;

  const StarBand({required this.stars, this.upperBoundary})
    : assert(stars >= 0 && stars <= 5, 'StarBand: stars must be within 0..5.');

  bool get isResolved => upperBoundary != null;

  Map<String, Object?> toMap() => <String, Object?>{
    'stars': stars,
    'upper_boundary': upperBoundary?.serialName,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StarBand &&
          other.stars == stars &&
          other.upperBoundary == upperBoundary;

  @override
  int get hashCode => Object.hash(stars, upperBoundary);
}

/// Missing-note star behavior.
///
/// Decided: one missing note in an otherwise clean performance caps at 4
/// stars; missing notes are count-sensitive. Per-additional-note steps and all
/// band widths remain unresolved.
final class MissingNoteStarPolicy {
  final bool countSensitive;
  final int? oneMissingNoteCapStars;
  final int? perAdditionalMissingCapStars;

  const MissingNoteStarPolicy({
    required this.countSensitive,
    required this.oneMissingNoteCapStars,
    required this.perAdditionalMissingCapStars,
  });

  Map<String, Object?> toMap() => <String, Object?>{
    'count_sensitive': countSensitive,
    'one_missing_note_cap_stars': oneMissingNoteCapStars,
    'per_additional_missing_cap_stars': perAdditionalMissingCapStars,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MissingNoteStarPolicy &&
          other.countSensitive == countSensitive &&
          other.oneMissingNoteCapStars == oneMissingNoteCapStars &&
          other.perAdditionalMissingCapStars == perAdditionalMissingCapStars;

  @override
  int get hashCode => Object.hash(
    countSensitive,
    oneMissingNoteCapStars,
    perAdditionalMissingCapStars,
  );
}

/// Extra-note star behavior.
///
/// Decided: extra notes do not impose a hard star cap.
final class ExtraNoteStarPolicy {
  final bool imposesHardCap;
  final int? hardCapStars;

  const ExtraNoteStarPolicy({
    required this.imposesHardCap,
    required this.hardCapStars,
  });

  Map<String, Object?> toMap() => <String, Object?>{
    'imposes_hard_cap': imposesHardCap,
    'hard_cap_stars': hardCapStars,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExtraNoteStarPolicy &&
          other.imposesHardCap == imposesHardCap &&
          other.hardCapStars == hardCapStars;

  @override
  int get hashCode => Object.hash(imposesHardCap, hardCapStars);
}

/// The 5..0 star quality policy.
///
/// Band thresholds are UNRESOLVED. Decided semantics are materialized:
/// worst-error-with-minor-trims primary model, 0 stars permitted for a real
/// poor performance, no star cap by default, lesson capacity 10 stars,
/// progress tracked against capacity. Minor-trim count is unresolved.
final class StarQualityPolicy {
  final PrimarySeverityModel primarySeverityModel;
  final bool allowZeroStars;
  final int? minorTrimCount;
  final MissingNoteStarPolicy missingNote;
  final ExtraNoteStarPolicy extraNote;
  final int? lessonStarCapacity;
  final StarAccumulationKind accumulation;

  final List<StarBand> bands;

  static const List<StarBand> standardBands = <StarBand>[
    StarBand(stars: 5),
    StarBand(stars: 4),
    StarBand(stars: 3),
    StarBand(stars: 2),
    StarBand(stars: 1),
    StarBand(stars: 0),
  ];

  StarQualityPolicy({
    required this.primarySeverityModel,
    required this.allowZeroStars,
    required this.minorTrimCount,
    required this.missingNote,
    required this.extraNote,
    required this.lessonStarCapacity,
    required this.accumulation,
    required List<StarBand> bands,
  }) : bands = List<StarBand>.unmodifiable(bands) {
    if (bands.length != standardBands.length) {
      throw const FormatException(
        'StarQualityPolicy: the star model must expose bands 5..0.',
      );
    }
  }

  bool get anyBandBoundaryResolved => bands.any((band) => band.isResolved);

  Map<String, Object?> toMap() => <String, Object?>{
    'primary_severity_model': primarySeverityModel.serialName,
    'allow_zero_stars': allowZeroStars,
    'minor_trim_count': minorTrimCount,
    'missing_note': missingNote.toMap(),
    'extra_note': extraNote.toMap(),
    'lesson_star_capacity': lessonStarCapacity,
    'accumulation': accumulation.serialName,
    'bands': bands.map((band) => band.toMap()).toList(growable: false),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StarQualityPolicy &&
          other.primarySeverityModel == primarySeverityModel &&
          other.allowZeroStars == allowZeroStars &&
          other.minorTrimCount == minorTrimCount &&
          other.missingNote == missingNote &&
          other.extraNote == extraNote &&
          other.lessonStarCapacity == lessonStarCapacity &&
          other.accumulation == accumulation &&
          _starBandListEq(other.bands, bands);

  @override
  int get hashCode => Object.hash(
    primarySeverityModel,
    allowZeroStars,
    minorTrimCount,
    missingNote,
    extraNote,
    lessonStarCapacity,
    accumulation,
    Object.hashAll(bands),
  );
}

/// Base of the six independent per-dimension policy specifications.
///
/// Every dimension carries its own typed spec; there is no generic unified
/// threshold wrapper that would damage type safety.
sealed class DimensionPolicySpec {
  final UnavailableHandling unavailableHandling;

  const DimensionPolicySpec({required this.unavailableHandling});

  Map<String, Object?> toMap();
}

/// Pitch policy. No comparison tolerance is established in the repository;
/// the spec remains an explicit, upgradeable slot.
final class PitchPolicySpec extends DimensionPolicySpec {
  const PitchPolicySpec({
    super.unavailableHandling = UnavailableHandling.noPenalty,
  });

  @override
  Map<String, Object?> toMap() => <String, Object?>{
    'unavailable_handling': unavailableHandling.serialName,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PitchPolicySpec &&
          other.unavailableHandling == unavailableHandling;

  @override
  int get hashCode => unavailableHandling.hashCode;
}

/// Timing policy.
///
/// Decided: first note establishes the start reference; tolerance tightens as
/// tempo increases. The tempo-dependency model and all numeric tolerances are
/// UNRESOLVED.
final class TimingPolicySpec extends DimensionPolicySpec {
  final bool firstNoteIsStartReference;
  final bool tightensWithTempo;
  final TimingTempoDependencyKind? tempoDependencyKind;
  final ToleranceSpec? baseTolerance;

  const TimingPolicySpec({
    super.unavailableHandling = UnavailableHandling.noPenalty,
    required this.firstNoteIsStartReference,
    required this.tightensWithTempo,
    required this.tempoDependencyKind,
    required this.baseTolerance,
  });

  @override
  Map<String, Object?> toMap() => <String, Object?>{
    'unavailable_handling': unavailableHandling.serialName,
    'first_note_is_start_reference': firstNoteIsStartReference,
    'tightens_with_tempo': tightensWithTempo,
    'tempo_dependency_kind': tempoDependencyKind?.serialName,
    'base_tolerance': baseTolerance?.toMap(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimingPolicySpec &&
          other.unavailableHandling == unavailableHandling &&
          other.firstNoteIsStartReference == firstNoteIsStartReference &&
          other.tightensWithTempo == tightensWithTempo &&
          other.tempoDependencyKind == tempoDependencyKind &&
          other.baseTolerance == baseTolerance;

  @override
  int get hashCode => Object.hash(
    unavailableHandling,
    firstNoteIsStartReference,
    tightensWithTempo,
    tempoDependencyKind,
    baseTolerance,
  );
}

/// Order policy.
///
/// Decided: order is an independent dimension with lower impact than primary
/// pitch errors; the exact trim magnitude is unresolved.
final class OrderPolicySpec extends DimensionPolicySpec {
  final OrderImpactTier impactTier;

  const OrderPolicySpec({
    super.unavailableHandling = UnavailableHandling.noPenalty,
    required this.impactTier,
  });

  @override
  Map<String, Object?> toMap() => <String, Object?>{
    'unavailable_handling': unavailableHandling.serialName,
    'impact_tier': impactTier.serialName,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderPolicySpec &&
          other.unavailableHandling == unavailableHandling &&
          other.impactTier == impactTier;

  @override
  int get hashCode => Object.hash(unavailableHandling, impactTier);
}

/// IOI policy. All comparison semantics and tolerances are UNRESOLVED.
final class IoiPolicySpec extends DimensionPolicySpec {
  final ToleranceSpec? tolerance;

  const IoiPolicySpec({
    super.unavailableHandling = UnavailableHandling.noPenalty,
    required this.tolerance,
  });

  @override
  Map<String, Object?> toMap() => <String, Object?>{
    'unavailable_handling': unavailableHandling.serialName,
    'tolerance': tolerance?.toMap(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IoiPolicySpec &&
          other.unavailableHandling == unavailableHandling &&
          other.tolerance == tolerance;

  @override
  int get hashCode => Object.hash(unavailableHandling, tolerance);
}

/// Simultaneity policy.
///
/// Decided: tolerance tightens with learner level; missing members do not make
/// the played chord automatically unjudgeable; extra notes are excluded from
/// simultaneity and remain descriptive extra-note errors. Every level tolerance
/// value is UNRESOLVED.
final class SimultaneityPolicySpec extends DimensionPolicySpec {
  final Map<LearnerLevelKey, ToleranceSpec> levelTolerances;
  final bool missingMembersDoNotInvalidate;
  final bool excludesExtraNotes;

  SimultaneityPolicySpec({
    super.unavailableHandling = UnavailableHandling.noPenalty,
    required Map<LearnerLevelKey, ToleranceSpec> levelTolerances,
    required this.missingMembersDoNotInvalidate,
    required this.excludesExtraNotes,
  }) : levelTolerances = Map<LearnerLevelKey, ToleranceSpec>.unmodifiable(
         levelTolerances,
       );

  @override
  Map<String, Object?> toMap() => <String, Object?>{
    'unavailable_handling': unavailableHandling.serialName,
    'level_tolerances': <String, Object?>{
      for (final entry in levelTolerances.entries)
        entry.key.serialName: entry.value.toMap(),
    },
    'missing_members_do_not_invalidate': missingMembersDoNotInvalidate,
    'excludes_extra_notes': excludesExtraNotes,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SimultaneityPolicySpec &&
          other.unavailableHandling == unavailableHandling &&
          _levelToleranceMapEq(other.levelTolerances, levelTolerances) &&
          other.missingMembersDoNotInvalidate ==
              missingMembersDoNotInvalidate &&
          other.excludesExtraNotes == excludesExtraNotes;

  @override
  int get hashCode => Object.hash(
    unavailableHandling,
    _toleranceMapContentHash(levelTolerances),
    missingMembersDoNotInvalidate,
    excludesExtraNotes,
  );
}

/// Retrieval Latency policy.
///
/// Runtime anchor absence (`NO_RUNTIME_PERFORMANCE_ANCHOR`) is an input-layer
/// fact; the policy only declares handling. Anchor semantics and thresholds
/// are UNRESOLVED.
final class RetrievalLatencyPolicySpec extends DimensionPolicySpec {
  const RetrievalLatencyPolicySpec({
    super.unavailableHandling = UnavailableHandling.noPenalty,
  });

  @override
  Map<String, Object?> toMap() => <String, Object?>{
    'unavailable_handling': unavailableHandling.serialName,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RetrievalLatencyPolicySpec &&
          other.unavailableHandling == unavailableHandling;

  @override
  int get hashCode => unavailableHandling.hashCode;
}

/// The single mutable-free container of an Evaluation Policy profile: identity,
/// versioning, provenance, six dimension specs, star-quality policy, and the
/// NOT_APPLICABLE / resolution handling.
///
/// This is DATA, not behavior. No evaluation algorithm lives here. Numeric
/// thresholds remain unresolved; only values explicitly decided by the product
/// owner are materialized (each tagged with [ContractSourceProvenance]).
final class EvaluationPolicyProfile {
  static const String profileId = 'mvp_default_v1';
  static const String contractVersion = 'v1.1';
  static const String policyVersion = 'v1';

  final String profileIdValue;
  final String contractVersionValue;
  final String policyVersionValue;

  final ContractSourceProvenance provenance;

  final PitchPolicySpec pitch;
  final TimingPolicySpec timing;
  final OrderPolicySpec order;
  final SimultaneityPolicySpec simultaneity;
  final IoiPolicySpec ioi;
  final RetrievalLatencyPolicySpec retrievalLatency;

  final StarQualityPolicy stars;
  final NotApplicableHandling notApplicableHandling;

  /// Only [PolicyResolutionLayer.profile] (plus per-mode applicability) is
  /// resolved today; every deeper layer is explicitly unresolved.
  final PolicyResolutionLayer appliedResolutionDepth;
  final Set<PolicyResolutionLayer> unresolvedPrecedenceLayers;

  static final EvaluationPolicyProfile instance =
      EvaluationPolicyProfile.build();

  EvaluationPolicyProfile._({
    required this.profileIdValue,
    required this.contractVersionValue,
    required this.policyVersionValue,
    required this.provenance,
    required this.pitch,
    required this.timing,
    required this.order,
    required this.simultaneity,
    required this.ioi,
    required this.retrievalLatency,
    required this.stars,
    required this.notApplicableHandling,
    required this.appliedResolutionDepth,
    required Set<PolicyResolutionLayer> unresolvedPrecedenceLayers,
  }) : unresolvedPrecedenceLayers = Set<PolicyResolutionLayer>.unmodifiable(
         unresolvedPrecedenceLayers,
       );

  /// Deterministically builds the profile from locked constants. No numeric
  /// threshold is invented here.
  factory EvaluationPolicyProfile.build() {
    return EvaluationPolicyProfile._(
      profileIdValue: profileId,
      contractVersionValue: contractVersion,
      policyVersionValue: policyVersion,
      provenance: const ContractSourceProvenance(
        sourceKind: 'repository_code',
        sourcePath: 'lib/midi/domain/evaluation_input.dart',
        sourceIdentifier: 'MvpDefaultEvaluationProfile',
      ),
      pitch: const PitchPolicySpec(),
      timing: const TimingPolicySpec(
        firstNoteIsStartReference: true,
        tightensWithTempo: true,
        tempoDependencyKind: null,
        baseTolerance: null,
      ),
      order: const OrderPolicySpec(
        impactTier: OrderImpactTier.lowerThanPrimaryPitch,
      ),
      simultaneity: SimultaneityPolicySpec(
        levelTolerances: <LearnerLevelKey, ToleranceSpec>{
          // Vocabulary materialized; every level tolerance UNRESOLVED.
          LearnerLevelKey.beginner: ToleranceSpec(),
          LearnerLevelKey.intermediate: ToleranceSpec(),
          LearnerLevelKey.advanced: ToleranceSpec(),
        },
        missingMembersDoNotInvalidate: true,
        excludesExtraNotes: true,
      ),
      ioi: const IoiPolicySpec(tolerance: null),
      retrievalLatency: const RetrievalLatencyPolicySpec(),
      stars: StarQualityPolicy(
        primarySeverityModel: PrimarySeverityModel.worstErrorWithMinorTrims,
        allowZeroStars: true,
        minorTrimCount: null,
        missingNote: MissingNoteStarPolicy(
          countSensitive: true,
          oneMissingNoteCapStars: 4,
          perAdditionalMissingCapStars: null,
        ),
        extraNote: const ExtraNoteStarPolicy(
          imposesHardCap: false,
          hardCapStars: null,
        ),
        lessonStarCapacity: 10,
        accumulation: StarAccumulationKind.cappedProgress,
        bands: StarQualityPolicy.standardBands,
      ),
      notApplicableHandling: NotApplicableHandling.distinct,
      appliedResolutionDepth: PolicyResolutionLayer.profile,
      unresolvedPrecedenceLayers: <PolicyResolutionLayer>{
        PolicyResolutionLayer.learnerLevel,
        PolicyResolutionLayer.skill,
        PolicyResolutionLayer.exerciseMode,
        PolicyResolutionLayer.tempoRange,
        PolicyResolutionLayer.dimensionOverride,
      },
    );
  }

  List<DimensionPolicySpec> get dimensionSpecs =>
      List<DimensionPolicySpec>.unmodifiable([
        pitch,
        timing,
        order,
        simultaneity,
        ioi,
        retrievalLatency,
      ]);

  bool get containsResolvedDimensionThresholds =>
      timing.baseTolerance?.isResolved == true ||
      ioi.tolerance?.isResolved == true ||
      simultaneity.levelTolerances.values.any((spec) => spec.isResolved);

  Map<String, Object?> toMap() => <String, Object?>{
    'profile_id': profileIdValue,
    'contract_version': contractVersionValue,
    'policy_version': policyVersionValue,
    'provenance': provenance.toMap(),
    'dimensions': <String, Object?>{
      'pitch': pitch.toMap(),
      'timing': timing.toMap(),
      'order': order.toMap(),
      'simultaneity': simultaneity.toMap(),
      'ioi': ioi.toMap(),
      'retrieval_latency': retrievalLatency.toMap(),
    },
    'stars': stars.toMap(),
    'not_applicable_handling': notApplicableHandling.serialName,
    'applied_resolution_depth': appliedResolutionDepth.serialName,
    'unresolved_precedence_layers':
        unresolvedPrecedenceLayers
            .map((layer) => layer.serialName)
            .toList(growable: false)
          ..sort(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EvaluationPolicyProfile &&
          other.profileIdValue == profileIdValue &&
          other.contractVersionValue == contractVersionValue &&
          other.policyVersionValue == policyVersionValue &&
          other.provenance == provenance &&
          other.pitch == pitch &&
          other.timing == timing &&
          other.order == order &&
          other.simultaneity == simultaneity &&
          other.ioi == ioi &&
          other.retrievalLatency == retrievalLatency &&
          other.stars == stars &&
          other.notApplicableHandling == notApplicableHandling &&
          other.appliedResolutionDepth == appliedResolutionDepth;

  @override
  int get hashCode => Object.hash(
    profileIdValue,
    contractVersionValue,
    policyVersionValue,
    provenance,
    pitch,
    timing,
    order,
    simultaneity,
    ioi,
    retrievalLatency,
    stars,
    notApplicableHandling,
    appliedResolutionDepth,
  );
}

/// Identity + mode + optional key used by [EvaluationPolicyResolver].
final class PolicyResolutionContext {
  final String profileId;
  final String profileVersion;
  final TargetMode mode;
  final LearnerLevelKey? learnerLevel;
  final int? tempoBpm;

  const PolicyResolutionContext({
    required this.profileId,
    required this.profileVersion,
    required this.mode,
    this.learnerLevel,
    this.tempoBpm,
  });
}

/// One dimension of a resolved policy view.
///
/// [state] comes from the locked profile applicability for the mode
/// (enabled / notApplicable). Data availability (available / unavailable) is an
/// input-layer fact from H2.8, never a policy fact; the policy carries the
/// handling rule for each case via [spec].
final class ResolvedDimensionPolicy {
  final EvaluationDimension dimension;
  final EvaluationDimensionState state;
  final DimensionPolicySpec spec;

  const ResolvedDimensionPolicy({
    required this.dimension,
    required this.state,
    required this.spec,
  });

  Map<String, Object?> toMap() => <String, Object?>{
    'dimension': _dimensionSerial(dimension),
    'state': state.serialName,
    'spec': spec.toMap(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResolvedDimensionPolicy &&
          other.dimension == dimension &&
          other.state == state &&
          other.spec == spec;

  @override
  int get hashCode => Object.hash(dimension, state, spec);
}

/// The deterministic result of resolving a profile against a context.
final class ResolvedEvaluationPolicy {
  final EvaluationPolicyProfile profile;
  final TargetMode mode;
  final List<ResolvedDimensionPolicy> dimensions;
  final LearnerLevelKey? learnerLevel;
  final int? tempoBpm;

  ResolvedEvaluationPolicy({
    required this.profile,
    required this.mode,
    required List<ResolvedDimensionPolicy> dimensions,
    required this.learnerLevel,
    required this.tempoBpm,
  }) : dimensions = List<ResolvedDimensionPolicy>.unmodifiable(dimensions);

  bool get containsResolvedDimensionThresholds =>
      profile.containsResolvedDimensionThresholds;

  Map<String, Object?> toMap() => <String, Object?>{
    'profile_id': profile.profileIdValue,
    'contract_version': profile.contractVersionValue,
    'policy_version': profile.policyVersionValue,
    'mode': mode.name,
    'learner_level': learnerLevel?.serialName,
    'tempo_bpm': tempoBpm,
    'dimensions': dimensions.map((d) => d.toMap()).toList(growable: false),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResolvedEvaluationPolicy &&
          other.profile == profile &&
          other.mode == mode &&
          _resolvedDimensionListEq(other.dimensions, dimensions) &&
          other.learnerLevel == learnerLevel &&
          other.tempoBpm == tempoBpm;

  @override
  int get hashCode => Object.hash(
    profile,
    mode,
    Object.hashAll(dimensions),
    learnerLevel,
    tempoBpm,
  );
}

/// Deterministic resolution of an [EvaluationPolicyProfile] for a
/// [PolicyResolutionContext].
///
/// Rules:
/// * Strict identity match on profile id + contract version; anything else is
///   a deterministic [FormatException].
/// * Per-dimension state is derived from the locked profile applicability
///   ([MvpDefaultEvaluationProfile]) for the context mode.
/// * Only the [PolicyResolutionLayer.profile] layer is applied; deeper
///   precedence layers are explicitly unresolved on the profile.
final class EvaluationPolicyResolver {
  const EvaluationPolicyResolver();

  ResolvedEvaluationPolicy resolve({
    required EvaluationPolicyProfile profile,
    required PolicyResolutionContext context,
  }) {
    if (profile.profileIdValue != context.profileId ||
        profile.contractVersionValue != context.profileVersion) {
      throw const FormatException(
        'EvaluationPolicyResolver: unknown policy identity (no matching '
        'profile/version).',
      );
    }
    final specs = <EvaluationDimension, DimensionPolicySpec>{
      EvaluationDimension.pitch: profile.pitch,
      EvaluationDimension.timing: profile.timing,
      EvaluationDimension.order: profile.order,
      EvaluationDimension.simultaneity: profile.simultaneity,
      EvaluationDimension.ioi: profile.ioi,
      EvaluationDimension.retrievalLatency: profile.retrievalLatency,
    };
    final dimensions = <ResolvedDimensionPolicy>[
      for (final dimension in EvaluationDimension.values)
        ResolvedDimensionPolicy(
          dimension: dimension,
          state:
              MvpDefaultEvaluationProfile.instance.isDimensionEnabled(
                context.mode,
                dimension,
              )
              ? EvaluationDimensionState.enabled
              : EvaluationDimensionState.notApplicable,
          spec: specs[dimension]!,
        ),
    ];
    return ResolvedEvaluationPolicy(
      profile: profile,
      mode: context.mode,
      dimensions: dimensions,
      learnerLevel: context.learnerLevel,
      tempoBpm: context.tempoBpm,
    );
  }
}

// ---- Deterministic helpers ----

String _dimensionSerial(EvaluationDimension dimension) => switch (dimension) {
  EvaluationDimension.pitch => 'pitch',
  EvaluationDimension.timing => 'timing',
  EvaluationDimension.order => 'order',
  EvaluationDimension.simultaneity => 'simultaneity',
  EvaluationDimension.ioi => 'ioi',
  EvaluationDimension.retrievalLatency => 'retrieval_latency',
};

bool _starBandListEq(List<StarBand> a, List<StarBand> b) {
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

bool _levelToleranceMapEq(
  Map<LearnerLevelKey, ToleranceSpec> a,
  Map<LearnerLevelKey, ToleranceSpec> b,
) {
  if (a.length != b.length) {
    return false;
  }
  for (final key in LearnerLevelKey.values) {
    if (a[key] != b[key]) {
      return false;
    }
  }
  return true;
}

/// Content-based, order-stable hash of a level-tolerance map. Dart Map
/// instances compare by identity, which would make equal content produce
/// different hashes; this derives a stable hash from the fixed
/// [LearnerLevelKey] enumeration instead.
int _toleranceMapContentHash(Map<LearnerLevelKey, ToleranceSpec> map) {
  var hash = 0;
  for (final key in LearnerLevelKey.values) {
    hash = Object.hash(hash, key, map[key]);
  }
  return hash;
}

bool _resolvedDimensionListEq(
  List<ResolvedDimensionPolicy> a,
  List<ResolvedDimensionPolicy> b,
) {
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
