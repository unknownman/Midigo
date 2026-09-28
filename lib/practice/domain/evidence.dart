import '../../midi/domain/evaluation_input.dart'
    show DataAvailability, EvaluationDimension, EvaluationDimensionState;
import '../../midi/domain/expected_musical_target.dart' show TargetMode;

/// The materialized, executable form of Evidence Aggregation Contract v1.1.
///
/// Only the decisions that this layer actually implements are represented here.
/// Every constant is traceable to
/// `docs/evidence-aggregation-contract-v1.1-decision-matrix.md`:
///
/// ```text
/// EVG-002  identity  = (targetId, evaluationDimension), content derived
/// EVG-004  the only contribution kind is practiceAttempt
/// EVG-007  dependency classification rule
/// EVG-008  independence threshold = 15 minutes, boundary INCLUSIVE
/// EVG-009  groups are delimited by independence boundaries
/// EVG-010  group identity is derived from stream identity + segmentation
/// EVG-011  a stream exists per (targetId, dimension) that is ENABLED and
///          produced graded data; Retrieval Latency is ENABLED but UNAVAILABLE
///          (NO_RUNTIME_PERFORMANCE_ANCHOR) and therefore receives nothing
/// EVG-012  NOT_ENOUGH_PERFORMANCE yields no contribution
/// EVG-013  an EVALUATED result with 0 stars IS evidence
/// EVG-020  identity is derived from content - never random, never clock
/// EVG-021  contributions and groups are immutable
/// EVG-022  no mastery in evidence
/// EVG-023  no scheduler vocabulary in evidence
/// EVG-024  recorded stars are per-attempt evidence, not lesson stars
/// ```
///
/// What is deliberately absent: mastery, confidence, retention, decay, review
/// eligibility, intervals, and any statistical model (EVG-016/017/018 are
/// RESOLVED-DEFERRED, EVG-022/023 forbid the rest).
abstract final class EvidenceAggregationContract {
  static const String contractName = 'Evidence Aggregation Contract';
  static const String contractVersion = 'v1.1';

  /// EVG-008: the one numeric Evidence policy of v1.1.
  static const Duration independenceThreshold = Duration(minutes: 15);

  /// EVG-008: the boundary is inclusive - a gap of exactly
  /// [independenceThreshold] is INDEPENDENT.
  static const bool independenceBoundaryInclusive = true;

  /// Separator used by every derived evidence identifier. Rejected inside
  /// identity components so two different identities can never collapse onto
  /// the same string.
  static const String idSeparator = ':';
}

/// Whether two contributions may be treated as fully independent evidence.
///
/// EVG-007: this is a *statistical-independence* statement about how closely
/// spaced two performances were. It is NOT a quality statement: `dependent`
/// does not mean correct, incorrect, mastered, or retained, and it is never
/// exposed to the learner.
enum EvidenceDependency { dependent, independent }

/// The one contribution kind defined by Evidence v1.1 (EVG-004).
///
/// `ACQUISITION` / `RETRIEVAL` / `RETENTION` / `DEGRADATION` / `LAPSE` are not
/// contribution kinds in v1.1: the first two have no locked mechanism and the
/// temporal kinds are Scheduler/Mastery concerns (EVG-016/017/018 are deferred).
/// Review practice, when it produces an evaluated attempt, uses this same kind:
/// there is no Review-specific evidence kind.
enum EvidenceContributionKind { practiceAttempt }

/// Why an evaluated attempt produced no Evidence Contribution.
///
/// Every value is a contract-established non-producing case. None of them is a
/// quality signal, and none of them creates a negative contribution.
enum EvidenceOmission {
  /// EVG-003: only a completed Attempt that reached the evaluation boundary can
  /// contribute (armed/active/paused/abandoned/invalidated never can).
  attemptNotCompleted,

  /// EVG-006/RT-013: an Attempt belongs to exactly one Practice Item inside
  /// exactly one Practice Interaction. An attempt that is not owned by the
  /// supplied interaction cannot be attributed.
  attemptNotOwnedByInteraction,

