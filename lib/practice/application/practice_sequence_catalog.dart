import '../../midi/domain/expected_musical_target.dart';
import '../domain/learning_lesson.dart';
import '../domain/practice_exercise.dart';
import 'learning_catalog.dart';

/// Deterministic programmatic catalog of Practice Sequences per lesson.
///
/// For H2.8 every lesson's Practice Sequence contains exactly ONE real exercise:
/// the lesson's own fully-guided, single-target, evaluated practice interaction
/// (N = 1). It is an honest MVP decision - the current runtime executes a
/// single target, fully-guided, through the existing evaluated path, and the
/// learner proceeds through the existing Result / Continue flow. There is no
/// fake 'Next' button and no second exercise that would just be a different
/// label around the same interaction.
///
/// N = 1 is a catalog decision, NOT a structural limit: the exercise set maps
/// one exercise to one genuinely distinct executable practice interaction, so
/// the models and the [PracticeSequenceController] stay N-capable for future
/// lessons whose targets the runtime can truly differentiate.
final class PracticeSequenceCatalog {
  const PracticeSequenceCatalog(this.catalog);

  final LearningCatalog catalog;

  /// The deterministic sequence for [lesson].
  ///
  /// By construction every catalog lesson is covered; unknown lesson ids throw
  /// a clear [StateError] instead of silently producing an empty sequence.
  PracticeSequence sequenceFor(LearningLesson lesson) =>
      _sequenceFor(ownerId: lesson.id, targetId: lesson.targetId);

  /// The canonical Practice Exercise a review of [targetId] executes.
  ///
  /// Review enters by target id rather than by lesson (the Review Scheduler
  /// hands out due skill ids, not lesson ids), so this resolves the exercise
  /// through the very same curriculum builder [sequenceFor] uses instead of
  /// letting the review screen invent an execution input of its own. Review is
  /// ordinary practice against the same exercise definition, so both routes
  /// produce the same single-target, fully-guided, evaluated exercise.
  ///
  /// The id is deterministic and review-scoped (`review.<targetId>.exercise.01`)
  /// because a review has no lesson to own it; it is never random and never
  /// clock-derived.
  PracticeExercise exerciseForTargetId(String targetId) =>
      _exerciseFor(ownerId: 'review.$targetId', targetId: targetId);

  PracticeSequence _sequenceFor({
    required String ownerId,
    required String targetId,
  }) {
    return PracticeSequence(
      lessonId: ownerId,
      exercises: <PracticeExercise>[
        _exerciseFor(ownerId: ownerId, targetId: targetId),
      ],
    );
  }

  /// The one place a curriculum exercise is defined, shared by every route so
  /// lesson practice and review can never drift into different exercises.
  PracticeExercise _exerciseFor({
    required String ownerId,
    required String targetId,
  }) {
    final target = catalog.buildTargetForTargetId(targetId);
    final title = switch (target.mode) {
      TargetMode.block => 'Guided Block Practice',
      TargetMode.arpeggio => 'Guided Arpeggio Practice',
    };
    return PracticeExercise(
      id: '$ownerId.exercise.01',
      order: 1,
      title: title,
      targetId: targetId,
    );
  }
}