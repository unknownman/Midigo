import 'evaluation_dimension_observations.dart';
import 'expected_musical_target.dart';

/// The six evaluation dimensions recognised by the locked MVP Evaluation
/// Profile.
///
/// This is a vocabulary for profile applicability only - it carries no
/// observation data and expresses no judgment.
enum EvaluationDimension {
  pitch,
  timing,
  order,
  simultaneity,
  ioi,
  retrievalLatency;
}

/// Profile-level applicability of one evaluation dimension for the current
/// target mode.
///
/// * [enabled] - the profile evaluates the dimension for this mode. Whether
///   usable data exists is expressed separately by [DataAvailability].
/// * [notApplicable] - the profile does not evaluate the dimension for this
///   mode.
/// * [unavailable] - reserved vocabulary for "the profile relationship for
///   this dimension could not be established". The MVP profile always resolves
///   to [enabled] or [notApplicable]; it never emits this value.
enum EvaluationDimensionState {
  enabled,
  notApplicable,
  unavailable;

  String get serialName => switch (this) {
        EvaluationDimensionState.enabled => 'ENABLED',
        EvaluationDimensionState.notApplicable => 'NOT_APPLICABLE',
        EvaluationDimensionState.unavailable => 'UNAVAILABLE',
      };
}

/// Whether the required observation data exists for a dimension.
///
/// Independent from [EvaluationDimensionState]: an [enabled] dimension may
/// still report [unavailable] data (for example Retrieval Latency, for which
/// no frozen model provides a performance anchor). A dimension that is
/// [notApplicable] to the mode reports nothing to observe.
enum DataAvailability {
  available,
  unavailable;

  String get serialName => switch (this) {
        DataAvailability.available => 'AVAILABLE',
        DataAvailability.unavailable => 'UNAVAILABLE',
      };
}

/// The locked, single MVP Evaluation Profile definition.
///
/// This expresses ONLY which dimensions are evaluated for which target mode:
///
/// ```text
/// BLOCK     Pitch, Timing, Simultaneity, Retrieval Latency, order/IOI N/A
/// ARPEGGIO  Pitch, Order, Timing, IOI, Retrieval Latency, simultaneity N/A
/// ```
///
/// H2.8 represents the profile explicitly and selects/packages policy inputs.
/// It does NOT apply any policy: no threshold is executed, no verdict is
/// produced. H2.9 consumes the resulting [EvaluationInput].
final class MvpDefaultEvaluationProfile {
  /// Locked identity of the single MVP Evaluation Profile.
  static const String profileId = 'mvp_default_v1';

  /// Evaluation Contract version actually implemented - the project's
  /// established, locked contract identifier (Evaluation Contract v1.1).
  static const String contractVersion = 'v1.1';

  /// The single executable instance of the locked profile.
  static const MvpDefaultEvaluationProfile instance =
      MvpDefaultEvaluationProfile._();

  const MvpDefaultEvaluationProfile._();

  static const Set<EvaluationDimension> _blockEnabled = <EvaluationDimension>{
    EvaluationDimension.pitch,
    EvaluationDimension.timing,
    EvaluationDimension.simultaneity,
    EvaluationDimension.retrievalLatency,
  };

  static const Set<EvaluationDimension> _arpeggioEnabled =
      <EvaluationDimension>{
    EvaluationDimension.pitch,
    EvaluationDimension.timing,
    EvaluationDimension.order,
    EvaluationDimension.ioi,
    EvaluationDimension.retrievalLatency,
  };

  /// Dimensions the profile evaluates for the given target mode.
  Set<EvaluationDimension> enabledDimensions(TargetMode mode) =>
      switch (mode) {
        TargetMode.block => _blockEnabled,
        TargetMode.arpeggio => _arpeggioEnabled,
      };

  bool isDimensionEnabled(TargetMode mode, EvaluationDimension dimension) =>
      enabledDimensions(mode).contains(dimension);
}

/// Immutable, auditable snapshot of the Evaluation Profile's policy metadata.
///
/// Policy metadata is what the future Evaluation Engine will consume (for
/// example a contracted tolerance in milliseconds). H2.8 carries it into the
/// canonical input verbatim as a snapshot. It never executes it, and it never
/// invents a value: the locked contract defines no executable policy value yet,
/// so every slot is null (absent).
///
/// ```text
/// policy value != evaluation result
/// ```
final class EvaluationPolicySnapshot {
  final String profileId;
  final String profileVersion;