  /// EVG-012: a NOT_ENOUGH_PERFORMANCE result is an ungraded attempt. It is
  /// not zero stars and it never enters evidence as zero stars.
  notEnoughPerformance,

  /// EVG-011: the attempt produced no dimension that both is ENABLED for the
  /// target mode and carries graded data. Retrieval Latency is exactly this
  /// case (ENABLED, UNAVAILABLE, NO_RUNTIME_PERFORMANCE_ANCHOR).
  noGradedDimension,
}

/// Deterministic identity of one Evidence Stream (EVG-002).
///
/// The identity is the tuple `(targetId, evaluationDimension)` and nothing
/// else: it is derived from content, so it is stable across process restarts
/// and identical for every attempt that concerns the same target and
/// dimension. It is NOT derived from an attempt, a timestamp, a random value,
/// a hash of anything nondeterministic, or a counter.
///
/// `targetId` is [ExpectedMusicalTarget.targetId] and the dimension is the
/// frozen `EvaluationDimension` vocabulary reused 1:1 (EVG-011) - no second
/// dimension taxonomy exists here.
final class EvidenceIdentity {
  final String targetId;
  final EvaluationDimension dimension;

  EvidenceIdentity({
    required this.targetId,
    required this.dimension,
  }) {
    if (targetId.isEmpty) {
      throw const FormatException(
          'EvidenceIdentity: targetId must not be empty.');
    }
    _rejectSeparator(targetId, 'targetId');
  }

  /// Deterministic stream identifier derived from `(targetId, dimension)`.
  String get streamId =>
      'evidence${EvidenceAggregationContract.idSeparator}$targetId'
      '${EvidenceAggregationContract.idSeparator}${dimension.name}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EvidenceIdentity &&
          other.targetId == targetId &&
          other.dimension == dimension;

  @override
  int get hashCode => Object.hash(targetId, dimension);

  @override
  String toString() => 'EvidenceIdentity($streamId)';
}

/// Immutable provenance of one contribution (EVG-014, RT-014).
///
/// Carries exactly the vocabulary the contract requires, and nothing that
/// merely looks useful:
///
/// * the locked evaluation provenance already propagated by `EvaluationInput`
///   (target, MIDI capture session, mode, evaluation profile id/version and
///   the engine algorithm versions),
/// * the Practice Runtime provenance needed to answer "which attempt, which
///   interaction, which practice item, when" (EVG-006, RT-013),
/// * the Practice Interaction lifecycle timestamps, which are the only legal
///   operand of the independence gap (EVG-019). They are practice-domain time
///   and are never synthesized from MIDI capture `app_monotonic_ts_ms`.
///
/// No mastery, confidence, retention, difficulty, or scheduler interval field
/// exists (EVG-022/EVG-023).
final class EvidenceProvenance {
  final String targetId;
  final TargetMode mode;

  /// The MIDI capture session id the evaluated events came from, propagated
  /// from the frozen `EvaluationInput.sessionId`. It is NOT an Execution
  /// Session and NOT a Practice Interaction (RT-011/RT-012).
  final String captureSessionId;

  final String evaluationProfileId;
  final String evaluationProfileVersion;
  final String alignmentAlgorithmVersion;
  final String observationExtractionAlgorithmVersion;
  final String preparationAlgorithmVersion;
  final String evaluationFlowAlgorithmVersion;

  final String practiceInteractionId;
  final String executionSessionId;
  final String practiceItemId;
  final String attemptId;

  /// Practice-domain start of the owning Practice Interaction (RT-004). It is
  /// practice time and is never synthesized from MIDI capture
  /// `app_monotonic_ts_ms`, first-note time, or the wall clock.
  final DateTime practiceInteractionStartedAt;

