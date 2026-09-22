import '../../midi/domain/evaluation_result.dart';
import '../domain/attempt.dart';
import '../domain/exercise_instance.dart';
import '../domain/practice_clock.dart';
import '../domain/practice_interaction.dart';
import '../domain/practice_item.dart';

/// Orchestrates the lifecycle of one bounded Practice Interaction.
///
/// Responsibilities (RT-001..RT-024 - the Practice Runtime contract):
///
/// * owns the interaction/execution-session 1:1 relationship (PR-015),
/// * owns the Attempt state machine (RT-009..RT-011) exactly as defined,
/// * assigns only deterministic, caller/content-derived identities -
///   never random, never wall-clock (RT-003/RT-020),
/// * stamps practice-lifecycle timestamps from the injected [PracticeClock]
///   (RT-004/RT-012) - MIDI `app_monotonic_ts_ms` is never promoted to
///   practice lifecycle time,
/// * takes an already-produced [EvaluationResult] on
///   [completeAttempt] - it NEVER owns the evaluation engine, the evaluation
///   input, raw MIDI, CoreMIDI, or grading (RT-008).
///
/// The runtime keeps an internally evolving record and exposes immutable
/// [PracticeInteraction] / [PracticeItem] / [Attempt] snapshots via getters.
final class PracticeRuntime {
  PracticeRuntime({required this.clock});

  /// The only sanctioned source of practice-lifecycle timestamps.
  final PracticeClock clock;

  PracticeInteraction? _interaction;
  final Map<String, PracticeItem> _itemsById = <String, PracticeItem>{};
  final Map<String, Attempt> _attemptsById = <String, Attempt>{};
  int _attemptOrdinal = 0;

  /// The current interaction, or null before one is created/after it ends.
  PracticeInteraction? get currentInteraction => _interaction;

  bool get hasOpenInteraction =>
      _interaction != null && _interaction!.endedAt == null;

  /// Deterministic evaluation-flow-result view of the current interaction.
  List<PracticeItem> get currentItems =>
      List<PracticeItem>.unmodifiable(_interaction?.items ?? const []);

  /// Creates a new practice interaction owning exactly one execution session.
  ///
  /// [interactionId] must be deterministic and caller-supplied. The execution
  /// session id is derived from it, preserving the PR-015 1:1 cross-reference.
  PracticeInteraction createInteraction({
    required String interactionId,
    required List<ExerciseInstance> exercises,
  }) {
    if (hasOpenInteraction) {
      throw StateError(
          'PracticeRuntime: a practice interaction is already open.');
    }
    if (interactionId.isEmpty) {
      throw const FormatException(
          'PracticeRuntime: interactionId must not be empty.');
    }
    if (exercises.isEmpty) {
      throw const FormatException(
          'PracticeRuntime: an interaction needs at least one exercise.');
    }
    final now = clock.now();
    final session = ExecutionSession(
      id: 'es-$interactionId',
      practiceInteractionId: interactionId,
    );
    final items = <PracticeItem>[
      for (var i = 0; i < exercises.length; i++)
        PracticeItem(
          id: '$interactionId-item-$i',
          exerciseInstance: exercises[i],
        ),
    ];
    final interaction = PracticeInteraction(
      id: interactionId,
      executionSession: session,
      items: items,
      startedAt: now,
    );
    _interaction = interaction;
    _itemsById.clear();
    for (final item in items) {
      _itemsById[item.id] = item;
    }
    _attemptsById.clear();
    _attemptOrdinal = 0;
    return interaction;
  }

  // -------------------------------------------------------------------------
  // Attempt lifecycle
  // -------------------------------------------------------------------------

  /// Arms a new attempt against [itemId]. The attempt starts in `armed`.
  Attempt armAttempt({required String itemId}) {
    _requireOpen();
    final item = _itemFor(itemId);
    _attemptOrdinal += 1;
    final attemptId = '${item.id}-attempt-$_attemptOrdinal';
    final attempt = Attempt(
      id: attemptId,
      practiceItemId: item.id,
      state: AttemptState.armed,
    );
    _storeAttempt(attempt);
    return attempt;
  }

  /// `armed -> active`: records [PracticeClock] now as startedAt.
  Attempt activateAttempt(String attemptId) {
    final attempt = _requireAttempt(attemptId);
    _requireLegal(attempt, AttemptState.active);
    final now = clock.now();
    final updated = attempt.copyWith(state: AttemptState.active, startedAt: now);
    _storeAttempt(updated);
    return updated;
  }

  /// `active -> paused`.
  Attempt pauseAttempt(String attemptId) {
    final attempt = _requireAttempt(attemptId);
    _requireLegal(attempt, AttemptState.paused);
    final updated = attempt.copyWith(state: AttemptState.paused);
    _storeAttempt(updated);
    return updated;
  }

