import 'attempt.dart';
import 'exercise_instance.dart';

/// A concrete practice exercise within a Practice Interaction.
///
/// RT-005: a Practice Item references exactly one Exercise Instance, which wraps
/// one frozen [ExerciseInstance.expectedTarget]. An item owns the runtime
/// records ([Attempt]) produced against it during the interaction. The list is
/// immutable so each new attempt is exposed as a new immutable [PracticeItem].
class PracticeItem {
  /// Deterministic, caller-supplied id (never random, never clock-derived).
  final String id;

  final ExerciseInstance exerciseInstance;

  /// Immutable snapshot of attempts recorded against this item so far.
  final List<Attempt> attempts;

  PracticeItem({
    required this.id,
    required this.exerciseInstance,
    List<Attempt>? attempts,
  })  : attempts = List<Attempt>.unmodifiable(attempts ?? const <Attempt>[]) {
    if (id.isEmpty) {
      throw const FormatException('PracticeItem: id must not be empty.');
    }
  }

  /// Convenience: the wrapped exercise target id.
  String get targetId => exerciseInstance.targetId;

  PracticeItem copyWith({List<Attempt>? attempts}) => PracticeItem(
        id: id,
        exerciseInstance: exerciseInstance,
        attempts: attempts ?? this.attempts,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeItem &&
          other.id == id &&
          other.exerciseInstance == exerciseInstance &&
          _attemptListEq(other.attempts, attempts);

  @override
  int get hashCode => Object.hash(id, exerciseInstance, Object.hashAll(attempts));

  @override
  String toString() => 'PracticeItem($id: $targetId, ${attempts.length} attempts)';
}

bool _attemptListEq(List<Attempt> a, List<Attempt> b) {
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