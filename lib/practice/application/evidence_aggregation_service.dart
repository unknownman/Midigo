import '../../midi/domain/evaluation_input.dart'
    show DataAvailability, EvaluationDimensionState;
import '../../midi/domain/evaluation_result.dart'
    show EvaluatedResult, NotEnoughPerformanceResult;
import '../domain/attempt.dart';
import '../domain/evidence.dart';
import '../domain/practice_clock.dart';
import '../domain/practice_interaction.dart';
import '../domain/practice_item.dart';
import 'evaluation_flow.dart';
import 'evidence_store.dart';

/// What one evaluated attempt contributed, and - when it contributed nothing -
/// exactly which contract rule made it produce nothing.
final class EvidenceRecordOutcome {
  /// The contributions now stored for this attempt and its stream, in
  /// deterministic order. Empty when the attempt produced no evidence.
  final List<EvidenceContribution> contributions;

  /// The contract-established reason no evidence was produced, or null when
  /// evidence was produced.
  final EvidenceOmission? omission;

  EvidenceRecordOutcome({
    required List<EvidenceContribution> contributions,
    this.omission,
  }) : contributions =
            List<EvidenceContribution>.unmodifiable(contributions) {
    if (contributions.isNotEmpty && omission != null) {
      throw const FormatException(
          'EvidenceRecordOutcome: an outcome is either a record or an '
          'omission, never both.');
    }
  }

  static EvidenceRecordOutcome recorded(
          List<EvidenceContribution> contributions) =>
      EvidenceRecordOutcome(contributions: contributions);

  static EvidenceRecordOutcome omitted(EvidenceOmission omission) =>
      EvidenceRecordOutcome(
        contributions: const <EvidenceContribution>[],
        omission: omission,
      );

  bool get producedEvidence => contributions.isNotEmpty;

  @override
  String toString() => producedEvidence
      ? 'EvidenceRecordOutcome(${contributions.length} contributions)'
      : 'EvidenceRecordOutcome(none: ${omission!.name})';
}

/// Turns evaluated practice attempts into immutable Evidence Contributions.
///
/// This is the only place where an Attempt becomes Evidence. It never grades,
/// never reinterprets a result, never touches lesson stars, mastery, the Review
/// Scheduler, or the evaluation pipeline: it only projects what the frozen
/// evaluation already decided into explicit, immutable contributions.
abstract interface class EvidenceAggregator {
  /// The aggregated Evidence State, i.e. the whole read model of the evidence
  /// this service has recorded (EVG-009/EVG-010). It is derived purely from
  /// stored values, so it can never drift from them.
  EvidenceState get state;

  /// Records the evidence contributed by one completed, evaluated [attempt].
  ///
  /// [interaction] must be the Practice Interaction that owns the attempt
  /// (EVG-006/RT-013); its lifecycle timestamps are the only legal operand of
  /// the independence rule (EVG-019). [evaluation] carries the provenance of
  /// the frozen result the attempt already carries.
  ///
  /// Idempotent: recording the same attempt again returns the contribution
  /// already stored and never duplicates it (EVG-003).
  EvidenceRecordOutcome recordAttempt({
    required Attempt attempt,
    required PracticeInteraction interaction,
    required EvaluationFlowResult evaluation,
  });

  /// Reports that a Practice Interaction has ended.
  ///
  /// A contribution is born while its interaction is normally still open, so
  /// EVG-019's `earlierInteraction.ended_at` operand arrives later. Reporting it
  /// here is what lets the independence rule work on real evidence; until then
  /// the interaction counts as still open and its contributions stay dependent
  /// with each other (EVG-019). Stored evidence is never rewritten (EVG-021).
  void recordInteractionEnd(PracticeInteraction interaction);
}

/// The Evidence v1.1 aggregation service.
final class PracticeEvidenceAggregator implements EvidenceAggregator {
  PracticeEvidenceAggregator({
    required this.store,
    required this.clock,
  });

  final EvidenceStore store;

  /// The only sanctioned source of the contribution creation time. It never
  /// becomes part of the evidence identity (EVG-020).
  final PracticeClock clock;

  @override
  EvidenceState get state => store.state;

  @override
  void recordInteractionEnd(PracticeInteraction interaction) =>
      store.recordInteractionEnd(interaction);

