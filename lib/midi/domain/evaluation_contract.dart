import 'evaluation_input.dart';
import 'expected_musical_target.dart';

/// Materialization status of one Evaluation Contract rule.
///
/// * [defined] - explicitly established by a committed repository source.
/// * [derived] - follows mechanically from already locked facts without a new
///   policy choice (for example Block/Arpeggio NOT_APPLICABLE applicability).
/// * [unresolved] - the repository does not establish the rule; this is not
///   permission to guess.
/// * [notApplicable] - the rule does not apply to the given mode/dimension.
enum ContractRuleStatus {
  defined,
  derived,
  unresolved,
  notApplicable;

  String get serialName => switch (this) {
    ContractRuleStatus.defined => 'DEFINED',
    ContractRuleStatus.derived => 'DERIVED',
    ContractRuleStatus.unresolved => 'UNRESOLVED',
    ContractRuleStatus.notApplicable => 'NOT_APPLICABLE',
  };
}

/// Traceable repository source of a [ContractRuleStatus.defined] or
/// [ContractRuleStatus.derived] rule.
final class ContractSourceProvenance {
  /// 'repository_code', 'repository_test', or 'repository_documentation'.
  final String sourceKind;

  /// Repository-relative path of the source.
  final String sourcePath;

  /// Stable identifier of the source (model/enum/constant/test name).
  final String sourceIdentifier;