  EvidenceProvenance({
    required this.targetId,
    required this.mode,
    required this.captureSessionId,
    required this.evaluationProfileId,
    required this.evaluationProfileVersion,
    required this.alignmentAlgorithmVersion,
    required this.observationExtractionAlgorithmVersion,
    required this.preparationAlgorithmVersion,
    required this.evaluationFlowAlgorithmVersion,
    required this.practiceInteractionId,
    required this.executionSessionId,
    required this.practiceItemId,
    required this.attemptId,
    required this.practiceInteractionStartedAt,
  }) {
    for (final (name, value) in <(String, String)>[
      ('targetId', targetId),
      ('captureSessionId', captureSessionId),
      ('evaluationProfileId', evaluationProfileId),
      ('evaluationProfileVersion', evaluationProfileVersion),
      ('alignmentAlgorithmVersion', alignmentAlgorithmVersion),
      ('observationExtractionAlgorithmVersion',
          observationExtractionAlgorithmVersion),
      ('preparationAlgorithmVersion', preparationAlgorithmVersion),
      ('evaluationFlowAlgorithmVersion', evaluationFlowAlgorithmVersion),
      ('practiceInteractionId', practiceInteractionId),
      ('executionSessionId', executionSessionId),
      ('practiceItemId', practiceItemId),
      ('attemptId', attemptId),
    ]) {
      if (value.isEmpty) {
        throw FormatException('EvidenceProvenance: $name must not be empty.');
      }
    }
    _rejectSeparator(attemptId, 'attemptId');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EvidenceProvenance &&
          other.targetId == targetId &&
          other.mode == mode &&
          other.captureSessionId == captureSessionId &&
          other.evaluationProfileId == evaluationProfileId &&
          other.evaluationProfileVersion == evaluationProfileVersion &&
          other.alignmentAlgorithmVersion == alignmentAlgorithmVersion &&
          other.observationExtractionAlgorithmVersion ==
              observationExtractionAlgorithmVersion &&
          other.preparationAlgorithmVersion == preparationAlgorithmVersion &&
          other.evaluationFlowAlgorithmVersion ==
              evaluationFlowAlgorithmVersion &&
          other.practiceInteractionId == practiceInteractionId &&
          other.executionSessionId == executionSessionId &&
          other.practiceItemId == practiceItemId &&
          other.attemptId == attemptId &&
          other.practiceInteractionStartedAt == practiceInteractionStartedAt;

  @override
  int get hashCode => Object.hash(
        targetId,
        mode,
        captureSessionId,
        evaluationProfileId,
        evaluationProfileVersion,
        alignmentAlgorithmVersion,
        observationExtractionAlgorithmVersion,
        preparationAlgorithmVersion,
        evaluationFlowAlgorithmVersion,
        practiceInteractionId,
        executionSessionId,
        practiceItemId,
        attemptId,
        practiceInteractionStartedAt,
      );

  @override
  String toString() =>
      'EvidenceProvenance($attemptId @ $practiceInteractionId: $targetId)';
}

/// One immutable learning signal contributed by one evaluated practice attempt
/// (EVG-003, EVG-021).
///
/// An Evidence Contribution is NOT an Attempt, NOT an EvaluationResult, NOT
/// mastery, and NOT a lesson star. [stars] is the per-attempt observed quality
/// recorded as evidence input (EVG-013/EVG-024): it never accumulates lesson
/// stars, never completes a lesson, and never changes evaluation.
final class EvidenceContribution {
  final EvidenceIdentity identity;
  final EvidenceContributionKind kind;
  final EvidenceProvenance provenance;

  /// Per-attempt observed quality, `0..5` (EVG-013). A zero-star evaluated
  /// attempt is genuine evidence: zero is a value, not an absence.
  final int stars;

  /// Profile applicability of the contributing dimension, carried verbatim
  /// from the frozen [DimensionResult] so the stream rule of EVG-011 stays
  /// auditable on the contribution itself.
  final EvaluationDimensionState dimensionState;

  /// Whether graded data existed for the contributing dimension, carried
  /// verbatim from the frozen [DimensionResult].
  final DataAvailability dataAvailability;