  /// Contract-defined policy value in the unit the future Evaluation Engine
  /// would consume. Null = the locked contract defines none.
  final int? pitchMs;
  final int? timingMs;
  final int? orderMs;
  final int? simultaneityMs;
  final int? ioiMs;
  final int? retrievalLatencyMs;

  const EvaluationPolicySnapshot({
    required this.profileId,
    required this.profileVersion,
    this.pitchMs,
    this.timingMs,
    this.orderMs,
    this.simultaneityMs,
    this.ioiMs,
    this.retrievalLatencyMs,
  });

  /// False while the locked contract defines no policy value. Always false for
  /// the MVP profile.
  bool get hasAnyDefinedPolicies =>
      pitchMs != null ||
      timingMs != null ||
      orderMs != null ||
      simultaneityMs != null ||
      ioiMs != null ||
      retrievalLatencyMs != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EvaluationPolicySnapshot &&
          other.profileId == profileId &&
          other.profileVersion == profileVersion &&
          other.pitchMs == pitchMs &&
          other.timingMs == timingMs &&
          other.orderMs == orderMs &&
          other.simultaneityMs == simultaneityMs &&
          other.ioiMs == ioiMs &&
          other.retrievalLatencyMs == retrievalLatencyMs;

  @override
  int get hashCode => Object.hash(profileId, profileVersion, pitchMs, timingMs,
      orderMs, simultaneityMs, ioiMs, retrievalLatencyMs);

  Map<String, Object?> toMap() => <String, Object?>{
        'profile_id': profileId,
        'profile_version': profileVersion,
        'pitch_ms': pitchMs,
        'timing_ms': timingMs,
        'order_ms': orderMs,
        'simultaneity_ms': simultaneityMs,
        'ioi_ms': ioiMs,
        'retrieval_latency_ms': retrievalLatencyMs,
      };
}

/// Base of the six per-dimension canonical inputs.
///
/// Every dimension is represented explicitly - none is silently omitted. The
/// [dimensionState] expresses profile applicability for the current mode; the
/// [dataAvailability] expresses whether usable observation data exists. The
/// two fields are deliberately independent.
sealed class EvaluationDimensionInput {
  final EvaluationDimensionState dimensionState;
  final DataAvailability dataAvailability;

  const EvaluationDimensionInput({
    required this.dimensionState,
    required this.dataAvailability,
  });

  Map<String, Object?> toMap();
}

/// Canonical Pitch input.
///
/// H2.7 [PitchObservation]s are passed through without reinterpretation: no
/// pitch match/accuracy/error, no enharmonic normalisation, no tolerance.
final class PitchEvaluationInput extends EvaluationDimensionInput {
  final List<PitchObservation> observations;