  @override
  EvidenceRecordOutcome recordAttempt({
    required Attempt attempt,
    required PracticeInteraction interaction,
    required EvaluationFlowResult evaluation,
  }) {
    // EVG-003: only a completed attempt that actually reached the evaluation
    // boundary can contribute. Abandoned / invalidated / still-open attempts
    // never do, and no evidence is inferred from partial MIDI input.
    final result = attempt.evaluationResult;
    if (attempt.state != AttemptState.completed || result == null) {
      return EvidenceRecordOutcome.omitted(EvidenceOmission.attemptNotCompleted);
    }

    // EVG-006/RT-013: an attempt belongs to exactly one Practice Item inside
    // exactly one Practice Interaction.
    final PracticeItem? item = _owningItem(interaction, attempt);
    if (item == null) {
      return EvidenceRecordOutcome.omitted(
          EvidenceOmission.attemptNotOwnedByInteraction);
    }

    // EVG-012: a not-enough-performance attempt is ungraded. It is not zero
    // stars, produces no contribution, and must not be recorded as a negative
    // signal of any kind.
    if (result is NotEnoughPerformanceResult) {
      return EvidenceRecordOutcome.omitted(EvidenceOmission.notEnoughPerformance);
    }
    if (result is! EvaluatedResult) {
      return EvidenceRecordOutcome.omitted(EvidenceOmission.notEnoughPerformance);
    }

    // EVG-011: a stream exists for a dimension that is ENABLED for the target
    // mode AND produced graded data. Retrieval Latency is enabled but has no
    // runtime performance anchor, so it receives no contribution.
    final graded = result.dimensions
        .where((dimension) =>
            dimension.state == EvaluationDimensionState.enabled &&
            dimension.dataAvailability == DataAvailability.available)
        .toList(growable: false);
    if (graded.isEmpty) {
      return EvidenceRecordOutcome.omitted(EvidenceOmission.noGradedDimension);
    }

    final createdAt = clock.now();
    final recorded = <EvidenceContribution>[];
    for (final dimension in graded) {
      final identity = EvidenceIdentity(
        targetId: item.targetId,
        dimension: dimension.dimension,
      );
      final contribution = EvidenceContribution(
        identity: identity,
        kind: EvidenceContributionKind.practiceAttempt,
        provenance: EvidenceProvenance(
          targetId: item.targetId,
          mode: evaluation.mode,
          captureSessionId: evaluation.sessionId,
          evaluationProfileId: evaluation.provenance.evaluationProfileId,
          evaluationProfileVersion:
              evaluation.provenance.evaluationProfileVersion,
          alignmentAlgorithmVersion:
              evaluation.provenance.alignmentAlgorithmVersion,
          observationExtractionAlgorithmVersion:
              evaluation.provenance.observationExtractionAlgorithmVersion,
          preparationAlgorithmVersion:
              evaluation.provenance.preparationAlgorithmVersion,
          evaluationFlowAlgorithmVersion:
              evaluation.provenance.flowAlgorithmVersion,
          practiceInteractionId: interaction.id,
          executionSessionId: interaction.executionSession.id,
          practiceItemId: item.id,
          attemptId: attempt.id,
          practiceInteractionStartedAt: interaction.startedAt,
        ),
        // EVG-013: 0..5 stars is the observed per-attempt quality. A zero-star
        // evaluated attempt is genuine evidence, never an absence of evidence.
        stars: result.stars,
        dimensionState: dimension.state,
        dataAvailability: dimension.dataAvailability,
        createdAt: createdAt,
      );
      recorded.add(store.add(contribution));
    }

    // An attempt evaluated after its interaction already closed still supplies
    // EVG-019's operand for every other contribution of that interaction.
    if (interaction.endedAt != null) {
      store.recordInteractionEnd(interaction);
    }

    return EvidenceRecordOutcome.recorded(recorded);
  }

  /// The Practice Item of [interaction] that owns [attempt], or null.
  static PracticeItem? _owningItem(
    PracticeInteraction interaction,
    Attempt attempt,
  ) {
    for (final item in interaction.items) {
      if (item.id != attempt.practiceItemId) {
        continue;
      }
      for (final owned in item.attempts) {
        if (owned.id == attempt.id) {
          return item;
        }
      }
    }
    return null;
  }
}
