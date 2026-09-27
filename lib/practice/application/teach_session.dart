import 'package:flutter/foundation.dart';

import 'teach_step.dart';

/// Immutable snapshot of the Teach stage: the authored steps, the currently
/// shown step, and the steps the learner advanced past this session.
///
/// Teach-step completion is transient and session-scoped: never persisted,
/// never scheduled, and never mastery / evaluation / practice completion
/// (architecture §5, §12). A step is only ever completed by advancing past it,
/// so future steps can never appear completed.
final class TeachSessionSnapshot {
  TeachSessionSnapshot({
    required List<TeachStep> steps,
    required this.currentIndex,
    required Set<int> completedOrders,
    required this.teachComplete,
  })  : steps = List<TeachStep>.unmodifiable(steps),
        completedOrders = Set<int>.unmodifiable(completedOrders);

  final List<TeachStep> steps;

  /// 0-based index of the step currently shown.
  final int currentIndex;

  /// 1-based orders of the steps the learner advanced past this session.
  final Set<int> completedOrders;

  /// Reached only when the learner advances past the final step.
  final bool teachComplete;

  int get totalSteps => steps.length;

  TeachStep get currentStep => steps[currentIndex];

  bool get canGoPrevious => currentIndex > 0;

  /// True always (learner-authored advance) unless Teach is already complete.
  bool get canAdvance => !teachComplete;

  bool get isOnLastStep => currentIndex == totalSteps - 1;

  bool get currentStepShowsKeyboard => currentStep.showsKeyboard;

  int get completedCount => completedOrders.length;

  /// Teach progress: completed steps over total; 1.0 once Teach is complete.
  double get progress => teachComplete ? 1.0 : completedCount / totalSteps;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TeachSessionSnapshot &&
          other.currentIndex == currentIndex &&
          other.teachComplete == teachComplete &&
          listEquals(other.steps, steps) &&
          setEquals(other.completedOrders, completedOrders);

  @override
  int get hashCode =>
      Object.hash(completedCount, currentIndex, teachComplete);

  @override
  String toString() =>
      'TeachSessionSnapshot(step ${currentIndex + 1}/$totalSteps '
      'completed=$completedCount complete=$teachComplete)';
}

/// Session-scoped Teach wizard state (architecture §5).
///
/// Owns ordered progression: orderedSteps, currentIndex, per-reached-step
/// completion, canGoPrevious / canAdvance, and teachComplete. Mirrors the
/// repository's ValueNotifier snapshot style (see [PracticeSessionController]).
/// Lives exactly as long as the Teach stage and is disposed with it; it is
/// never persisted and never touches evaluation, mastery, or the scheduler.
class TeachSessionController extends ValueNotifier<TeachSessionSnapshot> {
  TeachSessionController({required List<TeachStep> steps})
      : super(TeachSessionSnapshot(
          steps: steps,
          currentIndex: 0,
          completedOrders: const <int>{},
          teachComplete: false,
        ));

  /// Marks the current step complete for this session and moves forward;
  /// advancing past the final step marks Teach complete (and nothing else).
  ///
  /// Completing after [TeachSessionSnapshot.teachComplete] is a no-op.
  void advance() {
    final snapshot = value;
    if (snapshot.teachComplete) {
      return;
    }
    final completed = <int>{
      ...snapshot.completedOrders,
      snapshot.currentStep.order,
    };
    final onLast = snapshot.isOnLastStep;
    value = TeachSessionSnapshot(
      steps: snapshot.steps,
      currentIndex: onLast ? snapshot.currentIndex : snapshot.currentIndex + 1,
      completedOrders: completed,
      teachComplete: onLast,
    );
  }

  /// Moves back one step when possible. Completed steps stay completed for the
  /// session; moving back never presents future steps as completed.
  void goPrevious() {
    final snapshot = value;
    if (!snapshot.canGoPrevious || snapshot.teachComplete) {
      return;
    }
    value = TeachSessionSnapshot(
      steps: snapshot.steps,
      currentIndex: snapshot.currentIndex - 1,
      completedOrders: snapshot.completedOrders,
      teachComplete: false,
    );
  }
}