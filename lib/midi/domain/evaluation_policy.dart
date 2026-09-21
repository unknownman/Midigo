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

/// Severity vocabulary shared by every dimension's grading bands.
///
/// The labels are deliberately DESCRIPTIVE. Equal labels across dimensions do
/// not by themselves imply equal star impact; the star impact is materialized
/// separately by the star aggregation policy.
enum SeverityTier {
  none,
  negligible,
  minor,
  moderate,
  major;

  String get serialName => switch (this) {
    SeverityTier.none => 'NONE',
    SeverityTier.negligible => 'NEGLIGIBLE',
    SeverityTier.minor => 'MINOR',
    SeverityTier.moderate => 'MODERATE',
    SeverityTier.major => 'MAJOR',
  };

  /// Ordinal severity rank; a larger rank is a worse error.
  int get rank => index;

  bool atLeast(SeverityTier other) => index >= other.index;
}

/// Outcome-state vocabulary of an evaluated musical target.
///
/// A real but extremely poor performance is [evaluated] with 0 stars; that is
/// deliberately distinct from [notEnoughPerformance].
enum EvaluationResultState {
  notEnoughPerformance,
  evaluated;

  String get serialName => switch (this) {
    EvaluationResultState.notEnoughPerformance => 'NOT_ENOUGH_PERFORMANCE',
    EvaluationResultState.evaluated => 'EVALUATED',
  };
}

/// Closed Error Vector reason-code vocabulary.
enum ErrorVectorReasonCode {
  pitchWrong,
  pitchMissing,
  pitchExtra,
  timingEarly,
  timingLate,
  orderAdjacentInversion,
  orderPartialInversion,
  orderFullReversal,
  ioiInconsistent,
  simultaneitySpread,
  retrievalLatencyUnavailable;

  String get serialName => switch (this) {
    ErrorVectorReasonCode.pitchWrong => 'PITCH_WRONG',
    ErrorVectorReasonCode.pitchMissing => 'PITCH_MISSING',
    ErrorVectorReasonCode.pitchExtra => 'PITCH_EXTRA',
    ErrorVectorReasonCode.timingEarly => 'TIMING_EARLY',
    ErrorVectorReasonCode.timingLate => 'TIMING_LATE',
    ErrorVectorReasonCode.orderAdjacentInversion => 'ORDER_ADJACENT_INVERSION',
    ErrorVectorReasonCode.orderPartialInversion => 'ORDER_PARTIAL_INVERSION',
    ErrorVectorReasonCode.orderFullReversal => 'ORDER_FULL_REVERSAL',
    ErrorVectorReasonCode.ioiInconsistent => 'IOI_INCONSISTENT',
    ErrorVectorReasonCode.simultaneitySpread => 'SIMULTANEITY_SPREAD',
    ErrorVectorReasonCode.retrievalLatencyUnavailable =>
      'RETRIEVAL_LATENCY_UNAVAILABLE',
  };
}

/// Rounding rule for a proportional tolerance value.
enum ToleranceRoundingMode {
  nearest;

  String get serialName => 'NEAREST';
}

/// One severity band over a raw numeric measure (`<= upper` / `< upper`).
///
/// The final band is open-ended ([isOpen]); every other band must carry an
/// explicit boundary so inclusive-vs-exclusive is never ambiguous.
final class SeverityBand {
  final SeverityTier severity;
  final num? upperBound;
  final PolicyBoundary? upperBoundary;

  const SeverityBand({
    required this.severity,
    this.upperBound,
    this.upperBoundary,
  });

  bool get isOpen => upperBound == null;

  bool contains(num value) {
    final bound = upperBound;
    if (bound == null) {
      return true;
    }
    return upperBoundary == PolicyBoundary.inclusive
        ? value <= bound
        : value < bound;
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'severity': severity.serialName,
    'upper_bound': upperBound,
    'upper_boundary': upperBoundary?.serialName,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SeverityBand &&
          other.severity == severity &&
          other.upperBound == upperBound &&
          other.upperBoundary == upperBoundary;

  @override
  int get hashCode => Object.hash(severity, upperBound, upperBoundary);
}

/// Ordered [SeverityBand] table for one numeric measure, worst band last.
///
/// Classification is pure policy-data lookup: the table owns every numeric
/// boundary, so no grading literal ever needs to appear in a consuming
/// algorithm.
final class SeverityBandTable {
  final List<SeverityBand> bands;

  SeverityBandTable({required List<SeverityBand> bands})
    : bands = List<SeverityBand>.unmodifiable(bands);

  /// The severity for [value], evaluated from least to most severe.
  SeverityTier classify(num value) {
    for (final band in bands) {
      if (band.contains(value)) {
        return band.severity;
      }
    }
    return bands.last.severity;
  }

  /// Rejects malformed tables deterministically.
  void validate() {
    if (bands.isEmpty) {
      throw const FormatException(
        'SeverityBandTable: at least one band is required.',
      );
    }
    final openCount = bands.where((band) => band.isOpen).length;
    if (openCount != 1 || !bands.last.isOpen) {
      throw const FormatException(
        'SeverityBandTable: exactly one open-ended band is required, and it '
        'must be the most severe band.',
      );
    }
    for (var i = 0; i < bands.length; i++) {
      final band = bands[i];
      if (band.upperBound != null && band.upperBoundary == null) {
        throw const FormatException(
          'SeverityBandTable: a bounded band requires an explicit boundary.',
        );
      }
      if (band.upperBound == null && band.upperBoundary != null) {
        throw const FormatException(
          'SeverityBandTable: an open band must not carry a boundary.',
        );
      }
      if (i == 0) {
        continue;
      }
      final previous = bands[i - 1];
      if (band.severity.rank <= previous.severity.rank) {
        throw const FormatException(
          'SeverityBandTable: severities must strictly increase.',
        );
      }
      final previousUpper = previous.upperBound;
      final upper = band.upperBound;
      if (previousUpper == null) {
        throw const FormatException(
          'SeverityBandTable: no band may follow the open-ended band.',
        );
      }
      if (upper != null && upper <= previousUpper) {
        throw const FormatException(
          'SeverityBandTable: band bounds must strictly increase '
          '(no overlap or inversion).',
        );
      }
    }
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'bands': bands.map((band) => band.toMap()).toList(growable: false),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SeverityBandTable && _severityBandListEq(other.bands, bands);

  @override
  int get hashCode => Object.hashAll(bands);
}

/// One missing-note-count bucket of the star ceiling table.
final class MissingNoteCap {
  final int minimumMissingCount;
  final int? maxStars;

  const MissingNoteCap({
    required this.minimumMissingCount,
    required this.maxStars,
  });

  Map<String, Object?> toMap() => <String, Object?>{
    'minimum_missing_count': minimumMissingCount,
    'max_stars': maxStars,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MissingNoteCap &&
          other.minimumMissingCount == minimumMissingCount &&
          other.maxStars == maxStars;

  @override
  int get hashCode => Object.hash(minimumMissingCount, maxStars);
}

/// Count-sensitive missing-note star ceiling table; the final bucket is open.
final class MissingNoteCapTable {
  final List<MissingNoteCap> caps;

