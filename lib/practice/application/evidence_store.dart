import '../domain/evidence.dart';
import '../domain/practice_interaction.dart';

/// Application-level storage and read model for aggregated Evidence.
///
/// The interface is intentionally the only thing callers see: no file paths,
/// no JSON shapes, no internal indices. A future persistent implementation can
/// satisfy it without any caller change; Evidence v1.1 defines no persistence
/// requirement, so the only implementation in this phase is in memory.
abstract interface class EvidenceStore {
  /// The aggregated Evidence State derived from every stored contribution and
  /// every known Practice Interaction window.
  EvidenceState get state;

  /// Stores [contribution] and returns the contribution that is now stored.
  ///
  /// Creation is idempotent by contribution identity (EVG-003, one contribution
  /// per attempt + stream). When a contribution with the same identity is
  /// already stored, the existing one is returned unchanged: evidence is
  /// immutable and is never overwritten or mutated in place (EVG-021), so a
  /// replayed or conflicting re-record can neither duplicate nor alter stored
  /// evidence.
  EvidenceContribution add(EvidenceContribution contribution);

  /// Records that [interaction] has ended, supplying the second operand of the
  /// EVG-019 independence gap.
  ///
  /// A contribution is born while its Practice Interaction is normally still
  /// open, so the interaction's end is reported separately and kept as its own
  /// immutable window rather than being back-written into stored evidence
  /// (EVG-021). Recording the same end twice is idempotent and never rewrites a
  /// known window.
  void recordInteractionEnd(PracticeInteraction interaction);

  /// The known window of [practiceInteractionId], or null while Evidence has
  /// not been told that the interaction ended.
  EvidenceInteractionWindow? interactionWindow(String practiceInteractionId);

  /// The stored contribution with [id], or null.
  EvidenceContribution? contributionById(String id);

  /// The stream for [identity], or null when nothing was contributed to it.
  ///
  /// A defined-but-empty stream is expressible: EVG-011 keeps the Retrieval
  /// Latency stream defined while it receives no contributions, so absence of a
  /// stream is absence of contributions, never a fabricated dimension.
  EvidenceStream? streamFor(EvidenceIdentity identity);

  /// Every stored contribution in deterministic order.
  List<EvidenceContribution> get contributions;
}

/// The single Evidence v1.1 implementation: an in-memory store.
///
/// Aggregation is a pure function of the stored contributions and the recorded
/// interaction windows ([EvidenceAggregation.aggregate]), recomputed on read.
/// Nothing is cached incrementally, so the state can never drift from the stored
/// values and the same stored values always rebuild the same state - including
/// the same deterministic group identities (EVG-009/EVG-010/EVG-020).
final class InMemoryEvidenceStore implements EvidenceStore {
  final Map<String, EvidenceContribution> _byId =
      <String, EvidenceContribution>{};
  final Map<String, EvidenceInteractionWindow> _windows =
      <String, EvidenceInteractionWindow>{};

  /// Creates a store pre-loaded with [contributions] and [interactionWindows],
  /// which is how a restored store looks (duplicate identities collapse to one
  /// value, exactly as [add] and [recordInteractionEnd] would do).
  InMemoryEvidenceStore({
    Iterable<EvidenceContribution> contributions =
        const <EvidenceContribution>[],
    Iterable<EvidenceInteractionWindow> interactionWindows =
        const <EvidenceInteractionWindow>[],
  }) {
    for (final window in interactionWindows) {
      if (window.isOpen) {
        throw const FormatException(
            'InMemoryEvidenceStore: a stored interaction window must be closed.');
      }
      _windows.putIfAbsent(
        window.practiceInteractionId,
        () => window,
      );
    }
    for (final contribution in contributions) {
      add(contribution);
    }
  }

  @override
  EvidenceState get state => EvidenceAggregation.aggregate(
        _byId.values,
        windows: _windows,
      );

  @override
  EvidenceContribution add(EvidenceContribution contribution) {
    final existing = _byId[contribution.id];
    if (existing != null) {
      return existing;
    }
    _byId[contribution.id] = contribution;
    return contribution;
  }

  @override
  void recordInteractionEnd(PracticeInteraction interaction) {
    final endedAt = interaction.endedAt;
    if (endedAt == null) {
      throw StateError(
        'recordInteractionEnd: interaction ${interaction.id} is still open; '
        'Practice Runtime must end it first.',
      );
    }
    _windows.putIfAbsent(
      interaction.id,
      () => EvidenceInteractionWindow(
        practiceInteractionId: interaction.id,
        startedAt: interaction.startedAt,
        endedAt: endedAt,
      ),
    );
  }

  @override
  EvidenceInteractionWindow? interactionWindow(String practiceInteractionId) =>
      _windows[practiceInteractionId];

  @override
  EvidenceContribution? contributionById(String id) => _byId[id];

  @override
  EvidenceStream? streamFor(EvidenceIdentity identity) =>
      state.streamFor(identity);

  @override
  List<EvidenceContribution> get contributions => state.contributions;
}