  PitchEvaluationInput({
    required super.dimensionState,
    required super.dataAvailability,
    required List<PitchObservation> observations,
  }) : observations = List<PitchObservation>.unmodifiable(observations) {
    if (dataAvailability == DataAvailability.available &&
        observations.isEmpty) {
      throw const FormatException(
          'PitchEvaluationInput: available data must expose observations.');
    }
    if (dataAvailability == DataAvailability.unavailable &&
        observations.isNotEmpty) {
      throw const FormatException(
          'PitchEvaluationInput: unavailable data must not carry observations.');
    }
    if (dimensionState == EvaluationDimensionState.notApplicable &&
        observations.isNotEmpty) {
      throw const FormatException(
          'PitchEvaluationInput: a not-applicable dimension must expose no '
          'observations.');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PitchEvaluationInput &&
          other.dimensionState == dimensionState &&
          other.dataAvailability == dataAvailability &&
          _pitchObservationListEq(other.observations, observations);

  @override
  int get hashCode => Object.hash(dimensionState, dataAvailability,
      Object.hashAll(observations));

  @override
  Map<String, Object?> toMap() => <String, Object?>{
        'dimension_state': dimensionState.serialName,
        'data_availability': dataAvailability.serialName,
        'observations':
            observations.map((o) => o.toMap()).toList(growable: false),
      };
}

/// Canonical Timing input.
///
/// Raw expected onset offsets and observed onset timestamps are preserved;
/// nothing is classified as early/late and no timing verdict is produced.
final class TimingEvaluationInput extends EvaluationDimensionInput {
  final List<TimingObservation> observations;

  TimingEvaluationInput({
    required super.dimensionState,
    required super.dataAvailability,
    required List<TimingObservation> observations,
  }) : observations = List<TimingObservation>.unmodifiable(observations) {
    if (dataAvailability == DataAvailability.available &&
        observations.isEmpty) {
      throw const FormatException(
          'TimingEvaluationInput: available data must expose observations.');
    }
    if (dataAvailability == DataAvailability.unavailable &&
        observations.isNotEmpty) {
      throw const FormatException(
          'TimingEvaluationInput: unavailable data must not carry observations.');
    }
    if (dimensionState == EvaluationDimensionState.notApplicable &&
        observations.isNotEmpty) {
      throw const FormatException(
          'TimingEvaluationInput: a not-applicable dimension must expose no '
          'observations.');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimingEvaluationInput &&
          other.dimensionState == dimensionState &&
          other.dataAvailability == dataAvailability &&
          _timingObservationListEq(other.observations, observations);

  @override
  int get hashCode => Object.hash(dimensionState, dataAvailability,
      Object.hashAll(observations));

  @override
  Map<String, Object?> toMap() => <String, Object?>{
        'dimension_state': dimensionState.serialName,
        'data_availability': dataAvailability.serialName,
        'observations':
            observations.map((o) => o.toMap()).toList(growable: false),
      };
}

/// Canonical Order input.
///
/// Exposes the H2.7 [OrderObservation] unchanged: expected sequence, observed
/// sequence exactly as captured (never re-sorted), and structurally associated
/// pairs. No sequence-correctness calculation and no order score.
final class OrderEvaluationInput extends EvaluationDimensionInput {
  final OrderObservation order;

  OrderEvaluationInput({
    required super.dimensionState,
    required super.dataAvailability,
    required this.order,
  }) {
    if (dimensionState == EvaluationDimensionState.notApplicable &&
        (order.expectedOrder.isNotEmpty ||
            order.observedOrder.isNotEmpty ||
            order.associatedPairs.isNotEmpty)) {
      throw const FormatException(
          'OrderEvaluationInput: a not-applicable dimension must expose an '
          'empty order.');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderEvaluationInput &&
          other.dimensionState == dimensionState &&
          other.dataAvailability == dataAvailability &&
          other.order == order;

  @override
  int get hashCode => Object.hash(dimensionState, dataAvailability, order);

  @override
  Map<String, Object?> toMap() => <String, Object?>{
        'dimension_state': dimensionState.serialName,
        'data_availability': dataAvailability.serialName,
        'order': order.toMap(),
      };
}

/// Canonical IOI input.
///
/// Signed/raw expected and observed inter-onset-interval entries are passed
/// through uncoupled. No IOI deviation, tempo deviation, or speed verdict.
final class IoiEvaluationInput extends EvaluationDimensionInput {
  final List<IoiEntry> expected;
  final List<IoiEntry> observed;

  IoiEvaluationInput({
    required super.dimensionState,
    required super.dataAvailability,
    required List<IoiEntry> expected,
    required List<IoiEntry> observed,
  })  : expected = List<IoiEntry>.unmodifiable(expected),
        observed = List<IoiEntry>.unmodifiable(observed) {
    if (dataAvailability == DataAvailability.available &&
        expected.isEmpty &&
        observed.isEmpty) {
      throw const FormatException(
          'IoiEvaluationInput: available data must expose at least one entry.');
    }
    if (dataAvailability == DataAvailability.unavailable &&
        (expected.isNotEmpty || observed.isNotEmpty)) {
      throw const FormatException(
          'IoiEvaluationInput: unavailable data must not carry entries.');
    }
    if (dimensionState == EvaluationDimensionState.notApplicable &&
        (expected.isNotEmpty || observed.isNotEmpty)) {
      throw const FormatException(
          'IoiEvaluationInput: a not-applicable dimension must expose no '
          'entries.');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IoiEvaluationInput &&
          other.dimensionState == dimensionState &&
          other.dataAvailability == dataAvailability &&
          _ioiEntryListEq(other.expected, expected) &&
          _ioiEntryListEq(other.observed, observed);

  @override
  int get hashCode => Object.hash(dimensionState, dataAvailability,
      Object.hashAll(expected), Object.hashAll(observed));

  @override
  Map<String, Object?> toMap() => <String, Object?>{
        'dimension_state': dimensionState.serialName,
        'data_availability': dataAvailability.serialName,
        'expected': expected.map((e) => e.toMap()).toList(growable: false),
        'observed': observed.map((e) => e.toMap()).toList(growable: false),
      };
}

/// Canonical Simultaneity input.
///
/// Raw group membership, associated observed onsets, and the observed span are
/// exposed unchanged. No `simultaneous` / `not_simultaneous` classification and
/// no threshold application. The observed span stays a raw quantity.
final class SimultaneityEvaluationInput extends EvaluationDimensionInput {
  final List<SimultaneityGroup> groups;

  SimultaneityEvaluationInput({
    required super.dimensionState,
    required super.dataAvailability,
    required List<SimultaneityGroup> groups,
  }) : groups = List<SimultaneityGroup>.unmodifiable(groups) {
    if (dataAvailability == DataAvailability.available && groups.isEmpty) {
      throw const FormatException(
          'SimultaneityEvaluationInput: available data must expose groups.');
    }
    if (dataAvailability == DataAvailability.unavailable && groups.isNotEmpty) {
      throw const FormatException(
          'SimultaneityEvaluationInput: unavailable data must not carry groups.');
    }
    if (dimensionState == EvaluationDimensionState.notApplicable &&
        groups.isNotEmpty) {
      throw const FormatException(
          'SimultaneityEvaluationInput: a not-applicable dimension must expose '
          'no groups.');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SimultaneityEvaluationInput &&
          other.dimensionState == dimensionState &&
          other.dataAvailability == dataAvailability &&
          _simultaneityGroupListEq(other.groups, groups);

  @override
  int get hashCode => Object.hash(
      dimensionState, dataAvailability, Object.hashAll(groups));

  @override
  Map<String, Object?> toMap() => <String, Object?>{
        'dimension_state': dimensionState.serialName,
        'data_availability': dataAvailability.serialName,
        'groups': groups.map((g) => g.toMap()).toList(growable: false),
      };
}

/// Canonical Retrieval Latency input.
///
/// The MVP profile enables Retrieval Latency; H2.7 reports no performance
/// anchor, so [dimensionState] is [EvaluationDimensionState.enabled] with
/// [DataAvailability.unavailable]. The H2.7 observation is passed through
/// unchanged - nothing is fabricated and no anchor substitutes (session start,
/// first event, target creation, capture start, wall clock) are used.
final class RetrievalLatencyEvaluationInput extends EvaluationDimensionInput {
  final RetrievalLatencyObservation observation;

  RetrievalLatencyEvaluationInput({
    required super.dimensionState,
    required super.dataAvailability,
    required this.observation,
  }) {
    if (dimensionState == EvaluationDimensionState.notApplicable) {
      throw const FormatException(
          'RetrievalLatencyEvaluationInput: the MVP profile always enables '
          'Retrieval Latency; a not-applicable state is invalid.');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RetrievalLatencyEvaluationInput &&
          other.dimensionState == dimensionState &&
          other.dataAvailability == dataAvailability &&
          other.observation == observation;

  @override
  int get hashCode =>
      Object.hash(dimensionState, dataAvailability, observation);

  @override
  Map<String, Object?> toMap() => <String, Object?>{
        'dimension_state': dimensionState.serialName,
        'data_availability': dataAvailability.serialName,
        'observation': observation.toMap(),
      };
}

/// Canonical, immutable Evaluation Input: exactly the information available to
/// the future Evaluation Engine for each applicable dimension, selected and
/// packaged for the locked [MvpDefaultEvaluationProfile].
///
/// H2.8 is a projection of H2.7 observations plus the profile. It answers
/// "what should the Evaluation Engine inspect?" and never answers "did the
/// learner succeed?". No EvaluationResult, no verdict, no score, no threshold,
/// no tolerance, and no Error Vector lives in this model.
final class EvaluationInput {
  final String evaluationProfileId;
  final String evaluationProfileVersion;
  final String targetId;
  final String sessionId;
  final TargetMode mode;

  /// Provenance of the producing layers.
  final String alignmentAlgorithmVersion;
  final String observationExtractionAlgorithmVersion;
  final String preparationAlgorithmVersion;

  final PitchEvaluationInput pitch;
  final TimingEvaluationInput timing;
  final OrderEvaluationInput order;
  final SimultaneityEvaluationInput simultaneity;
  final IoiEvaluationInput ioi;
  final RetrievalLatencyEvaluationInput retrievalLatency;

  final EvaluationPolicySnapshot policy;

  /// Provenance passthrough of the H2.6 alignment's ignored references.
  final List<int> ignoredNonNoteEventRefs;
  final List<int> ignoredIntegrityAnomalyEventRefs;
  final List<int> ignoredOtherSessionEventRefs;

  EvaluationInput({
    required this.evaluationProfileId,
    required this.evaluationProfileVersion,
    required this.targetId,
    required this.sessionId,
    required this.mode,
    required this.alignmentAlgorithmVersion,
    required this.observationExtractionAlgorithmVersion,
    required this.preparationAlgorithmVersion,
    required this.pitch,
    required this.timing,
    required this.order,
    required this.simultaneity,
    required this.ioi,
    required this.retrievalLatency,
    required this.policy,
    required List<int> ignoredNonNoteEventRefs,
    required List<int> ignoredIntegrityAnomalyEventRefs,
    required List<int> ignoredOtherSessionEventRefs,
  })  : ignoredNonNoteEventRefs =
            List<int>.unmodifiable(ignoredNonNoteEventRefs),
        ignoredIntegrityAnomalyEventRefs =
            List<int>.unmodifiable(ignoredIntegrityAnomalyEventRefs),
        ignoredOtherSessionEventRefs =
            List<int>.unmodifiable(ignoredOtherSessionEventRefs);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EvaluationInput &&
          other.evaluationProfileId == evaluationProfileId &&
          other.evaluationProfileVersion == evaluationProfileVersion &&
          other.targetId == targetId &&
          other.sessionId == sessionId &&
          other.mode == mode &&
          other.alignmentAlgorithmVersion == alignmentAlgorithmVersion &&
          other.observationExtractionAlgorithmVersion ==
              observationExtractionAlgorithmVersion &&
          other.preparationAlgorithmVersion == preparationAlgorithmVersion &&
          other.pitch == pitch &&
          other.timing == timing &&
          other.order == order &&
          other.simultaneity == simultaneity &&
          other.ioi == ioi &&
          other.retrievalLatency == retrievalLatency &&
          other.policy == policy &&
          _intListEq(other.ignoredNonNoteEventRefs, ignoredNonNoteEventRefs) &&
          _intListEq(other.ignoredIntegrityAnomalyEventRefs,
              ignoredIntegrityAnomalyEventRefs) &&
          _intListEq(
              other.ignoredOtherSessionEventRefs, ignoredOtherSessionEventRefs);

  @override
  int get hashCode => Object.hash(evaluationProfileId, evaluationProfileVersion,
      targetId, sessionId, mode, alignmentAlgorithmVersion,
      observationExtractionAlgorithmVersion, preparationAlgorithmVersion,
      pitch, timing, order, simultaneity, ioi, retrievalLatency, policy,
      Object.hashAll(ignoredNonNoteEventRefs),
      Object.hashAll(ignoredIntegrityAnomalyEventRefs),
      Object.hashAll(ignoredOtherSessionEventRefs));

  Map<String, Object?> toMap() => <String, Object?>{
        'evaluation_profile_id': evaluationProfileId,
        'evaluation_profile_version': evaluationProfileVersion,
        'target_id': targetId,
        'session_id': sessionId,
        'mode': mode.name,
        'alignment_algorithm_version': alignmentAlgorithmVersion,
        'observation_extraction_algorithm_version':
            observationExtractionAlgorithmVersion,
        'preparation_algorithm_version': preparationAlgorithmVersion,
        'pitch': pitch.toMap(),
        'timing': timing.toMap(),
        'order': order.toMap(),
        'simultaneity': simultaneity.toMap(),
        'ioi': ioi.toMap(),
        'retrieval_latency': retrievalLatency.toMap(),
        'policy': policy.toMap(),
        'ignored_non_note_event_refs': ignoredNonNoteEventRefs,
        'ignored_integrity_anomaly_event_refs': ignoredIntegrityAnomalyEventRefs,
        'ignored_other_session_event_refs': ignoredOtherSessionEventRefs,
      };
}

bool _pitchObservationListEq(
    List<PitchObservation> a, List<PitchObservation> b) {
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

bool _timingObservationListEq(
    List<TimingObservation> a, List<TimingObservation> b) {
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

bool _simultaneityGroupListEq(
    List<SimultaneityGroup> a, List<SimultaneityGroup> b) {
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