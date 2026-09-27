/// One learner-facing practice exercise inside a Lesson's Practice Sequence.
///
/// An exercise is a concrete, executable practice activity with one explicit
/// pedagogical objective (Learning Curriculum & Lesson Architecture v1.0 §3,
/// §7). For H2.8 each exercise maps exactly one frozen [targetId]; the current
/// runtime executes it as a single-target, fully-guided, evaluated practice
/// interaction (`PracticeSessionController -> PracticeRuntime ->
/// EvaluationFlowService`).
///
/// Pure curriculum value type: no MIDI transport types, no EvaluationResult,
/// no scheduler/mastery state, no wall-clock, and no random/UUID identity.
final class PracticeExercise {
  const PracticeExercise({
    required this.id,
    required this.order,
    required this.title,
    required this.targetId,
  }) : assert(order > 0, 'PracticeExercise: order must be >= 1.');

  /// Deterministic exercise identity (never random, never clock-derived),
  /// e.g. `<lesson-id>.exercise.01`.
  final String id;

  /// 1-based position within the Practice Sequence.
  final int order;

  /// Learner-facing exercise title (e.g. 'Guided Block Practice').
  final String title;

  /// The frozen target id this exercise executes (e.g. `major-c-rh-block`).
  ///
  /// By construction the exercise respects the lesson's hand/mode/target
  /// identity: an arpeggio exercise is never described as a block, and a
  /// both-unison exercise stays a paired-hand target, not alternating hands.
  final String targetId;

  /// EVALUATED stars on [targetId] required to COMPLETE this exercise
  /// (architecture §12): an evaluated attempt with stars >= this threshold
  /// completes the exercise; NEP and zero-star evaluated attempts are real
  /// attempts but never complete it. Not a mastery claim.
  static const int completionStarThreshold = 3;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeExercise &&
          other.id == id &&
          other.order == order &&
          other.title == title &&
          other.targetId == targetId;

  @override
  int get hashCode => Object.hash(id, order, title, targetId);

  @override
  String toString() => 'PracticeExercise($id: $targetId)';
}

/// The ordered, deterministic practice exercises of one Lesson.
///
/// The sequence belongs to exactly one [lessonId] (a Lesson, never a
/// scheduler). It is immutable, ordered, deterministic, and non-empty: every
/// exercise is a real, executable interaction of the current runtime - no
/// placeholders, no UI-only exercises (H2.8 mission §6, §9-10).
///
/// The current MVP catalog builds N = 1 real exercise per lesson (the lesson's
/// own fully-guided, evaluated target), but this type and its controller are
/// N-capable so future lessons that the runtime can genuinely differentiate can
/// carry longer sequences without an architecture change.
final class PracticeSequence {
  PracticeSequence({
    required this.lessonId,
    required List<PracticeExercise> exercises,
  }) : exercises = List<PracticeExercise>.unmodifiable(exercises) {
    if (lessonId.isEmpty) {
      throw const FormatException(
          'PracticeSequence: lessonId must not be empty.');
    }
    if (exercises.isEmpty) {
      throw const FormatException(
          'PracticeSequence: an exercise sequence must not be empty.');
    }
    final orders = <int>{for (final exercise in exercises) exercise.order};
    if (orders.length != exercises.length) {
      throw const FormatException(
          'PracticeSequence: exercise orders must be distinct.');
    }
    if (exercises.any((exercise) => exercise.id.isEmpty)) {
      throw const FormatException(
          'PracticeSequence: exercise ids must not be empty.');
    }
  }

  /// The owning lesson. A sequence belongs to a Lesson, never a scheduler.
  final String lessonId;

  /// The exercises in deterministic order. Immutable: no mutable list escapes.
  final List<PracticeExercise> exercises;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeSequence &&
          other.lessonId == lessonId &&
          _listEq(other.exercises, exercises);

  @override
  int get hashCode => Object.hash(lessonId, Object.hashAll(exercises));

  @override
  String toString() =>
      'PracticeSequence($lessonId: ${exercises.length} exercises)';
}

bool _listEq(List<PracticeExercise> a, List<PracticeExercise> b) {
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