  MissingNoteCapTable({required List<MissingNoteCap> caps})
    : caps = List<MissingNoteCap>.unmodifiable(caps);

  /// The star ceiling for [missingCount]; null means no ceiling.
  int? capForCount(int missingCount) {
    var result = caps.first.maxStars;
    for (final cap in caps) {
      if (missingCount >= cap.minimumMissingCount) {
        result = cap.maxStars;
      } else {
        break;
      }
    }
    return result;
  }

  void validate() {
    if (caps.isEmpty || caps.first.minimumMissingCount != 0) {
      throw const FormatException(
        'MissingNoteCapTable: the first bucket must start at 0 missing notes.',
      );
    }
    for (var i = 0; i < caps.length; i++) {
      final cap = caps[i];
      if (cap.maxStars != null && (cap.maxStars! < 0 || cap.maxStars! > 5)) {
        throw const FormatException(
          'MissingNoteCapTable: a star ceiling must be within 0..5.',
        );
      }
      if (i == 0) {
        continue;
      }
      if (cap.minimumMissingCount <= caps[i - 1].minimumMissingCount) {
        throw const FormatException(
          'MissingNoteCapTable: missing-count buckets must strictly increase.',
        );
      }
      final previous = caps[i - 1].maxStars ?? 6;
      final current = cap.maxStars ?? 6;
      if (current >= previous) {
        throw const FormatException(
          'MissingNoteCapTable: star ceilings must strictly tighten as '
          'missing notes increase.',
        );
      }
    }
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'caps': caps.map((cap) => cap.toMap()).toList(growable: false),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MissingNoteCapTable && _missingNoteCapListEq(other.caps, caps);

  @override
  int get hashCode => Object.hashAll(caps);
}

/// Tempo-aware proportional tolerance: `round(interval * percent / 100)`.
final class ProportionalTolerance {
  final int percent;
  final ToleranceRoundingMode rounding;

  const ProportionalTolerance({required this.percent, required this.rounding});

  num toleranceMs(num expectedIntervalMs) {
    final raw = expectedIntervalMs * percent / 100;
    return switch (rounding) {
      ToleranceRoundingMode.nearest => raw.round(),
    };
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'percent': percent,
    'rounding': rounding.serialName,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProportionalTolerance &&
          other.percent == percent &&
          other.rounding == rounding;

  @override
  int get hashCode => Object.hash(percent, rounding);
}

/// Evaluability: when a target is assessable at all.
final class EvaluabilityPolicy {
  final bool requiresStructuralAssociation;
  final bool basedOnPitchCorrectness;
  final bool zeroAssociationsMeansNotEnoughPerformance;
  final String associationAuthority;

  const EvaluabilityPolicy({
    required this.requiresStructuralAssociation,
    required this.basedOnPitchCorrectness,
    required this.zeroAssociationsMeansNotEnoughPerformance,
    required this.associationAuthority,
  });

  Map<String, Object?> toMap() => <String, Object?>{
    'requires_structural_association': requiresStructuralAssociation,
    'based_on_pitch_correctness': basedOnPitchCorrectness,
    'zero_associations_means_not_enough_performance':
        zeroAssociationsMeansNotEnoughPerformance,
    'association_authority': associationAuthority,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EvaluabilityPolicy &&
          other.requiresStructuralAssociation ==
              requiresStructuralAssociation &&
          other.basedOnPitchCorrectness == basedOnPitchCorrectness &&
          other.zeroAssociationsMeansNotEnoughPerformance ==
              zeroAssociationsMeansNotEnoughPerformance &&
          other.associationAuthority == associationAuthority;

  @override
  int get hashCode => Object.hash(
    requiresStructuralAssociation,
    basedOnPitchCorrectness,
    zeroAssociationsMeansNotEnoughPerformance,
    associationAuthority,
  );
}

/// Result-state semantics: NEP vs EVALUATED, and what stays outside.
final class ResultStatePolicy {
  final EvaluationResultState insufficientDataState;
  final int evaluatedMinStars;
  final int evaluatedMaxStars;
  final bool producesAggregatePassFail;
  final bool notEnoughPerformanceEqualsZeroStars;
  final List<String> lifecycleStatesOutsideResult;

  ResultStatePolicy({
    required this.insufficientDataState,
    required this.evaluatedMinStars,
    required this.evaluatedMaxStars,
    required this.producesAggregatePassFail,
    required this.notEnoughPerformanceEqualsZeroStars,
    required List<String> lifecycleStatesOutsideResult,
  }) : lifecycleStatesOutsideResult = List<String>.unmodifiable(
         lifecycleStatesOutsideResult,
       );

  void validate() {
    if (evaluatedMinStars < 0 ||
        evaluatedMaxStars > 5 ||
        evaluatedMinStars > evaluatedMaxStars) {
      throw const FormatException(
        'ResultStatePolicy: the evaluated star range must be a valid 0..5 '
        'sub-range.',
      );
    }
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'insufficient_data_state': insufficientDataState.serialName,
    'evaluated_min_stars': evaluatedMinStars,
    'evaluated_max_stars': evaluatedMaxStars,
    'produces_aggregate_pass_fail': producesAggregatePassFail,
    'not_enough_performance_equals_zero_stars':
        notEnoughPerformanceEqualsZeroStars,
    'lifecycle_states_outside_result': lifecycleStatesOutsideResult,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResultStatePolicy &&
          other.insufficientDataState == insufficientDataState &&
          other.evaluatedMinStars == evaluatedMinStars &&
          other.evaluatedMaxStars == evaluatedMaxStars &&
          other.producesAggregatePassFail == producesAggregatePassFail &&
          other.notEnoughPerformanceEqualsZeroStars ==
              notEnoughPerformanceEqualsZeroStars &&
          _stringListEq(
            other.lifecycleStatesOutsideResult,
            lifecycleStatesOutsideResult,
          );

  @override
  int get hashCode => Object.hash(
    insufficientDataState,
    evaluatedMinStars,
    evaluatedMaxStars,
    producesAggregatePassFail,
    notEnoughPerformanceEqualsZeroStars,
    Object.hashAll(lifecycleStatesOutsideResult),
  );
}

/// The Error Vector vocabulary policy: descriptive/diagnostic only.
final class ErrorVectorPolicy {
  final List<ErrorVectorReasonCode> reasonCodes;
  final bool descriptiveOnly;
  final bool carriesStarsOrWeights;
  final bool mutatesMasteryEvidence;

  ErrorVectorPolicy({
    required List<ErrorVectorReasonCode> reasonCodes,
    required this.descriptiveOnly,
    required this.carriesStarsOrWeights,
    required this.mutatesMasteryEvidence,
  }) : reasonCodes = List<ErrorVectorReasonCode>.unmodifiable(reasonCodes);

