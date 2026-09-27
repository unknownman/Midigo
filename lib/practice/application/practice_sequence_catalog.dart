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
  PracticeSequence sequenceFor(LearningLesson lesson) {
    final target = catalog.buildTargetForTargetId(lesson.targetId);
    final title = switch (target.mode) {
      TargetMode.block => 'Guided Block Practice',
      TargetMode.arpeggio => 'Guided Arpeggio Practice',
    };
    return PracticeSequence(
      lessonId: lesson.id,
      exercises: <PracticeExercise>[
        PracticeExercise(
          id: '${lesson.id}.exercise.01',
          order: 1,
          title: title,
          targetId: lesson.targetId,
        ),
      ],
    );
  }
}