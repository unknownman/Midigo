import '../../midi/domain/expected_musical_target.dart';
import 'practice_exercise.dart';

/// An instantiation of one [ExpectedMusicalTarget] as the focus of an exercise.
///
/// RT-005: a Practice Item is created from exactly one Exercise Instance.
/// Both identities are deterministic and caller-supplied; they are never
/// random and never derived from the practice clock.
///
/// An Exercise Instance is the *runtime* form of a curriculum [PracticeExercise]
/// - the two are deliberately distinct models and are never collapsed. Every
/// curriculum execution path builds its instance through
/// [ExerciseInstance.fromExercise] so the selected exercise, not an
/// independently supplied target, is the canonical execution input.
final class ExerciseInstance {
  final String id;

  /// The frozen expected target this exercise is built on.
  final ExpectedMusicalTarget expectedTarget;

  ExerciseInstance({required this.id, required this.expectedTarget}) {
    if (id.isEmpty) {
      throw const FormatException('ExerciseInstance: id must not be empty.');
    }
  }

  /// The single canonical construction point from a curriculum exercise to its
  /// runtime executable instance.
  ///
  /// The instance identity stays `exercise-<targetId>` - exactly the identity
  /// the runtime used before this boundary existed - so no contractual identity
  /// changes. What changes is ownership: the id and the target are both derived
  /// from the selected [PracticeExercise], and [target] must actually be that
  /// exercise's frozen target. A caller cannot smuggle in the target of some
  /// other exercise, which is precisely the bypass this boundary closes.
  factory ExerciseInstance.fromExercise({
    required PracticeExercise exercise,
    required ExpectedMusicalTarget target,
  }) {
    if (target.targetId != exercise.targetId) {
      throw FormatException(
        'ExerciseInstance.fromExercise: target "${target.targetId}" does not '
        'belong to exercise "${exercise.id}" (${exercise.targetId}).',
      );
    }
    return ExerciseInstance(
      id: 'exercise-${exercise.targetId}',
      expectedTarget: target,
    );
  }

  /// Convenience: the target id of the wrapped [expectedTarget].
  String get targetId => expectedTarget.targetId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExerciseInstance &&
          other.id == id &&
          other.expectedTarget == expectedTarget;

  @override
  int get hashCode => Object.hash(id, expectedTarget);

  @override
  String toString() => 'ExerciseInstance($id: $targetId)';
}