  /// Practice-clock time at which this contribution was recorded. It is
  /// provenance only: it is never part of [EvidenceIdentity].
  final DateTime createdAt;

  EvidenceContribution({
    required this.identity,
    required this.kind,
    required this.provenance,
    required this.stars,
    required this.dimensionState,
    required this.dataAvailability,
    required this.createdAt,
  }) {
    if (stars < 0 || stars > 5) {
      throw const FormatException(
          'EvidenceContribution: stars must be 0..5 (EVG-013).');
    }
    // EVG-003: the contribution belongs to the attempt it was derived from.
    if (provenance.attemptId.isEmpty) {
      throw const FormatException(
          'EvidenceContribution: provenance must name the contributing attempt.');
    }
  }

  /// Deterministic contribution identity (EVG-020), derived from content and
  /// therefore never supplied by a caller: the evidence stream
  /// `(targetId, dimension)` plus the contributing attempt. There is no random
  /// id, no timestamp and no counter, so the same attempt against the same
  /// stream always yields the same contribution identity - which is what makes
  /// evidence creation idempotent (one contribution per attempt + stream,
  /// EVG-003).
  String get id => EvidenceAggregation.contributionId(
        identity: identity,
        attemptId: provenance.attemptId,
      );

  /// Convenience: the id of the evidence stream this contribution belongs to.
  String get streamId => identity.streamId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EvidenceContribution &&
          other.id == id &&
          other.identity == identity &&
          other.kind == kind &&
          other.provenance == provenance &&
          other.stars == stars &&
          other.dimensionState == dimensionState &&
          other.dataAvailability == dataAvailability &&
          other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
        id,
        identity,
        kind,
        provenance,
        stars,
        dimensionState,
        dataAvailability,
        createdAt,
      );

  @override
  String toString() =>
      'EvidenceContribution($id: $kind, $stars stars)';
}

/// One deterministic unit of contributions that share an Evidence Identity and
/// are not separated by an independence boundary (EVG-009).
final class EvidenceGroup {
  /// Deterministic, content-derived group identity (EVG-010): the stream
  /// identity plus the id of the group's anchor (first) contribution. No
  /// counter, no clock, no randomness.
  final String id;

  final EvidenceIdentity identity;
  final List<EvidenceContribution> contributions;

  EvidenceGroup({
    required this.id,
    required this.identity,
    required List<EvidenceContribution> contributions,
  }) : contributions = List<EvidenceContribution>.unmodifiable(contributions) {
    if (id.isEmpty) {
      throw const FormatException('EvidenceGroup: id must not be empty.');
    }
    for (final contribution in this.contributions) {
      if (contribution.identity != identity) {
        throw const FormatException(
            'EvidenceGroup: every contribution must share the group identity.');
      }
    }
  }

  int get length => contributions.length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EvidenceGroup &&
          other.id == id &&
          other.identity == identity &&
          _contributionListEq(other.contributions, contributions);

  @override
  int get hashCode => Object.hash(id, identity, Object.hashAll(contributions));

  @override
  String toString() => 'EvidenceGroup($id: $length contributions)';
}

/// All contributions of one Evidence Identity, segmented into groups by the
/// independence boundary (EVG-009/EVG-010).
final class EvidenceStream {
  final EvidenceIdentity identity;
  final List<EvidenceGroup> groups;

  EvidenceStream({
    required this.identity,
    required List<EvidenceGroup> groups,
  }) : groups = List<EvidenceGroup>.unmodifiable(groups) {
    for (final group in this.groups) {
      if (group.identity != identity) {
        throw const FormatException(
            'EvidenceStream: every group must share the stream identity.');
      }
    }
  }

  /// Every contribution of the stream in deterministic order.
  List<EvidenceContribution> get contributions =>
      List<EvidenceContribution>.unmodifiable(<EvidenceContribution>[
        for (final group in groups) ...group.contributions,
      ]);