  const ContractSourceProvenance({
    required this.sourceKind,
    required this.sourcePath,
    required this.sourceIdentifier,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContractSourceProvenance &&
          other.sourceKind == sourceKind &&
          other.sourcePath == sourcePath &&
          other.sourceIdentifier == sourceIdentifier;

  @override
  int get hashCode => Object.hash(sourceKind, sourcePath, sourceIdentifier);

  Map<String, Object?> toMap() => <String, Object?>{
    'source_kind': sourceKind,
    'source_path': sourcePath,
    'source_identifier': sourceIdentifier,
  };
}

/// One materialized Evaluation Contract rule with traceable status.
///
/// A [contractValueMs] may only be carried by a resolved rule: a numeric policy
/// value with no repository provenance can never be represented.
final class ContractRule {
  /// Stable section identifier, for example `timing_threshold`.
  final String section;

  final ContractRuleStatus status;

  /// Required for [ContractRuleStatus.defined] and [ContractRuleStatus.derived].
  final ContractSourceProvenance? provenance;

  /// Repository-grounded explanation, for example the derivation chain of a
  /// [ContractRuleStatus.derived] rule.
  final String? note;

  /// Required for [ContractRuleStatus.unresolved]; states exactly what is
  /// missing and why.
  final String? unresolvedReason;

  /// Contract value, null unless the repository defines one. Always null for
  /// the MVP materialization.
  final double? contractValueMs;

  ContractRule({
    required this.section,
    required this.status,
    this.provenance,
    this.note,
    this.unresolvedReason,
    this.contractValueMs,
  }) {
    final bool resolved =
        status == ContractRuleStatus.defined ||
        status == ContractRuleStatus.derived;
    if (resolved && provenance == null) {
      throw FormatException(
        'ContractRule $section: a $status rule requires provenance.',
      );
    }
    if (resolved && unresolvedReason != null) {
      throw FormatException(
        'ContractRule $section: a $status rule must not carry an '
        'unresolved reason.',
      );
    }
    if (!resolved && contractValueMs != null) {
      throw FormatException(
        'ContractRule $section: a policy value requires a resolved status.',
      );
    }
    if (status == ContractRuleStatus.unresolved && unresolvedReason == null) {
      throw FormatException(
        'ContractRule $section: an unresolved rule must state why.',
      );
    }
  }

  bool get isDefined => status == ContractRuleStatus.defined;
  bool get isDerived => status == ContractRuleStatus.derived;
  bool get isResolved => isDefined || isDerived;
  bool get isUnresolved => status == ContractRuleStatus.unresolved;

  Map<String, Object?> toMap() => <String, Object?>{
    'section': section,
    'status': status.serialName,
    'provenance': provenance?.toMap(),
    'note': note,
    'unresolved_reason': unresolvedReason,
    'value_ms': contractValueMs,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContractRule &&
          other.section == section &&
          other.status == status &&
          other.provenance == provenance &&
          other.note == note &&
          other.unresolvedReason == unresolvedReason &&
          other.contractValueMs == contractValueMs;

  @override
  int get hashCode => Object.hash(
    section,
    status,
    provenance,
    note,
    unresolvedReason,
    contractValueMs,
  );
}

/// Per-dimension materialized contract bundle.
final class DimensionEvaluationContract {
  final EvaluationDimension dimension;

  final Map<TargetMode, ContractRule> _applicability;

  /// Which neutral observations the dimension consumes and that H2.8 passes
  /// them through unchanged.
  final ContractRule input;

  final ContractRule metric;
  final ContractRule verdictVocabulary;
  final ContractRule threshold;
  final ContractRule boundary;
  final ContractRule unavailableBehavior;
  final ContractRule notApplicableRepresentation;

  DimensionEvaluationContract({
    required this.dimension,
    required Map<TargetMode, ContractRule> applicability,
    required this.input,
    required this.metric,
    required this.verdictVocabulary,
    required this.threshold,
    required this.boundary,
    required this.unavailableBehavior,
    required this.notApplicableRepresentation,
  }) : _applicability = Map<TargetMode, ContractRule>.unmodifiable(
         applicability,
       ) {
    for (final mode in TargetMode.values) {
      if (!_applicability.containsKey(mode)) {
        throw FormatException(
          'DimensionEvaluationContract $dimension: missing applicability '
          'for $mode.',
        );
      }
    }
  }

  ContractRule applicability(TargetMode mode) => _applicability[mode]!;

  Map<TargetMode, ContractRule> get applicabilityMap => _applicability;

  /// All rules of this dimension in a stable order.
  Iterable<ContractRule> get allRules sync* {
    yield applicability(TargetMode.block);
    yield applicability(TargetMode.arpeggio);
    yield input;
    yield metric;
    yield verdictVocabulary;
    yield threshold;
    yield boundary;
    yield unavailableBehavior;
    yield notApplicableRepresentation;
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'dimension': _dimensionSerial(dimension),
    'rules': <String, Object?>{
      for (final rule in allRules) rule.section: rule.toMap(),
    },
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DimensionEvaluationContract &&
          other.dimension == dimension &&
          _modeRuleMapEq(other._applicability, _applicability) &&
          other.input == input &&
          other.metric == metric &&
          other.verdictVocabulary == verdictVocabulary &&
          other.threshold == threshold &&
          other.boundary == boundary &&
          other.unavailableBehavior == unavailableBehavior &&
          other.notApplicableRepresentation == notApplicableRepresentation;

  @override
  int get hashCode => Object.hash(
    dimension,
    _modeRuleMapHash(_applicability),
    input,
    metric,
    verdictVocabulary,
    threshold,
    boundary,
    unavailableBehavior,
    notApplicableRepresentation,
  );
}

/// The materialized, repository-resident representation of Evaluation Contract
/// v1.1 as far as it is actually established by the committed code.
///
/// This is a specification artifact, not an executor: it carries no evaluation
/// function, no verdict logic, and no invented policy. Rules that the
/// repository cannot establish are materialized as
/// [ContractRuleStatus.unresolved] with the exact reason documented.
///
/// Identity, profile applicability, input vocabulary, observation-state
/// semantics, the retrieval-latency runtime state, provenance vocabulary,
/// determinism, and diagnostic isolation are established facts. Verdict
/// vocabulary, metrics, thresholds, boundaries, unavailable/not-applicable
/// result behavior, Error Vector, aggregate result, aggregation precedence,
/// and result provenance format are [ContractRuleStatus.unresolved]: the
/// repository does not contain them.
final class EvaluationContract {
  /// Locked identity reproduced from [MvpDefaultEvaluationProfile].
  static const String contractName = 'Evaluation Contract';
  static const String contractVersion = 'v1.1';
  static const String profileId = 'mvp_default_v1';
  static const String profileVersion = 'v1.1';

  /// Committed reason for the retrieval-latency runtime state.
  static const String retrievalLatencyUnavailableReason =
      'NO_RUNTIME_PERFORMANCE_ANCHOR';

  // ---- Global rules ----

  final ContractRule identity;
  final ContractRule profile;

  /// Observation-layer state vocabulary: [EvaluationDimensionState] and
  /// [DataAvailability] are independent.
  final ContractRule observationStateVocabulary;
  final ContractRule unavailableObservationSemantics;
  final ContractRule notApplicableObservationSemantics;
  final ContractRule retrievalLatencyRuntimeState;
  final ContractRule verdictVocabulary;
  final ContractRule errorVector;
  final ContractRule aggregateResult;
  final ContractRule aggregationPrecedence;
  final ContractRule determinismRequirement;
  final ContractRule provenanceRequirement;
  final ContractRule resultProvenanceFormat;
  final ContractRule diagnosticsIsolation;

  final List<DimensionEvaluationContract> dimensions;
  final Map<EvaluationDimension, DimensionEvaluationContract> byDimension;
  final EvaluationPolicySnapshot policySnapshot;
  final List<String> diagnosticNonPolicySources;

  EvaluationContract._({
    required this.identity,
    required this.profile,
    required this.observationStateVocabulary,
    required this.unavailableObservationSemantics,
    required this.notApplicableObservationSemantics,
    required this.retrievalLatencyRuntimeState,
    required this.verdictVocabulary,
    required this.errorVector,
    required this.aggregateResult,
    required this.aggregationPrecedence,
    required this.determinismRequirement,
    required this.provenanceRequirement,
    required this.resultProvenanceFormat,
    required this.diagnosticsIsolation,
    required List<DimensionEvaluationContract> dimensions,
    required this.policySnapshot,
    required List<String> diagnosticNonPolicySources,
  }) : dimensions = List<DimensionEvaluationContract>.unmodifiable(dimensions),
       diagnosticNonPolicySources = List<String>.unmodifiable(
         diagnosticNonPolicySources,
       ),
       byDimension =
           Map<EvaluationDimension, DimensionEvaluationContract>.unmodifiable({
             for (final dimension in dimensions) dimension.dimension: dimension,
           });

  /// The single executable instance of the materialized contract.
  static final EvaluationContract instance = EvaluationContract.build();

  /// Deterministically builds a fresh instance from the committed constants.
  factory EvaluationContract.build() {
    return EvaluationContract._(
      identity: _defined(
        'contract_identity',
        'lib/midi/domain/evaluation_input.dart',
        'MvpDefaultEvaluationProfile.contractVersion (documented as '
            'Evaluation Contract v1.1)',
        'contract_name and contract_version are locked to Evaluation '
            'Contract v1.1.',
      ),
      profile: _defined(
        'profile_identity',
        'lib/midi/domain/evaluation_input.dart',
        'MvpDefaultEvaluationProfile',
        'The locked, single MVP Evaluation Profile.',
      ),
      observationStateVocabulary: _defined(
        'observation_state_vocabulary',
        'lib/midi/domain/evaluation_input.dart',
        'EvaluationDimensionState / DataAvailability',
        'dimensionState (enabled/notApplicable) is independent of '
            'dataAvailability (available/unavailable); an enabled dimension '
            'may report unavailable data.',
      ),
      unavailableObservationSemantics: _defined(
        'unavailable_observation_semantics',
        'lib/midi/domain/evaluation_input.dart',
        'EvaluationDimensionInput (enabled + unavailable combinations)',
        'H2.8 represents enabled-but-unavailable dimensions explicitly; '
            'that state is never downgraded to notApplicable.',
      ),
      notApplicableObservationSemantics: _defined(
        'not_applicable_observation_semantics',
        'lib/midi/domain/evaluation_input.dart',
        'PitchEvaluationInput (and sibling inputs) notApplicable invariant',
        'A NOT_APPLICABLE dimension must carry no observations; enforced by '
            'H2.8 FormatException invariants.',
      ),
      retrievalLatencyRuntimeState: _defined(
        'retrieval_latency_runtime_state',
        'lib/midi/application/evaluation_dimension_observation_extractor.dart',
        "RetrievalLatencyObservation / 'NO_RUNTIME_PERFORMANCE_ANCHOR'",
        'No frozen model provides a performance anchor and no anchor '
            'substitute is fabricated; H2.8 projects ENABLED + UNAVAILABLE '
            'with reason NO_RUNTIME_PERFORMANCE_ANCHOR.',
      ),
      verdictVocabulary: _unresolved(
        'verdict_vocabulary',
        'No PASS/FAIL/CORRECT/INCORRECT or any other verdict vocabulary is '
            'defined anywhere in the repository.',
      ),
      errorVector: _unresolved(
        'error_vector',
        'No Error Vector representation, fields, weights, or severity model '
            'exists. The only repository reference is negative: the H2.5 '
            'leakage test forbids an "error_vector" key in the '
            'expected-target projection.',
      ),
      aggregateResult: _unresolved(
        'aggregate_result',
        'No EvaluationResult model exists; lib/midi/domain/evaluation_input.dart '
            'states that no EvaluationResult/verdict/score lives in the '
            'evaluation input.',
      ),
      aggregationPrecedence: _unresolved(
        'aggregation_precedence',
        'No dimension precedence, voting, weighted scoring, or '
            'required-dimension aggregation rule exists in the repository.',
      ),
      determinismRequirement: _defined(
        'determinism_requirement',
        'test/evaluation_input_preparer_test.dart',
        "'determinism identical input yields identical stable projection' | "
            "'immutability mutating source collections cannot mutate "
            "EvaluationInput'",
        'The committed pipeline is deterministic and immutable; a value '
            'equal and structurally stable projection is required.',
      ),
      provenanceRequirement: _defined(
        'provenance_requirement',
        'lib/midi/domain/evaluation_input.dart',
        'EvaluationInput (evaluationProfileId, evaluationProfileVersion, '
            'targetId, sessionId, mode, algorithm versions)',
        'Identity vocabulary is already carried by the canonical input.',
      ),
      resultProvenanceFormat: _unresolved(
        'result_provenance_format',
        'The provenance vocabulary is established by EvaluationInput, but no '
            'result model defines how a result encodes it.',
      ),
      diagnosticsIsolation: _defined(
        'diagnostics_isolation',
        'lib/midi/diagnostics/diagnostic_analysis.dart',
        'Documented drafts: 60 ms simultaneity window / 5 ms duplicate '
            'threshold',
        'The only numeric window in the repository is a diagnostic value. No '
            'evaluation model references any H1/H2.2 diagnostic threshold.',
      ),
      dimensions: <DimensionEvaluationContract>[
        _pitch(),
        _timing(),
        _order(),
        _simultaneity(),
        _ioi(),
        _retrievalLatency(),
      ],
      policySnapshot: EvaluationPolicySnapshot(
        profileId: profileId,
        profileVersion: profileVersion,
      ),
      diagnosticNonPolicySources: <String>[
        'lib/midi/diagnostics/diagnostic_analysis.dart - '
            'DiagnosticAnalysisConfig.simultaneityWindowMs (60 ms burst '
            'window, diagnostic only)',
        'lib/midi/diagnostics/diagnostic_analysis.dart - duplicate threshold '
            '(5 ms, diagnostic only)',
        'lib/midi/diagnostics/midi_diagnostic_metrics.dart - diagnostic '
            'derived metrics (no evaluation meaning)',
      ],
    );
  }

  /// The artifact cannot be consumed as executable evaluation policy: it is a
  /// specification with no entry point and no resolved threshold value.
  bool get containsExecutablePolicy => false;

  int get definedRuleCount => allRules.where((rule) => rule.isDefined).length;
  int get derivedRuleCount => allRules.where((rule) => rule.isDerived).length;
  int get unresolvedRuleCount =>
      allRules.where((rule) => rule.isUnresolved).length;

  /// Every materialized rule in a stable order.
  Iterable<ContractRule> get allRules sync* {
    yield identity;
    yield profile;
    yield observationStateVocabulary;
    yield unavailableObservationSemantics;
    yield notApplicableObservationSemantics;
    yield retrievalLatencyRuntimeState;
    yield verdictVocabulary;
    yield errorVector;
    yield aggregateResult;
    yield aggregationPrecedence;
    yield determinismRequirement;
    yield provenanceRequirement;
    yield resultProvenanceFormat;
    yield diagnosticsIsolation;
    for (final dimension in dimensions) {
      yield* dimension.allRules;
    }
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'contract_name': contractName,
    'contract_version': contractVersion,
    'profile_id': profileId,
    'profile_version': profileVersion,
    'global_rules': <String, Object?>{
      for (final rule in <ContractRule>[
        identity,
        profile,
        observationStateVocabulary,
        unavailableObservationSemantics,
        notApplicableObservationSemantics,
        retrievalLatencyRuntimeState,
        verdictVocabulary,
        errorVector,
        aggregateResult,
        aggregationPrecedence,
        determinismRequirement,
        provenanceRequirement,
        resultProvenanceFormat,
        diagnosticsIsolation,
      ])
        rule.section: rule.toMap(),
    },
    'dimensions': <Object?>[
      for (final dimension in dimensions) dimension.toMap(),
    ],
    'policy_snapshot': policySnapshot.toMap(),
    'diagnostic_non_policy_sources': diagnosticNonPolicySources,
    'retrieval_latency_unavailable_reason': retrievalLatencyUnavailableReason,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EvaluationContract &&
          other.identity == identity &&
          other.profile == profile &&
          other.observationStateVocabulary == observationStateVocabulary &&
          other.unavailableObservationSemantics ==
              unavailableObservationSemantics &&
          other.notApplicableObservationSemantics ==
              notApplicableObservationSemantics &&
          other.retrievalLatencyRuntimeState == retrievalLatencyRuntimeState &&
          other.verdictVocabulary == verdictVocabulary &&
          other.errorVector == errorVector &&
          other.aggregateResult == aggregateResult &&
          other.aggregationPrecedence == aggregationPrecedence &&
          other.determinismRequirement == determinismRequirement &&
          other.provenanceRequirement == provenanceRequirement &&
          other.resultProvenanceFormat == resultProvenanceFormat &&
          other.diagnosticsIsolation == diagnosticsIsolation &&
          _dimensionListEq(other.dimensions, dimensions) &&
          other.policySnapshot == policySnapshot &&
          _stringListEq(
            other.diagnosticNonPolicySources,
            diagnosticNonPolicySources,
          );

  @override
  int get hashCode => Object.hash(
    identity,
    profile,
    observationStateVocabulary,
    unavailableObservationSemantics,
    notApplicableObservationSemantics,
    retrievalLatencyRuntimeState,
    verdictVocabulary,
    errorVector,
    aggregateResult,
    aggregationPrecedence,
    determinismRequirement,
    provenanceRequirement,
    resultProvenanceFormat,
    diagnosticsIsolation,
    Object.hashAll(dimensions),
    policySnapshot,
    Object.hashAll(diagnosticNonPolicySources),
  );

  // ---- Per-dimension construction ----

  static DimensionEvaluationContract _pitch() => _dimension(
    EvaluationDimension.pitch,
    'PitchObservations/PitchObservation -> PitchEvaluationInput',
  );

  static DimensionEvaluationContract _timing() => _dimension(
    EvaluationDimension.timing,
    'TimingObservations/TimingObservation -> TimingEvaluationInput',
  );

  static DimensionEvaluationContract _order() => _dimension(
    EvaluationDimension.order,
    'OrderObservations/OrderObservation -> OrderEvaluationInput',
  );

  static DimensionEvaluationContract _simultaneity() => _dimension(
    EvaluationDimension.simultaneity,
    'SimultaneityObservations/SimultaneityGroup -> '
    'SimultaneityEvaluationInput',
  );

  static DimensionEvaluationContract _ioi() => _dimension(
    EvaluationDimension.ioi,
    'IoiObservations/IoiEntry -> IoiEvaluationInput',
  );

  static DimensionEvaluationContract _retrievalLatency() => _dimension(
    EvaluationDimension.retrievalLatency,
    'RetrievalLatencyObservation -> RetrievalLatencyEvaluationInput',
  );

  static DimensionEvaluationContract _dimension(
    EvaluationDimension dimension,
    String inputIdentifier,
  ) {
    final String serial = _dimensionSerial(dimension);
    return DimensionEvaluationContract(
      dimension: dimension,
      applicability: <TargetMode, ContractRule>{
        for (final mode in TargetMode.values)
          mode: _applicabilityRule(dimension, mode),
      },
      input: _defined(
        '${serial}_input',
        'lib/midi/domain/evaluation_input.dart',
        inputIdentifier,
        'H2.8 passes the H2.7 observations through unchanged; the engine must '
            'consume them as supplied and must not re-derive them.',
      ),
      metric: _unresolved(
        '${serial}_metric',
        'No evaluation metric for this dimension is defined anywhere in the '
            'repository.',
      ),
      verdictVocabulary: _unresolved(
        '${serial}_verdict_vocabulary',
        'No verdict vocabulary exists in the repository for this dimension.',
      ),
      threshold: ContractRule(
        section: '${serial}_threshold',
        status: ContractRuleStatus.unresolved,
        unresolvedReason:
            'No threshold or tolerance value is defined in the repository; '
            'the committed EvaluationPolicySnapshot holds no value for this '
            'dimension.',
      ),
      boundary: _unresolved(
        '${serial}_boundary',
        'No inclusive/exclusive boundary rule (for example '
            'abs(delta) <= threshold) is defined in the repository for this '
            'dimension.',
      ),
      unavailableBehavior: _unresolved(
        '${serial}_unavailable_behavior',
        'No rule establishes what an enabled-but-unavailable dimension '
            'result should be.',
      ),
      notApplicableRepresentation: _unresolved(
        '${serial}_not_applicable_representation',
        'No result model exists, so no NOT_APPLICABLE result representation '
            'is defined.',
      ),
    );
  }

  static ContractRule _applicabilityRule(
    EvaluationDimension dimension,
    TargetMode mode,
  ) {
    final bool enabled = MvpDefaultEvaluationProfile.instance
        .isDimensionEnabled(mode, dimension);
    if (enabled) {
      return _defined(
        '${_dimensionSerial(dimension)}_applicability_${mode.name}',
        'lib/midi/domain/evaluation_input.dart',
        'MvpDefaultEvaluationProfile.enabledDimensions',
        'Locked MVP profile enables ${_dimensionSerial(dimension)} for '
            '${mode.name}.',
      );
    }
    return ContractRule(
      section: '${_dimensionSerial(dimension)}_applicability_${mode.name}',
      status: ContractRuleStatus.derived,
      provenance: const ContractSourceProvenance(
        sourceKind: 'repository_code',
        sourcePath: 'lib/midi/domain/evaluation_input.dart',
        sourceIdentifier:
            'MvpDefaultEvaluationProfile.enabledDimensions + '
            'EvaluationInputPreparer notApplicable mapping',
      ),
      note:
          'Mechanically follows from the locked profile: a dimension absent '
          'from enabledDimensions for ${mode.name} is projected as '
          'NOT_APPLICABLE by H2.8.',
    );
  }

  static ContractRule _defined(
    String section,
    String sourcePath,
    String sourceIdentifier,
    String note,
  ) => ContractRule(
    section: section,
    status: ContractRuleStatus.defined,
    provenance: ContractSourceProvenance(
      sourceKind: 'repository_code',
      sourcePath: sourcePath,
      sourceIdentifier: sourceIdentifier,
    ),
    note: note,
  );

  static ContractRule _unresolved(String section, String reason) =>
      ContractRule(
        section: section,
        status: ContractRuleStatus.unresolved,
        unresolvedReason: reason,
      );
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

bool _modeRuleMapEq(
  Map<TargetMode, ContractRule> a,
  Map<TargetMode, ContractRule> b,
) {
  if (a.length != b.length) {
    return false;
  }
  for (final mode in TargetMode.values) {
    if (a[mode] != b[mode]) {
      return false;
    }
  }
  return true;
}

int _modeRuleMapHash(Map<TargetMode, ContractRule> map) {
  var hash = 0;
  for (final mode in TargetMode.values) {
    hash = Object.hash(hash, mode, map[mode]);
  }
  return hash;
}

bool _dimensionListEq(
  List<DimensionEvaluationContract> a,
  List<DimensionEvaluationContract> b,
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
