import '../../midi/application/expected_musical_target_factory.dart';
import '../../midi/domain/expected_musical_target.dart';
import '../domain/exercise_instance.dart';

/// Slice-1 curriculum producer: one lesson ("C Major") mapping to exactly one
/// Exercise Instance of the deterministic `major-c-rh-block` target.
///
/// This is a boundary only - a fixed catalog, NOT a full Exercise Generator.
/// It derives its target through the frozen [ExpectedMusicalTargetFactory] and
/// pins the explicit `major-c-rh-block` target id used by every other layer.
final class Slice1Catalog {
  const Slice1Catalog();

  /// Deterministic lesson identity.
  static const String cMajorLessonId = 'lesson-major-c-rh-block';

  /// Deterministic target id every layer agrees on.
  static const String cMajorTargetId = 'major-c-rh-block';

  /// Builds the single Slice-1 exercise instance deterministically.
  ExerciseInstance buildCMajorBlockExercise() {
    final target = const ExpectedMusicalTargetFactory().build(
      quality: TargetQuality.major,
      root: TargetRoot.c,
      hand: TargetHand.right,
      mode: TargetMode.block,
      targetId: cMajorTargetId,
    );
    return ExerciseInstance(
      id: 'exercise-major-c-rh-block',
      expectedTarget: target,
    );
  }
}