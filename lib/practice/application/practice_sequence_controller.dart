import 'package:flutter/foundation.dart';

import '../domain/practice_exercise.dart';

/// Immutable stage snapshot of the Practice Sequence controller.
///
/// Preserves the architecture's distinction between teach-step completion,
/// exercise completion, and sequence completion (§12). Exercise completion
/// here is session-scoped: once an exercise meets its condition it stays
/// marked complete for the duration of this lesson session (sticky), and it is
/// never rolled back by a retry.
final class PracticeSequenceSnapshot {
  PracticeSequenceSnapshot({
    required this.sequence,
    required this.currentIndex,
    required Set<int> completedOrders,
  }) : completedOrders = Set<int>.unmodifiable(completedOrders) {
    if (currentIndex < 0 || currentIndex >= sequence.exercises.length) {
      throw RangeError.range(
          currentIndex, 0, sequence.exercises.length - 1, 'currentIndex');
    }
    final validOrders = <int>{for (final e in sequence.exercises) e.order};
    if (!completedOrders.every(validOrders.contains)) {
      throw ArgumentError(
          'completedOrders must reference existing exercise orders.');
    }
  }

  /// The sequence being executed (belongs to exactly one lesson).
  final PracticeSequence sequence;

  /// Index of the exercise the learner is on.
  final int currentIndex;

  /// The 1-based orders of exercises completed this session (sticky).
  final Set<int> completedOrders;

  /// Number of exercises in the sequence.
  int get totalExercises => sequence.exercises.length;

  /// The exercise currently presented to the learner.
  PracticeExercise get currentExercise => sequence.exercises[currentIndex];

  /// Whether the current exercise is already completed this session.
  bool get isCurrentExerciseCompleted =>
      completedOrders.contains(currentExercise.order);

  /// Whether there is a later exercise to advance to.
  bool get isOnLastExercise => currentIndex == totalExercises - 1;

  /// Next becomes available only AFTER the current exercise is completed
  /// (mission: 'next only after completion; no accidental skipping'). It is
  /// completion-gated, never time-gated.
  bool get canAdvance => isCurrentExerciseCompleted && !isOnLastExercise;

  /// Number of completed exercises.
  int get completedCount => completedOrders.length;

  /// Whether every exercise in the sequence has been completed this session.
  ///
  /// A completed sequence is the precondition for the existing Lesson
  /// Progress / Continue flow; it is a structural fact, not a mastery claim.
  bool get sequenceComplete => completedCount == totalExercises;

  /// Completed / total, in [0, 1].
  double get progress => completedCount / totalExercises;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeSequenceSnapshot &&
          other.sequence == sequence &&
          other.currentIndex == currentIndex &&
          setEquals(other.completedOrders, completedOrders);

  @override
  int get hashCode =>
      Object.hash(sequence, currentIndex, Object.hashAllUnordered(completedOrders));

  @override
  String toString() => 'PracticeSequenceSnapshot('
      'exercise ${currentIndex + 1} of $totalExercises, '
      '$completedCount of $totalExercises complete)';
}

/// Owns the ordered navigation and exercise-completion facts of one Lesson's
/// Practice Sequence.
///
/// Kept deliberately separate from [PracticeRuntime]: the runtime executes a
/// single interaction; the sequence controller owns which exercise is live,
/// which have been completed, and when the sequence is done. It carries no
/// scheduler, no mastery, and no scoring.
class PracticeSequenceController extends ValueNotifier<PracticeSequenceSnapshot> {
  PracticeSequenceController({required PracticeSequence sequence})
      : super(PracticeSequenceSnapshot(
          sequence: sequence,
          currentIndex: 0,
          completedOrders: const <int>{}));

  /// Marks the current exercise completed for this session.
  ///
  /// Idempotent and sticky: once completed, it stays completed - retrying the
  /// same exercise later never un-completes it.
  void completeCurrentExercise() {
    final snapshot = value;
    if (snapshot.isCurrentExerciseCompleted) {
      return;
    }
    value = PracticeSequenceSnapshot(
      sequence: snapshot.sequence,
      currentIndex: snapshot.currentIndex,
      completedOrders: {...snapshot.completedOrders, snapshot.currentExercise.order},
    );
  }

  /// Advances to the next exercise when the current one is completed.
  ///
  /// A no-op without a completed current exercise (never skip an incomplete
  /// exercise) and a no-op on the last exercise (nothing follows). Order is
  /// deterministic: index + 1, never random.
  void advanceExercise() {
    final snapshot = value;
    if (!snapshot.isCurrentExerciseCompleted || snapshot.isOnLastExercise) {
      return;
    }
    value = PracticeSequenceSnapshot(
      sequence: snapshot.sequence,
      currentIndex: snapshot.currentIndex + 1,
      completedOrders: snapshot.completedOrders,
    );
  }
}