  void validate() {
    final declared = reasonCodes.toSet();
    if (declared.length != reasonCodes.length) {
      throw const FormatException(
        'ErrorVectorPolicy: duplicate reason-code definitions.',
      );
    }
    for (final code in ErrorVectorReasonCode.values) {
      if (!declared.contains(code)) {
        throw FormatException(
          'ErrorVectorPolicy: missing reason-code definition '
          '${code.serialName}.',
        );
      }
    }
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'reason_codes': reasonCodes
        .map((code) => code.serialName)
        .toList(growable: false),
    'descriptive_only': descriptiveOnly,
    'carries_stars_or_weights': carriesStarsOrWeights,
    'mutates_mastery_evidence': mutatesMasteryEvidence,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ErrorVectorPolicy &&
          _reasonCodeListEq(other.reasonCodes, reasonCodes) &&
          other.descriptiveOnly == descriptiveOnly &&
          other.carriesStarsOrWeights == carriesStarsOrWeights &&
          other.mutatesMasteryEvidence == mutatesMasteryEvidence;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(reasonCodes),
    descriptiveOnly,
    carriesStarsOrWeights,
    mutatesMasteryEvidence,
  );
}

/// One immutable, descriptive Error Vector entry.
///
/// This carries diagnostics only: no stars, no weights, no mutation vocabulary.
final class ErrorVectorEntry {
  final EvaluationDimension dimension;
  final SeverityTier severity;
  final ErrorVectorReasonCode reasonCode;
  final Object? expectedValue;
  final Object? observedValue;
  final num? signedDelta;
  final int? count;
  final Map<String, Object?>? context;

  ErrorVectorEntry({
    required this.dimension,
    required this.severity,
    required this.reasonCode,
    this.expectedValue,
    this.observedValue,
    this.signedDelta,
    this.count,
    Map<String, Object?>? context,
  }) : context = context == null
           ? null
           : Map<String, Object?>.unmodifiable(context);

  Map<String, Object?> toMap() => <String, Object?>{
    'dimension': _dimensionSerial(dimension),
    'severity': severity.serialName,
    'reason_code': reasonCode.serialName,
    'expected_value': expectedValue,
    'observed_value': observedValue,
    'signed_delta': signedDelta,
    'count': count,
    'context': context,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ErrorVectorEntry &&
          other.dimension == dimension &&
          other.severity == severity &&
          other.reasonCode == reasonCode &&
          other.expectedValue == expectedValue &&
          other.observedValue == observedValue &&
          other.signedDelta == signedDelta &&
          other.count == count &&
          _nullableMapEq(other.context, context);

  @override
  int get hashCode => Object.hash(
    dimension,
    severity,
    reasonCode,
    expectedValue,
    observedValue,
    signedDelta,
    count,
    context == null ? null : _nullableMapHash(context!),
  );
}

/// Materialized per-mode applicability: exactly one state per dimension.
final class EvaluationPolicyApplicability {
  final Map<TargetMode, Set<EvaluationDimension>> enabled;
  final Map<TargetMode, Set<EvaluationDimension>> notApplicable;

  EvaluationPolicyApplicability({
    required Map<TargetMode, Set<EvaluationDimension>> enabled,
    required Map<TargetMode, Set<EvaluationDimension>> notApplicable,
  }) : enabled = _freezeDimensionSets(enabled),
       notApplicable = _freezeDimensionSets(notApplicable);

  void validate() {
    for (final mode in TargetMode.values) {
      final modeEnabled = enabled[mode];
      final modeNotApplicable = notApplicable[mode];
      if (modeEnabled == null || modeNotApplicable == null) {
        throw FormatException(
          'EvaluationPolicyApplicability: missing applicability for '
          '${mode.name}.',
        );
      }
      if (modeEnabled.intersection(modeNotApplicable).isNotEmpty) {
        throw FormatException(
          'EvaluationPolicyApplicability: ambiguous applicability for '
          '${mode.name}.',
        );
      }
      if (modeEnabled.union(modeNotApplicable).length !=
          EvaluationDimension.values.length) {
        throw FormatException(
          'EvaluationPolicyApplicability: incomplete applicability for '
          '${mode.name}.',
        );
      }
    }
  }

  EvaluationDimensionState stateFor(
    TargetMode mode,
    EvaluationDimension dimension,
  ) => enabled[mode]!.contains(dimension)
      ? EvaluationDimensionState.enabled
      : EvaluationDimensionState.notApplicable;