  /// `paused -> active`.
  Attempt resumeAttempt(String attemptId) {
    final attempt = _requireAttempt(attemptId);
    _requireLegal(attempt, AttemptState.active);
    final updated = attempt.copyWith(state: AttemptState.active);
    _storeAttempt(updated);
    return updated;
  }

  /// `active -> completed` (or `paused -> completed`).
  ///
  /// Attaches the [result] that was produced by the frozen evaluation pipeline;
  /// the runtime itself never grades (RT-008).
  Attempt completeAttempt({
    required String attemptId,
    required EvaluationResult result,
  }) {
    final attempt = _requireAttempt(attemptId);
    _requireLegal(attempt, AttemptState.completed);
    final now = clock.now();
    final updated = attempt.copyWith(
      state: AttemptState.completed,
      endedAt: now,
      evaluationResult: result,
    );
    _storeAttempt(updated);
    return updated;
  }

  /// `active -> abandoned`; an armed attempt may also be abandoned
  /// (`armed -> abandoned`) without ever starting.
  Attempt abandonAttempt(String attemptId) {
    final attempt = _requireAttempt(attemptId);
    _requireLegal(attempt, AttemptState.abandoned);
    final now = clock.now();
    final updated = attempt.copyWith(state: AttemptState.abandoned, endedAt: now);
    _storeAttempt(updated);
    return updated;
  }

  /// `active -> invalidated`; an armed attempt may also be invalidated
  /// (`armed -> invalidated`).
  Attempt invalidateAttempt(String attemptId) {
    final attempt = _requireAttempt(attemptId);
    _requireLegal(attempt, AttemptState.invalidated);
    final now = clock.now();
    final updated =
        attempt.copyWith(state: AttemptState.invalidated, endedAt: now);
    _storeAttempt(updated);
    return updated;
  }

  // -------------------------------------------------------------------------
  // Interaction end
  // -------------------------------------------------------------------------

  /// Ends the open interaction with [reason], stamping endedAt from the clock.
  PracticeInteraction endInteraction({required PracticeInteractionEndReason reason}) {
    _requireOpen();
    final now = clock.now();
    _interaction = _interaction!.copyWith(endedAt: now, endReason: reason);
    return _interaction!;
  }

  // -------------------------------------------------------------------------
  // Internal helpers
  // -------------------------------------------------------------------------

  void _requireOpen() {
    if (!hasOpenInteraction) {
      throw StateError('PracticeRuntime: no open practice interaction.');
    }
  }

  PracticeItem _itemFor(String itemId) {
    final item = _itemsById[itemId] ?? _findItemById(itemId);
    if (item == null) {
      throw StateError('PracticeRuntime: unknown practice item "$itemId".');
    }
    return item;
  }

  PracticeItem? _findItemById(String itemId) {
    for (final item in (_interaction?.items ?? const <PracticeItem>[])) {
      if (item.id == itemId) {
        return item;
      }
    }
    return null;
  }

  Attempt _requireAttempt(String attemptId) {
    final attempt = _attemptsById[attemptId];
    if (attempt == null) {
      throw StateError('PracticeRuntime: unknown attempt "$attemptId".');
    }
    return attempt;
  }

  void _requireLegal(Attempt attempt, AttemptState next) {
    if (!AttemptLifecycle.canTransition(attempt.state, next)) {
      throw StateError(
          'PracticeRuntime: illegal attempt transition '
          '${attempt.state.name} -> ${next.name}.');
    }
  }

  /// Records [attempt] into its item and rebuilds the interaction snapshot.
  void _storeAttempt(Attempt attempt) {
    _attemptsById[attempt.id] = attempt;
    final item = _itemFor(attempt.practiceItemId);
    final attempts = <Attempt>[];
    var replaced = false;
    for (final existing in item.attempts) {
      if (existing.id == attempt.id) {
        attempts.add(attempt);
        replaced = true;
      } else {
        attempts.add(existing);
      }
    }
    if (!replaced) {
      attempts.add(attempt);
    }
    final updatedItem = item.copyWith(attempts: attempts);
    _itemsById[item.id] = updatedItem;
    final updatedItems = <PracticeItem>[];
    var replacedItem = false;
    for (final existing in _interaction!.items) {
      if (existing.id == updatedItem.id) {
        updatedItems.add(updatedItem);
        replacedItem = true;
      } else {
        updatedItems.add(existing);
      }
    }
    if (!replacedItem) {
      updatedItems.add(updatedItem);
    }
    _interaction = _interaction!.copyWith(items: updatedItems);
  }
}