import '../domain/evaluation_dimension_observations.dart';
import '../domain/evaluation_input.dart';
import '../domain/expected_musical_target.dart';

/// Deterministic preparation of canonical Evaluation Inputs for the locked
/// MVP Evaluation Profile.
///
/// H2.8 plays the middle role of the pipeline:
///
/// ```text
/// H2.7 Dimension Observations
///        -> H2.8 Evaluation Input Preparation (this layer)
///        -> canonical Evaluation Input
///        -> H2.9 Evaluation Engine
/// ```
///
/// It selects/packages policy inputs and answers "what should the Evaluation
/// Engine inspect?" It does NOT answer "did the learner succeed?". H2.8 never
/// re-parses raw MIDI, never re-normalizes, and never re-runs structural
/// alignment: the supplied [EvaluationDimensionObservations] are consumed as
/// immutable facts and projected unchanged into the canonical input.
///
/// No threshold is applied and no verdict is produced anywhere in this layer.
final class EvaluationInputPreparer {
  const EvaluationInputPreparer();

  /// Deterministic preparation algorithm version.
  static const String algorithmVersion = '1';

  /// Projects one H2.7 observation set for the locked MVP profile.
  ///
  /// Every dimension is present in the output. A dimension the profile does
  /// not evaluate for [EvaluationDimensionObservations.mode] is marked
  /// [EvaluationDimensionState.notApplicable]; an enabled dimension whose
  /// observations are absent is marked [EvaluationDimensionState.enabled] with
  /// [DataAvailability.unavailable] (never downgraded to not-applicable).
  EvaluationInput prepare({
    required EvaluationDimensionObservations observations,
    MvpDefaultEvaluationProfile profile = MvpDefaultEvaluationProfile.instance,
  }) {
    final mode = observations.mode;

    return EvaluationInput(
      evaluationProfileId: MvpDefaultEvaluationProfile.profileId,
      evaluationProfileVersion: MvpDefaultEvaluationProfile.contractVersion,
      targetId: observations.targetId,
      sessionId: observations.sessionId,
      mode: mode,
      alignmentAlgorithmVersion: observations.alignmentAlgorithmVersion,
      observationExtractionAlgorithmVersion:
          observations.extractionAlgorithmVersion,
      preparationAlgorithmVersion: algorithmVersion,
      pitch: PitchEvaluationInput(
        dimensionState: _stateFor(mode, EvaluationDimension.pitch, profile),
        dataAvailability: _availabilityFor(observations.pitch.availability),
        observations: observations.pitch.observations,
      ),
      timing: TimingEvaluationInput(
        dimensionState: _stateFor(mode, EvaluationDimension.timing, profile),
        dataAvailability: _availabilityFor(observations.timing.availability),
        observations: observations.timing.observations,
      ),
      order: OrderEvaluationInput(
        dimensionState: _stateFor(mode, EvaluationDimension.order, profile),
        dataAvailability: _availabilityFor(observations.order.availability),
        order: observations.order.order,
      ),
      simultaneity: SimultaneityEvaluationInput(
        dimensionState:
            _stateFor(mode, EvaluationDimension.simultaneity, profile),
        dataAvailability:
            _availabilityFor(observations.simultaneity.availability),
        groups: observations.simultaneity.groups,
      ),
      ioi: IoiEvaluationInput(
        dimensionState: _stateFor(mode, EvaluationDimension.ioi, profile),
        dataAvailability: _availabilityFor(observations.ioi.availability),
        expected: observations.ioi.expected,
        observed: observations.ioi.observed,
      ),
      retrievalLatency: RetrievalLatencyEvaluationInput(
        dimensionState: EvaluationDimensionState.enabled,
        dataAvailability:
            _availabilityFor(observations.retrievalLatency.availability),
        observation: observations.retrievalLatency,
      ),
      policy: EvaluationPolicySnapshot(
        profileId: MvpDefaultEvaluationProfile.profileId,
        profileVersion: MvpDefaultEvaluationProfile.contractVersion,
      ),
      ignoredNonNoteEventRefs: observations.ignoredNonNoteEventRefs,
      ignoredIntegrityAnomalyEventRefs:
          observations.ignoredIntegrityAnomalyEventRefs,
      ignoredOtherSessionEventRefs: observations.ignoredOtherSessionEventRefs,
    );
  }

  /// Passes the H2.7 observation-level availability through to data
  /// availability. NOT_APPLICABLE observations carry no data, hence
  /// [DataAvailability.unavailable].
  static DataAvailability _availabilityFor(ObservationAvailability availability) =>
      switch (availability) {
        ObservationAvailability.available => DataAvailability.available,
        ObservationAvailability.unavailable => DataAvailability.unavailable,
        ObservationAvailability.notApplicable => DataAvailability.unavailable,
      };

  /// Profile applicability of [dimension] for [mode]: ENABLED when the profile
  /// evaluates the dimension for the mode, otherwise NOT_APPLICABLE. The MVP
  /// profile definition is total over both target modes; it never resolves a
  /// dimension to the unavailable state.
  static EvaluationDimensionState _stateFor(TargetMode mode,
          EvaluationDimension dimension, MvpDefaultEvaluationProfile profile) =>
      profile.isDimensionEnabled(mode, dimension)
          ? EvaluationDimensionState.enabled
          : EvaluationDimensionState.notApplicable;
}