  Map<String, Object?> toMap() => <String, Object?>{
    for (final mode in TargetMode.values)
      mode.name: <String, Object?>{
        'enabled': _dimensionSerials(enabled[mode] ?? const {}),
        'not_applicable': _dimensionSerials(notApplicable[mode] ?? const {}),
      },
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EvaluationPolicyApplicability &&
          _applicabilityMapEq(other.enabled, enabled) &&
          _applicabilityMapEq(other.notApplicable, notApplicable);

  @override
  int get hashCode => Object.hash(
    _applicabilityMapHash(enabled),
    _applicabilityMapHash(notApplicable),
  );
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
/// Count-sensitive: one missing note caps at 4 stars and each additional
/// missing-note bucket tightens the ceiling (3, then 2, then 1). The ceiling is
/// applied AFTER base + trims and never invalidates simultaneity of performed
/// notes.
final class MissingNoteStarPolicy {
  final bool countSensitive;
  final int? oneMissingNoteCapStars;

  /// Legacy single-step slot; superseded by [capTable], retained for
  /// compatibility.
  final int? perAdditionalMissingCapStars;

  final MissingNoteCapTable capTable;
  final bool appliedAfterBaseAndTrims;
  final bool isCeilingNotSeverity;
  final bool invalidatesSimultaneity;

  MissingNoteStarPolicy({
    required this.countSensitive,
    required this.oneMissingNoteCapStars,
    required this.perAdditionalMissingCapStars,
    required this.capTable,
    required this.appliedAfterBaseAndTrims,
    required this.isCeilingNotSeverity,
    required this.invalidatesSimultaneity,
  });

  Map<String, Object?> toMap() => <String, Object?>{
    'count_sensitive': countSensitive,
    'one_missing_note_cap_stars': oneMissingNoteCapStars,
    'per_additional_missing_cap_stars': perAdditionalMissingCapStars,
    'cap_table': capTable.toMap(),
    'applied_after_base_and_trims': appliedAfterBaseAndTrims,
    'is_ceiling_not_severity': isCeilingNotSeverity,
    'invalidates_simultaneity': invalidatesSimultaneity,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MissingNoteStarPolicy &&
          other.countSensitive == countSensitive &&
          other.oneMissingNoteCapStars == oneMissingNoteCapStars &&
          other.perAdditionalMissingCapStars == perAdditionalMissingCapStars &&
          other.capTable == capTable &&
          other.appliedAfterBaseAndTrims == appliedAfterBaseAndTrims &&
          other.isCeilingNotSeverity == isCeilingNotSeverity &&
          other.invalidatesSimultaneity == invalidatesSimultaneity;

  @override
  int get hashCode => Object.hash(
    countSensitive,
    oneMissingNoteCapStars,
    perAdditionalMissingCapStars,
    capTable,
    appliedAfterBaseAndTrims,
    isCeilingNotSeverity,
    invalidatesSimultaneity,
  );
}

/// Extra-note star behavior.
///
/// Decided: extra notes do not impose a hard star cap and are excluded from
/// required-note simultaneity.
final class ExtraNoteStarPolicy {
  final bool imposesHardCap;
  final int? hardCapStars;
  final bool excludedFromSimultaneity;
  final SeverityBandTable severityByCount;

  ExtraNoteStarPolicy({
    required this.imposesHardCap,
    required this.hardCapStars,
    required this.excludedFromSimultaneity,
    required this.severityByCount,
  });

  Map<String, Object?> toMap() => <String, Object?>{
    'imposes_hard_cap': imposesHardCap,
    'hard_cap_stars': hardCapStars,
    'excluded_from_simultaneity': excludedFromSimultaneity,
    'severity_by_count': severityByCount.toMap(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExtraNoteStarPolicy &&
          other.imposesHardCap == imposesHardCap &&
          other.hardCapStars == hardCapStars &&
          other.excludedFromSimultaneity == excludedFromSimultaneity &&
          other.severityByCount == severityByCount;

  @override
  int get hashCode => Object.hash(
    imposesHardCap,
    hardCapStars,
    excludedFromSimultaneity,
    severityByCount,
  );
}

/// The 5..0 star quality policy, fully materialized.
///
/// The primary tier is selected from the worst severity; additional
/// non-negligible errors trim whole stars, capped at [minorTrimCount]. The
/// missing-note ceiling is applied last. No percentage-based correct-content
/// formula is used.
final class StarQualityPolicy {
  final PrimarySeverityModel primarySeverityModel;
  final bool allowZeroStars;
  final int? minorTrimCount;
  final MissingNoteStarPolicy missingNote;
  final ExtraNoteStarPolicy extraNote;
  final int? lessonStarCapacity;
  final StarAccumulationKind accumulation;

  final Map<SeverityTier, int> baseStars;
  final SeverityTier minimumTrimSeverity;
  final bool worstErrorEstablishesBase;
  final bool worstErrorTrims;
  final bool fractionalStars;
  final bool lessonStarsMonotonic;
  final bool lessonStarsDecay;
  final bool lessonStarsSeparateFromMastery;
  final int? tempoProgressionThresholdStars;

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
    required Map<SeverityTier, int> baseStars,
    required this.minimumTrimSeverity,
    required this.worstErrorEstablishesBase,
    required this.worstErrorTrims,
    required this.fractionalStars,
    required this.lessonStarsMonotonic,
    required this.lessonStarsDecay,
    required this.lessonStarsSeparateFromMastery,
    required this.tempoProgressionThresholdStars,
    required List<StarBand> bands,
  }) : baseStars = Map<SeverityTier, int>.unmodifiable(baseStars),
       bands = List<StarBand>.unmodifiable(bands) {
    if (bands.length != standardBands.length) {
      throw const FormatException(
        'StarQualityPolicy: the star model must expose bands 5..0.',
      );
    }
  }

  bool get anyBandBoundaryResolved => bands.any((band) => band.isResolved);

  void validate() {
    for (final tier in SeverityTier.values) {
      if (!baseStars.containsKey(tier)) {
        throw FormatException(
          'StarQualityPolicy: missing base star mapping for '
          '${tier.serialName}.',
        );
      }
      final stars = baseStars[tier]!;
      if (stars < 0 || stars > 5) {
        throw FormatException(
          'StarQualityPolicy: base stars for ${tier.serialName} must be '
          'within 0..5.',
        );
      }
    }
    final trimCount = minorTrimCount;
    if (trimCount == null || trimCount < 0 || trimCount > 5) {
      throw const FormatException(
        'StarQualityPolicy: the trim count must be materialized within 0..5.',
      );
    }
    if (fractionalStars) {
      throw const FormatException(
        'StarQualityPolicy: fractional stars are not permitted by the MVP '
        'policy.',
      );
    }
    missingNote.capTable.validate();
    extraNote.severityByCount.validate();
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'primary_severity_model': primarySeverityModel.serialName,
    'allow_zero_stars': allowZeroStars,
    'minor_trim_count': minorTrimCount,
    'missing_note': missingNote.toMap(),
    'extra_note': extraNote.toMap(),
    'lesson_star_capacity': lessonStarCapacity,
    'accumulation': accumulation.serialName,
    'base_stars': <String, Object?>{
      for (final entry in baseStars.entries) entry.key.serialName: entry.value,
    },
    'minimum_trim_severity': minimumTrimSeverity.serialName,
    'worst_error_establishes_base': worstErrorEstablishesBase,
    'worst_error_trims': worstErrorTrims,
    'fractional_stars': fractionalStars,
    'lesson_stars_monotonic': lessonStarsMonotonic,
    'lesson_stars_decay': lessonStarsDecay,
    'lesson_stars_separate_from_mastery': lessonStarsSeparateFromMastery,
    'tempo_progression_threshold_stars': tempoProgressionThresholdStars,
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
          _severityStarMapEq(other.baseStars, baseStars) &&
          other.minimumTrimSeverity == minimumTrimSeverity &&
          other.worstErrorEstablishesBase == worstErrorEstablishesBase &&
          other.worstErrorTrims == worstErrorTrims &&
          other.fractionalStars == fractionalStars &&
          other.lessonStarsMonotonic == lessonStarsMonotonic &&
          other.lessonStarsDecay == lessonStarsDecay &&
          other.lessonStarsSeparateFromMastery ==
              lessonStarsSeparateFromMastery &&
          other.tempoProgressionThresholdStars ==
              tempoProgressionThresholdStars &&
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
    _severityStarMapHash(baseStars),
    minimumTrimSeverity,
    worstErrorEstablishesBase,
    worstErrorTrims,
    fractionalStars,
    lessonStarsMonotonic,
    lessonStarsDecay,
    lessonStarsSeparateFromMastery,
    tempoProgressionThresholdStars,
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

/// Pitch policy: exact MIDI identity with strict one-to-one matching.
///
/// Extra notes are not pitch errors; missing notes are handled by the
/// missing-note star ceiling, and mismatched required notes are counted as
/// wrong notes.
final class PitchPolicySpec extends DimensionPolicySpec {
  final bool exactMidiIdentity;
  final bool oneToOneMatching;
  final bool toleranceApplied;
  final bool spellingComparison;
  final bool rematchingAllowed;
  final String alignmentAuthority;
  final bool extraNotesArePitchErrors;
  final SeverityBandTable wrongNoteSeverity;

  PitchPolicySpec({
    super.unavailableHandling = UnavailableHandling.noPenalty,
    required this.exactMidiIdentity,
    required this.oneToOneMatching,
    required this.toleranceApplied,
    required this.spellingComparison,
    required this.rematchingAllowed,
    required this.alignmentAuthority,
    required this.extraNotesArePitchErrors,
    required this.wrongNoteSeverity,
  });

  @override
  Map<String, Object?> toMap() => <String, Object?>{
    'unavailable_handling': unavailableHandling.serialName,
    'exact_midi_identity': exactMidiIdentity,
    'one_to_one_matching': oneToOneMatching,
    'tolerance_applied': toleranceApplied,
    'spelling_comparison': spellingComparison,
    'rematching_allowed': rematchingAllowed,
    'alignment_authority': alignmentAuthority,
    'extra_notes_are_pitch_errors': extraNotesArePitchErrors,
    'wrong_note_severity': wrongNoteSeverity.toMap(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PitchPolicySpec &&
          other.unavailableHandling == unavailableHandling &&
          other.exactMidiIdentity == exactMidiIdentity &&
          other.oneToOneMatching == oneToOneMatching &&
          other.toleranceApplied == toleranceApplied &&
          other.spellingComparison == spellingComparison &&
          other.rematchingAllowed == rematchingAllowed &&
          other.alignmentAuthority == alignmentAuthority &&
          other.extraNotesArePitchErrors == extraNotesArePitchErrors &&
          other.wrongNoteSeverity == wrongNoteSeverity;

  @override
  int get hashCode => Object.hash(
    unavailableHandling,
    exactMidiIdentity,
    oneToOneMatching,
    toleranceApplied,
    spellingComparison,
    rematchingAllowed,
    alignmentAuthority,
    extraNotesArePitchErrors,
    wrongNoteSeverity,
  );
}

/// Timing policy.
///
/// Two independent concepts are materialized: a proportional tolerance
/// (`round(expectedInterval * percent / 100)`) and a proportional severity
/// band table. The first note is the start reference and first-note lateness is
/// not penalized.
final class TimingPolicySpec extends DimensionPolicySpec {
  final bool firstNoteIsStartReference;
  final bool firstNoteLatenessPenalized;
  final bool tightensWithTempo;
  final TimingTempoDependencyKind? tempoDependencyKind;
  final ToleranceSpec? baseTolerance;
  final ProportionalTolerance toleranceRatio;
  final SeverityBandTable severityBands;
  final num severityReferenceIntervalMs;

  const TimingPolicySpec({
    super.unavailableHandling = UnavailableHandling.noPenalty,
    required this.firstNoteIsStartReference,
    required this.firstNoteLatenessPenalized,
    required this.tightensWithTempo,
    required this.tempoDependencyKind,
    required this.baseTolerance,
    required this.toleranceRatio,
    required this.severityBands,
    required this.severityReferenceIntervalMs,
  });

  /// Severity of a raw timing deviation, expressed relative to the expected
  /// interval. Pure policy-data lookup; owns no literal.
  SeverityTier classifySeverity({
    required num deviationMs,
    required num expectedIntervalMs,
  }) {
    if (expectedIntervalMs == 0) {
      return severityBands.classify(deviationMs);
    }
    return severityBands.classify(deviationMs * 100 / expectedIntervalMs);
  }

  @override
  Map<String, Object?> toMap() => <String, Object?>{
    'unavailable_handling': unavailableHandling.serialName,
    'first_note_is_start_reference': firstNoteIsStartReference,
    'first_note_lateness_penalized': firstNoteLatenessPenalized,
    'tightens_with_tempo': tightensWithTempo,
    'tempo_dependency_kind': tempoDependencyKind?.serialName,
    'base_tolerance': baseTolerance?.toMap(),
    'tolerance_ratio': toleranceRatio.toMap(),
    'severity_bands': severityBands.toMap(),
    'severity_reference_interval_ms': severityReferenceIntervalMs,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimingPolicySpec &&
          other.unavailableHandling == unavailableHandling &&
          other.firstNoteIsStartReference == firstNoteIsStartReference &&
          other.firstNoteLatenessPenalized == firstNoteLatenessPenalized &&
          other.tightensWithTempo == tightensWithTempo &&
          other.tempoDependencyKind == tempoDependencyKind &&
          other.baseTolerance == baseTolerance &&
          other.toleranceRatio == toleranceRatio &&
          other.severityBands == severityBands &&
          other.severityReferenceIntervalMs == severityReferenceIntervalMs;

  @override
  int get hashCode => Object.hash(
    unavailableHandling,
    firstNoteIsStartReference,
    firstNoteLatenessPenalized,
    tightensWithTempo,
    tempoDependencyKind,
    baseTolerance,
    toleranceRatio,
    severityBands,
    severityReferenceIntervalMs,
  );
}

/// Order policy.
///
/// Order is an independent dimension with lower impact than primary pitch
/// errors. Inversion classes map to descriptive severities; the star impact is
/// applied by the shared star aggregation policy.
final class OrderPolicySpec extends DimensionPolicySpec {
  final OrderImpactTier impactTier;
  final SeverityTier adjacentInversionSeverity;
  final SeverityTier partialInversionSeverity;
  final SeverityTier fullReversalSeverity;
  final bool independentOfPitch;
  final bool rematchingAllowed;

  const OrderPolicySpec({
    super.unavailableHandling = UnavailableHandling.noPenalty,
    required this.impactTier,
    required this.adjacentInversionSeverity,
    required this.partialInversionSeverity,
    required this.fullReversalSeverity,
    required this.independentOfPitch,
    required this.rematchingAllowed,
  });

  @override
  Map<String, Object?> toMap() => <String, Object?>{
    'unavailable_handling': unavailableHandling.serialName,
    'impact_tier': impactTier.serialName,
    'adjacent_inversion_severity': adjacentInversionSeverity.serialName,
    'partial_inversion_severity': partialInversionSeverity.serialName,
    'full_reversal_severity': fullReversalSeverity.serialName,
    'independent_of_pitch': independentOfPitch,
    'rematching_allowed': rematchingAllowed,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderPolicySpec &&
          other.unavailableHandling == unavailableHandling &&
          other.impactTier == impactTier &&
          other.adjacentInversionSeverity == adjacentInversionSeverity &&
          other.partialInversionSeverity == partialInversionSeverity &&
          other.fullReversalSeverity == fullReversalSeverity &&
          other.independentOfPitch == independentOfPitch &&
          other.rematchingAllowed == rematchingAllowed;

  @override
  int get hashCode => Object.hash(
    unavailableHandling,
    impactTier,
    adjacentInversionSeverity,
    partialInversionSeverity,
    fullReversalSeverity,
    independentOfPitch,
    rematchingAllowed,
  );
}

/// IOI policy.
///
/// Inter-onset-interval consistency is measured against the learner's own mean
/// interval; the same deviation is never double-charged as a timing error.
final class IoiPolicySpec extends DimensionPolicySpec {
  final ToleranceSpec? tolerance;
  final SeverityBandTable severityBands;
  final String comparisonBasis;
  final bool doubleChargesTiming;

  IoiPolicySpec({
    super.unavailableHandling = UnavailableHandling.noPenalty,
    required this.tolerance,
    required this.severityBands,
    required this.comparisonBasis,
    required this.doubleChargesTiming,
  });

  /// Severity for a percent deviation from the learner's mean interval.
  SeverityTier classifySeverity(num deviationPercent) =>
      severityBands.classify(deviationPercent);

  @override
  Map<String, Object?> toMap() => <String, Object?>{
    'unavailable_handling': unavailableHandling.serialName,
    'tolerance': tolerance?.toMap(),
    'severity_bands': severityBands.toMap(),
    'comparison_basis': comparisonBasis,
    'double_charges_timing': doubleChargesTiming,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IoiPolicySpec &&
          other.unavailableHandling == unavailableHandling &&
          other.tolerance == tolerance &&
          other.severityBands == severityBands &&
          other.comparisonBasis == comparisonBasis &&
          other.doubleChargesTiming == doubleChargesTiming;

  @override
  int get hashCode => Object.hash(
    unavailableHandling,
    tolerance,
    severityBands,
    comparisonBasis,
    doubleChargesTiming,
  );
}

/// Simultaneity policy.
///
/// Decided: tolerance tightens with learner level; missing members do not make
/// the played chord automatically unjudgeable; extra notes are excluded from
/// simultaneity and remain descriptive extra-note errors. Every level tolerance
/// value is UNRESOLVED.
final class SimultaneityPolicySpec extends DimensionPolicySpec {
  final Map<LearnerLevelKey, ToleranceSpec> levelTolerances;
  final Map<LearnerLevelKey, SeverityBandTable> levelSeverityMs;
  final bool missingMembersDoNotInvalidate;
  final bool excludesExtraNotes;

  SimultaneityPolicySpec({
    super.unavailableHandling = UnavailableHandling.noPenalty,
    required Map<LearnerLevelKey, ToleranceSpec> levelTolerances,
    required Map<LearnerLevelKey, SeverityBandTable> levelSeverityMs,
    required this.missingMembersDoNotInvalidate,
    required this.excludesExtraNotes,
  }) : levelTolerances = Map<LearnerLevelKey, ToleranceSpec>.unmodifiable(
         levelTolerances,
       ),
       levelSeverityMs = Map<LearnerLevelKey, SeverityBandTable>.unmodifiable(
         levelSeverityMs,
       );

  /// Severity for an observed chord spread in milliseconds at [level].
  SeverityTier classifySeverity(LearnerLevelKey level, num spreadMs) =>
      levelSeverityMs[level]!.classify(spreadMs);

  /// Every learner level must carry exactly one severity table.
  void validateLevelCoverage() {
    for (final level in LearnerLevelKey.values) {
      if (!levelSeverityMs.containsKey(level)) {
        throw FormatException(
          'SimultaneityPolicySpec: unknown/missing learner-level mapping '
          '${level.serialName}.',
        );
      }
    }
  }

  @override
  Map<String, Object?> toMap() => <String, Object?>{
    'unavailable_handling': unavailableHandling.serialName,
    'level_tolerances': <String, Object?>{
      for (final entry in levelTolerances.entries)
        entry.key.serialName: entry.value.toMap(),
    },
    'level_severity_ms': <String, Object?>{
      for (final entry in levelSeverityMs.entries)
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
          _levelSeverityMapEq(other.levelSeverityMs, levelSeverityMs) &&
          other.missingMembersDoNotInvalidate ==
              missingMembersDoNotInvalidate &&
          other.excludesExtraNotes == excludesExtraNotes;

  @override
  int get hashCode => Object.hash(
    unavailableHandling,
    _toleranceMapContentHash(levelTolerances),
    _levelSeverityMapHash(levelSeverityMs),
    missingMembersDoNotInvalidate,
    excludesExtraNotes,
  );
}

/// Retrieval Latency policy.
///
/// Enabled for every mode but always UNAVAILABLE in the MVP because no frozen
/// model provides a runtime performance anchor. It produces no severity and no
/// star impact; no threshold is invented.
final class RetrievalLatencyPolicySpec extends DimensionPolicySpec {
  final bool enabledForAllModes;
  final bool producesSeverity;
  final bool producesStarImpact;
  final ErrorVectorReasonCode unavailableReasonCode;

  const RetrievalLatencyPolicySpec({
    super.unavailableHandling = UnavailableHandling.noPenalty,
    required this.enabledForAllModes,
    required this.producesSeverity,
    required this.producesStarImpact,
    required this.unavailableReasonCode,
  });

  @override
  Map<String, Object?> toMap() => <String, Object?>{
    'unavailable_handling': unavailableHandling.serialName,
    'enabled_for_all_modes': enabledForAllModes,
    'produces_severity': producesSeverity,
    'produces_star_impact': producesStarImpact,
    'unavailable_reason_code': unavailableReasonCode.serialName,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RetrievalLatencyPolicySpec &&
          other.unavailableHandling == unavailableHandling &&
          other.enabledForAllModes == enabledForAllModes &&
          other.producesSeverity == producesSeverity &&
          other.producesStarImpact == producesStarImpact &&
          other.unavailableReasonCode == unavailableReasonCode;

  @override
  int get hashCode => Object.hash(
    unavailableHandling,
    enabledForAllModes,
    producesSeverity,
    producesStarImpact,
    unavailableReasonCode,
  );
}

/// The single mutable-free container of an Evaluation Policy profile: identity,
/// versioning, provenance, six dimension specs, star-quality policy, the star
/// aggregation rules, the result-state model, the Error Vector policy, the
/// materialized applicability table, and the NOT_APPLICABLE handling.
///
/// This is DATA, not behavior. No evaluation algorithm lives here. Every value
/// decided by H2.9G is materialized; a consuming algorithm must read its
/// thresholds from this profile and must not hard-code grading literals.
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
  final EvaluabilityPolicy evaluability;
  final ResultStatePolicy resultState;
  final ErrorVectorPolicy errorVector;
  final EvaluationPolicyApplicability applicability;
  final NotApplicableHandling notApplicableHandling;

  /// Only [PolicyResolutionLayer.profile] (plus per-mode applicability) is
  /// resolved today; every deeper layer is explicitly unresolved.
  final PolicyResolutionLayer appliedResolutionDepth;
  final Set<PolicyResolutionLayer> unresolvedPrecedenceLayers;

  static final EvaluationPolicyProfile instance =
      EvaluationPolicyProfile.build();

  EvaluationPolicyProfile({
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
    required this.evaluability,
    required this.resultState,
    required this.errorVector,
    required this.applicability,
    required this.notApplicableHandling,
    required this.appliedResolutionDepth,
    required Set<PolicyResolutionLayer> unresolvedPrecedenceLayers,
  }) : unresolvedPrecedenceLayers = Set<PolicyResolutionLayer>.unmodifiable(
         unresolvedPrecedenceLayers,
       );

  /// Deterministically builds the materialized `mvp_default_v1` profile from
  /// the locked H2.9G decisions.
  factory EvaluationPolicyProfile.build() {
    return EvaluationPolicyProfile(
      profileIdValue: profileId,
      contractVersionValue: contractVersion,
      policyVersionValue: policyVersion,
      provenance: const ContractSourceProvenance(
        sourceKind: 'repository_code',
        sourcePath: 'lib/midi/domain/evaluation_input.dart',
        sourceIdentifier: 'MvpDefaultEvaluationProfile',
      ),
      pitch: PitchPolicySpec(
        exactMidiIdentity: true,
        oneToOneMatching: true,
        toleranceApplied: false,
        spellingComparison: false,
        rematchingAllowed: false,
        alignmentAuthority: 'H2.6',
        extraNotesArePitchErrors: false,
        wrongNoteSeverity: _pitchWrongNoteSeverity,
      ),
      timing: TimingPolicySpec(
        firstNoteIsStartReference: true,
        firstNoteLatenessPenalized: false,
        tightensWithTempo: true,
        tempoDependencyKind: TimingTempoDependencyKind.normalizedRatio,
        baseTolerance: null,
        toleranceRatio: const ProportionalTolerance(
          percent: 5,
          rounding: ToleranceRoundingMode.nearest,
        ),
        severityBands: _timingSeverity,
        severityReferenceIntervalMs: 500,
      ),
      order: const OrderPolicySpec(
        impactTier: OrderImpactTier.lowerThanPrimaryPitch,
        adjacentInversionSeverity: SeverityTier.minor,
        partialInversionSeverity: SeverityTier.moderate,
        fullReversalSeverity: SeverityTier.major,
        independentOfPitch: true,
        rematchingAllowed: false,
      ),
      simultaneity: SimultaneityPolicySpec(
        levelTolerances: <LearnerLevelKey, ToleranceSpec>{
          // Level thresholds are carried by the severity tables below; the
          // legacy per-level tolerance slot stays unresolved.
          LearnerLevelKey.beginner: ToleranceSpec(),
          LearnerLevelKey.intermediate: ToleranceSpec(),
          LearnerLevelKey.advanced: ToleranceSpec(),
        },
        levelSeverityMs: _simultaneitySeverity,
        missingMembersDoNotInvalidate: true,
        excludesExtraNotes: true,
      ),
      ioi: IoiPolicySpec(
        tolerance: null,
        severityBands: _ioiSeverity,
        comparisonBasis: 'learner_mean_interval',
        doubleChargesTiming: false,
      ),
      retrievalLatency: const RetrievalLatencyPolicySpec(
        enabledForAllModes: true,
        producesSeverity: false,
        producesStarImpact: false,
        unavailableReasonCode:
            ErrorVectorReasonCode.retrievalLatencyUnavailable,
      ),
      stars: StarQualityPolicy(
        primarySeverityModel: PrimarySeverityModel.worstErrorWithMinorTrims,
        allowZeroStars: true,
        minorTrimCount: 2,
        missingNote: MissingNoteStarPolicy(
          countSensitive: true,
          oneMissingNoteCapStars: 4,
          perAdditionalMissingCapStars: null,
          capTable: _missingNoteCaps,
          appliedAfterBaseAndTrims: true,
          isCeilingNotSeverity: true,
          invalidatesSimultaneity: false,
        ),
        extraNote: ExtraNoteStarPolicy(
          imposesHardCap: false,
          hardCapStars: null,
          excludedFromSimultaneity: true,
          severityByCount: _extraNoteSeverity,
        ),
        lessonStarCapacity: 10,
        accumulation: StarAccumulationKind.cappedProgress,
        baseStars: const <SeverityTier, int>{
          SeverityTier.none: 5,
          SeverityTier.negligible: 5,
          SeverityTier.minor: 4,
          SeverityTier.moderate: 3,
          SeverityTier.major: 2,
        },
        minimumTrimSeverity: SeverityTier.minor,
        worstErrorEstablishesBase: true,
        worstErrorTrims: false,
        fractionalStars: false,
        lessonStarsMonotonic: true,
        lessonStarsDecay: false,
        lessonStarsSeparateFromMastery: true,
        tempoProgressionThresholdStars: 4,
        bands: StarQualityPolicy.standardBands,
      ),
      evaluability: const EvaluabilityPolicy(
        requiresStructuralAssociation: true,
        basedOnPitchCorrectness: false,
        zeroAssociationsMeansNotEnoughPerformance: true,
        associationAuthority: 'H2.6',
      ),
      resultState: ResultStatePolicy(
        insufficientDataState: EvaluationResultState.notEnoughPerformance,
        evaluatedMinStars: 0,
        evaluatedMaxStars: 5,
        producesAggregatePassFail: false,
        notEnoughPerformanceEqualsZeroStars: false,
        lifecycleStatesOutsideResult: const <String>[
          'INVALIDATED',
          'ABANDONED',
          'FAILED',
        ],
      ),
      errorVector: ErrorVectorPolicy(
        reasonCodes: ErrorVectorReasonCode.values,
        descriptiveOnly: true,
        carriesStarsOrWeights: false,
        mutatesMasteryEvidence: false,
      ),
      applicability: _buildApplicability(),
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

  static EvaluationPolicyApplicability _buildApplicability() {
    final enabled = <TargetMode, Set<EvaluationDimension>>{};
    final notApplicable = <TargetMode, Set<EvaluationDimension>>{};
    for (final mode in TargetMode.values) {
      final modeEnabled = MvpDefaultEvaluationProfile.instance
          .enabledDimensions(mode);
      enabled[mode] = modeEnabled;
      notApplicable[mode] = <EvaluationDimension>{
        for (final dimension in EvaluationDimension.values)
          if (!modeEnabled.contains(dimension)) dimension,
      };
    }
    return EvaluationPolicyApplicability(
      enabled: enabled,
      notApplicable: notApplicable,
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

  /// True for the materialized MVP profile: every applicable dimension carries
  /// executable severity data.
  bool get containsResolvedDimensionThresholds =>
      timing.severityBands.bands.isNotEmpty &&
      ioi.severityBands.bands.isNotEmpty &&
      simultaneity.levelSeverityMs.isNotEmpty;

  /// Deterministically rejects malformed profiles.
  void validate() {
    if (profileIdValue != profileId ||
        contractVersionValue != contractVersion) {
      throw const FormatException(
        'EvaluationPolicyProfile: incompatible profile identity or contract '
        'version.',
      );
    }
    if (dimensionSpecs.length != EvaluationDimension.values.length) {
      throw const FormatException(
        'EvaluationPolicyProfile: every evaluation dimension requires a '
        'policy.',
      );
    }
    pitch.wrongNoteSeverity.validate();
    timing.severityBands.validate();
    ioi.severityBands.validate();
    simultaneity.validateLevelCoverage();
    for (final table in simultaneity.levelSeverityMs.values) {
      table.validate();
    }
    stars.validate();
    errorVector.validate();
    applicability.validate();
    resultState.validate();
  }

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
    'evaluability': evaluability.toMap(),
    'result_state': resultState.toMap(),
    'error_vector': errorVector.toMap(),
    'applicability': applicability.toMap(),
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
          other.evaluability == evaluability &&
          other.resultState == resultState &&
          other.errorVector == errorVector &&
          other.applicability == applicability &&
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
    evaluability,
    resultState,
    errorVector,
    applicability,
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

bool _severityBandListEq(List<SeverityBand> a, List<SeverityBand> b) {
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

bool _missingNoteCapListEq(List<MissingNoteCap> a, List<MissingNoteCap> b) {
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

bool _reasonCodeListEq(
  List<ErrorVectorReasonCode> a,
  List<ErrorVectorReasonCode> b,
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

bool _stringListEq(List<String> a, List<String> b) {
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

bool _severityStarMapEq(Map<SeverityTier, int> a, Map<SeverityTier, int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (final tier in SeverityTier.values) {
    if (a[tier] != b[tier]) {
      return false;
    }
  }
  return true;
}

int _severityStarMapHash(Map<SeverityTier, int> map) {
  var hash = 0;
  for (final tier in SeverityTier.values) {
    hash = Object.hash(hash, tier, map[tier]);
  }
  return hash;
}

bool _levelSeverityMapEq(
  Map<LearnerLevelKey, SeverityBandTable> a,
  Map<LearnerLevelKey, SeverityBandTable> b,
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

int _levelSeverityMapHash(Map<LearnerLevelKey, SeverityBandTable> map) {
  var hash = 0;
  for (final key in LearnerLevelKey.values) {
    hash = Object.hash(hash, key, map[key]);
  }
  return hash;
}

List<String> _dimensionSerials(Set<EvaluationDimension> dimensions) => <String>[
  for (final dimension in EvaluationDimension.values)
    if (dimensions.contains(dimension)) _dimensionSerial(dimension),
];

Map<TargetMode, Set<EvaluationDimension>> _freezeDimensionSets(
  Map<TargetMode, Set<EvaluationDimension>> source,
) => Map<TargetMode, Set<EvaluationDimension>>.unmodifiable(
  <TargetMode, Set<EvaluationDimension>>{
    for (final mode in TargetMode.values)
      mode: Set<EvaluationDimension>.unmodifiable(
        source[mode] ?? const <EvaluationDimension>{},
      ),
  },
);

bool _applicabilityMapEq(
  Map<TargetMode, Set<EvaluationDimension>> a,
  Map<TargetMode, Set<EvaluationDimension>> b,
) {
  if (a.length != b.length) {
    return false;
  }
  for (final mode in TargetMode.values) {
    final first = a[mode];
    final second = b[mode];
    if (first == null || second == null) {
      if (first != second) {
        return false;
      }
      continue;
    }
    if (first.length != second.length || !first.containsAll(second)) {
      return false;
    }
  }
  return true;
}

int _applicabilityMapHash(Map<TargetMode, Set<EvaluationDimension>> map) {
  var hash = 0;
  for (final mode in TargetMode.values) {
    hash = Object.hash(
      hash,
      mode,
      Object.hashAll(_dimensionSerials(map[mode] ?? const {})),
    );
  }
  return hash;
}

bool _nullableMapEq(Map<String, Object?>? a, Map<String, Object?>? b) {
  if (identical(a, b)) {
    return true;
  }
  if (a == null || b == null || a.length != b.length) {
    return false;
  }
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

int _nullableMapHash(Map<String, Object?> map) {
  final keys = map.keys.toList()..sort();
  var hash = 0;
  for (final key in keys) {
    hash = Object.hash(hash, key, map[key]);
  }
  return hash;
}

// ---- Materialized mvp_default_v1 grading data (H2.9G) ----
//
// All numeric grading values live here as data. No consuming algorithm may
// hard-code these thresholds.

final SeverityBandTable _pitchWrongNoteSeverity = SeverityBandTable(
  bands: const <SeverityBand>[
    SeverityBand(
      severity: SeverityTier.none,
      upperBound: 0,
      upperBoundary: PolicyBoundary.inclusive,
    ),
    SeverityBand(
      severity: SeverityTier.minor,
      upperBound: 1,
      upperBoundary: PolicyBoundary.inclusive,
    ),
    SeverityBand(
      severity: SeverityTier.moderate,
      upperBound: 2,
      upperBoundary: PolicyBoundary.inclusive,
    ),
    SeverityBand(severity: SeverityTier.major),
  ],
);

final SeverityBandTable _extraNoteSeverity = SeverityBandTable(
  bands: const <SeverityBand>[
    SeverityBand(
      severity: SeverityTier.none,
      upperBound: 0,
      upperBoundary: PolicyBoundary.inclusive,
    ),
    SeverityBand(
      severity: SeverityTier.negligible,
      upperBound: 1,
      upperBoundary: PolicyBoundary.inclusive,
    ),
    SeverityBand(
      severity: SeverityTier.minor,
      upperBound: 2,
      upperBoundary: PolicyBoundary.inclusive,
    ),
    SeverityBand(severity: SeverityTier.moderate),
  ],
);

final SeverityBandTable _timingSeverity = SeverityBandTable(
  bands: const <SeverityBand>[
    SeverityBand(
      severity: SeverityTier.negligible,
      upperBound: 4,
      upperBoundary: PolicyBoundary.inclusive,
    ),
    SeverityBand(
      severity: SeverityTier.minor,
      upperBound: 8,
      upperBoundary: PolicyBoundary.inclusive,
    ),
    SeverityBand(
      severity: SeverityTier.moderate,
      upperBound: 15,
      upperBoundary: PolicyBoundary.inclusive,
    ),
    SeverityBand(severity: SeverityTier.major),
  ],
);

final SeverityBandTable _ioiSeverity = SeverityBandTable(
  bands: const <SeverityBand>[
    SeverityBand(
      severity: SeverityTier.negligible,
      upperBound: 5,
      upperBoundary: PolicyBoundary.inclusive,
    ),
    SeverityBand(
      severity: SeverityTier.minor,
      upperBound: 10,
      upperBoundary: PolicyBoundary.inclusive,
    ),
    SeverityBand(
      severity: SeverityTier.moderate,
      upperBound: 20,
      upperBoundary: PolicyBoundary.inclusive,
    ),
    SeverityBand(severity: SeverityTier.major),
  ],
);

final Map<LearnerLevelKey, SeverityBandTable> _simultaneitySeverity =
    <LearnerLevelKey, SeverityBandTable>{
      LearnerLevelKey.beginner: SeverityBandTable(
        bands: const <SeverityBand>[
          SeverityBand(
            severity: SeverityTier.negligible,
            upperBound: 40,
            upperBoundary: PolicyBoundary.inclusive,
          ),
          SeverityBand(
            severity: SeverityTier.minor,
            upperBound: 80,
            upperBoundary: PolicyBoundary.inclusive,
          ),
          SeverityBand(severity: SeverityTier.major),
        ],
      ),
      LearnerLevelKey.intermediate: SeverityBandTable(
        bands: const <SeverityBand>[
          SeverityBand(
            severity: SeverityTier.negligible,
            upperBound: 30,
            upperBoundary: PolicyBoundary.inclusive,
          ),
          SeverityBand(
            severity: SeverityTier.minor,
            upperBound: 60,
            upperBoundary: PolicyBoundary.inclusive,
          ),
          SeverityBand(severity: SeverityTier.major),
        ],
      ),
      LearnerLevelKey.advanced: SeverityBandTable(
        bands: const <SeverityBand>[
          SeverityBand(
            severity: SeverityTier.negligible,
            upperBound: 20,
            upperBoundary: PolicyBoundary.inclusive,
          ),
          SeverityBand(
            severity: SeverityTier.minor,
            upperBound: 40,
            upperBoundary: PolicyBoundary.inclusive,
          ),
          SeverityBand(severity: SeverityTier.major),
        ],
      ),
    };

final MissingNoteCapTable _missingNoteCaps = MissingNoteCapTable(
  caps: const <MissingNoteCap>[
    MissingNoteCap(minimumMissingCount: 0, maxStars: null),
    MissingNoteCap(minimumMissingCount: 1, maxStars: 4),
    MissingNoteCap(minimumMissingCount: 2, maxStars: 3),
    MissingNoteCap(minimumMissingCount: 3, maxStars: 2),
    MissingNoteCap(minimumMissingCount: 4, maxStars: 1),
  ],
);
