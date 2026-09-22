import '../../midi/domain/expected_musical_target.dart';

/// An instantiation of one [ExpectedMusicalTarget] as the focus of an exercise.
///
/// RT-005: a Practice Item is created from exactly one Exercise Instance.
/// Both identities are deterministic and caller-supplied; they are never
/// random and never derived from the practice clock.
final class ExerciseInstance {
  final String id;

  /// The frozen expected target this exercise is built on.
  final ExpectedMusicalTarget expectedTarget;

  ExerciseInstance({required this.id, required this.expectedTarget}) {
    if (id.isEmpty) {
      throw const FormatException('ExerciseInstance: id must not be empty.');
    }
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