  int get contributionCount => contributions.length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EvidenceStream &&
          other.identity == identity &&
          _groupListEq(other.groups, groups);

  @override
  int get hashCode => Object.hash(identity, Object.hashAll(groups));

  @override
  String toString() =>
      'EvidenceStream(${identity.streamId}: ${groups.length} groups, '
      '$contributionCount contributions)';
}

/// The lifecycle window of a Practice Interaction, as far as Evidence is
/// concerned (RT-004, EVG-019).
///
/// EVG-019 needs `laterInteraction.started_at - earlierInteraction.ended_at`.
/// A contribution can only capture the interaction *start* it observed, because
/// a contribution is born while the interaction is normally still open. The
/// end therefore arrives later, from the Practice Runtime, and is held here as
/// its own immutable value instead of being back-written into stored evidence
/// (EVG-021).
///
/// A window with `endedAt == null` means the interaction is still open: the
/// earlier operand of EVG-019 does not exist yet.
final class EvidenceInteractionWindow {
  final String practiceInteractionId;
  final DateTime startedAt;
  final DateTime? endedAt;

  bool get isOpen => endedAt == null;

  EvidenceInteractionWindow({
    required this.practiceInteractionId,
    required this.startedAt,
    this.endedAt,
  }) {
    if (practiceInteractionId.isEmpty) {
      throw const FormatException(
          'EvidenceInteractionWindow: practiceInteractionId must not be empty.');
    }
    final ended = endedAt;
    if (ended != null && ended.isBefore(startedAt)) {
      throw FormatException(
          'EvidenceInteractionWindow: endedAt must not precede startedAt '
          'for interaction $practiceInteractionId.',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EvidenceInteractionWindow &&
          other.practiceInteractionId == practiceInteractionId &&
          other.startedAt == startedAt &&
          other.endedAt == endedAt;

  @override
  int get hashCode => Object.hash(practiceInteractionId, startedAt, endedAt);

  @override
  String toString() => 'EvidenceInteractionWindow($practiceInteractionId, '
      'startedAt: $startedAt, endedAt: $endedAt)';
}

/// The aggregated Evidence State: the whole read model, derived purely from the
/// stored contributions and the known interaction windows (EVG-009/EVG-010).
final class EvidenceState {
  final List<EvidenceContribution> contributions;
  final List<EvidenceStream> streams;
  final List<EvidenceInteractionWindow> interactionWindows;

  EvidenceState({
    required List<EvidenceContribution> contributions,
    required List<EvidenceStream> streams,
    List<EvidenceInteractionWindow> interactionWindows =
        const <EvidenceInteractionWindow>[],
  })  : contributions = List<EvidenceContribution>.unmodifiable(contributions),
        streams = List<EvidenceStream>.unmodifiable(streams),
        interactionWindows =
            List<EvidenceInteractionWindow>.unmodifiable(interactionWindows);

  static final EvidenceState empty = EvidenceState(
    contributions: const <EvidenceContribution>[],
    streams: const <EvidenceStream>[],
  );

  EvidenceStream? streamFor(EvidenceIdentity identity) {
    for (final stream in streams) {
      if (stream.identity == identity) {
        return stream;
      }
    }
    return null;
  }

  EvidenceContribution? contributionById(String id) {
    for (final contribution in contributions) {
      if (contribution.id == id) {
        return contribution;
      }
    }
    return null;
  }

  /// The known window of a Practice Interaction, or null while Evidence has not
  /// been told that it ended (the interaction is treated as still open).
  EvidenceInteractionWindow? interactionWindow(String practiceInteractionId) {
    for (final window in interactionWindows) {
      if (window.practiceInteractionId == practiceInteractionId) {
        return window;
      }
    }
    return null;
  }

  /// All groups of the state, in deterministic stream order.
  List<EvidenceGroup> get groups => List<EvidenceGroup>.unmodifiable(
        <EvidenceGroup>[for (final stream in streams) ...stream.groups],
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EvidenceState &&
          _contributionListEq(other.contributions, contributions) &&
          _streamListEq(other.streams, streams) &&
          _windowListEq(other.interactionWindows, interactionWindows);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(contributions),
        Object.hashAll(streams),
        Object.hashAll(interactionWindows),
      );

  @override
  String toString() => 'EvidenceState(${contributions.length} contributions, '
      '${streams.length} streams)';
}

/// The whole aggregation semantics of Evidence v1.1: contribution derivation,
/// dependency classification, and deterministic grouping.
abstract final class EvidenceAggregation {
  /// Deterministic contribution identity for `(stream, attempt)` (EVG-003/020).
  static String contributionId({
    required EvidenceIdentity identity,
    required String attemptId,
  }) {
    if (attemptId.isEmpty) {
      throw const FormatException(
          'EvidenceAggregation: attemptId must not be empty.');
    }
    _rejectSeparator(attemptId, 'attemptId');
    return 'contribution${EvidenceAggregationContract.idSeparator}'
        '${identity.streamId}${EvidenceAggregationContract.idSeparator}'
        '$attemptId';
  }

  /// Whether the two Practice Interactions the contributions belong to are
  /// dependent evidence (EVG-007/008/019).
  ///
  /// ```text
  /// same Practice Interaction                     -> dependent
  /// earlier interaction still open               -> dependent
  /// different interactions, gap < 15:00          -> dependent
  /// different interactions, gap >= 15:00         -> independent
  /// ```
  ///
  /// The gap is `later.startedAt - earlier.endedAt` in practice-domain time
  /// (EVG-019). The threshold boundary is inclusive: a gap of exactly 15:00 is
  /// INDEPENDENT (EVG-008).
  static EvidenceDependency classify({
    required EvidenceInteractionWindow earlier,
    required EvidenceInteractionWindow later,
  }) {
    if (earlier.practiceInteractionId == later.practiceInteractionId) {
      return EvidenceDependency.dependent;
    }
    final gap = _gap(earlier: earlier, later: later);
    if (gap == null) {
      // An interaction that has not ended yet cannot establish a 15-minute
      // gap: EVG-019's operand does not exist yet, so the contributions stay
      // dependent rather than being assumed independent.
      return EvidenceDependency.dependent;
    }
    return gap < EvidenceAggregationContract.independenceThreshold
        ? EvidenceDependency.dependent
        : EvidenceDependency.independent;
  }

  /// The deterministic gap used by [classify], or null when the operand does
  /// not exist yet. Exposed for diagnostics and tests; it is a raw quantity,
  /// never a score.
  static Duration? independenceGap({
    required EvidenceInteractionWindow earlier,
    required EvidenceInteractionWindow later,
  }) {
    if (earlier.practiceInteractionId == later.practiceInteractionId) {
      return null;
    }
    return _gap(earlier: earlier, later: later);
  }

  /// The window a contribution is judged by: the window the Practice Runtime
  /// has reported, or the open window the contribution itself observed.
  static EvidenceInteractionWindow resolveWindow(
    EvidenceContribution contribution,
    Map<String, EvidenceInteractionWindow> windows,
  ) {
    return windows[contribution.provenance.practiceInteractionId] ??
        EvidenceInteractionWindow(
          practiceInteractionId:
              contribution.provenance.practiceInteractionId,
          startedAt: contribution.provenance.practiceInteractionStartedAt,
        );
  }

  /// Pure aggregation: contributions in, Evidence State out.
  ///
  /// Contributions are grouped per Evidence Identity, sorted deterministically
  /// by `(interaction start, attempt id, contribution id)`, and split into
  /// groups at every independence boundary (EVG-009). A contribution belongs to
  /// the current group only while it is dependent on that group's anchor
  /// contribution, so a group is a chain of dependent attempts and a new
  /// contribution can never bridge two otherwise independent stretches. The
  /// same set of contributions and windows always produces exactly the same
  /// state - there is no counter, no clock read and no global mutable state
  /// (EVG-020).
  static EvidenceState aggregate(
    Iterable<EvidenceContribution> contributions, {
    Map<String, EvidenceInteractionWindow> windows =
        const <String, EvidenceInteractionWindow>{},
  }) {
    final byStream = <String, List<EvidenceContribution>>{};
    final identities = <String, EvidenceIdentity>{};
    for (final contribution in contributions) {
      final streamId = contribution.streamId;
      identities[streamId] = contribution.identity;
      (byStream[streamId] ??= <EvidenceContribution>[]).add(contribution);
    }

    final streamIds = byStream.keys.toList()..sort();
    final streams = <EvidenceStream>[];
    final ordered = <EvidenceContribution>[];
    for (final streamId in streamIds) {
      final sorted = List<EvidenceContribution>.of(byStream[streamId]!)
        ..sort(_contributionOrder);
      final groups = <List<EvidenceContribution>>[];
      for (final contribution in sorted) {
        if (groups.isEmpty) {
          groups.add(<EvidenceContribution>[contribution]);
          continue;
        }
        final anchor = groups.last.first;
        final dependent = classify(
          earlier: resolveWindow(anchor, windows),
          later: resolveWindow(contribution, windows),
        ) == EvidenceDependency.dependent;
        if (dependent) {
          groups.last.add(contribution);
        } else {
          groups.add(<EvidenceContribution>[contribution]);
        }
      }
      final identity = identities[streamId]!;
      streams.add(
        EvidenceStream(
          identity: identity,
          groups: <EvidenceGroup>[
            for (final group in groups)
              EvidenceGroup(
                id: 'evidence-group${EvidenceAggregationContract.idSeparator}'
                    '$streamId${EvidenceAggregationContract.idSeparator}'
                    '${group.first.id}',
                identity: identity,
                contributions: group,
              ),
          ],
        ),
      );
      ordered.addAll(sorted);
    }

    final knownWindows = windows.values.toList()
      ..sort((a, b) => a.practiceInteractionId.compareTo(
            b.practiceInteractionId,
          ));

    return EvidenceState(
      contributions: ordered,
      streams: streams,
      interactionWindows: knownWindows,
    );
  }

  /// Deterministic intra-stream order: practice-interaction start, then
  /// attempt, then contribution identity. Timestamps come from the Practice
  /// Clock via the runtime, never from MIDI capture time (RT-012).
  static int _contributionOrder(
    EvidenceContribution a,
    EvidenceContribution b,
  ) {
    final byInteraction = a.provenance.practiceInteractionStartedAt
        .compareTo(b.provenance.practiceInteractionStartedAt);
    if (byInteraction != 0) {
      return byInteraction;
    }
    final byAttempt =
        a.provenance.attemptId.compareTo(b.provenance.attemptId);
    if (byAttempt != 0) {
      return byAttempt;
    }
    return a.id.compareTo(b.id);
  }

  static Duration? _gap({
    required EvidenceInteractionWindow earlier,
    required EvidenceInteractionWindow later,
  }) {
    final endedAt = earlier.endedAt;
    if (endedAt == null) {
      return null;
    }
    return later.startedAt.difference(endedAt);
  }
}

void _rejectSeparator(String value, String field) {
  if (value.contains(EvidenceAggregationContract.idSeparator)) {
    throw FormatException(
      'Evidence: $field must not contain the reserved identity separator '
      '"${EvidenceAggregationContract.idSeparator}".',
    );
  }
}

bool _contributionListEq(
  List<EvidenceContribution> a,
  List<EvidenceContribution> b,
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

bool _streamListEq(List<EvidenceStream> a, List<EvidenceStream> b) {
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

bool _windowListEq(
  List<EvidenceInteractionWindow> a,
  List<EvidenceInteractionWindow> b,
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

bool _groupListEq(List<EvidenceGroup> a, List<EvidenceGroup> b) {
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
