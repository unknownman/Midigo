import '../../midi/domain/evaluation_result.dart';
import '../domain/learning_path.dart';

/// Learner-facing cumulative lesson progress for one musical target.
///
/// Persisted per target id. [stars] is cumulative `0..10`, [attemptCount] is
/// the number of evaluated performances regardless of outcome.
///
/// * A [NotEnoughPerformanceResult] and a zero-star [EvaluatedResult] both
///   increment [attemptCount] and add zero stars.
/// * Stars never decrease.
/// * Stars never exceed 10.
/// * 10 stars is lesson progress only - it is NOT mastery.
class LessonProgress implements LessonProgressLike {
  /// Frozen lesson star capacity (cumulative, capped, monotonic; "completed at
  /// 10"). This is the existing MVP acquisition ceiling and is also the
  /// Learning Path acquisition/completion condition.
  static const int starCapacity = 10;

  final String targetId;
  @override
  final int stars;
  @override
  final int attemptCount;

  LessonProgress({
    required this.targetId,
    required this.stars,
    required this.attemptCount,
  }) {
    if (targetId.isEmpty) {
      throw const FormatException('LessonProgress: targetId must not be empty.');
    }
    if (stars < 0 || stars > 10) {
      throw const FormatException('LessonProgress: stars must be in 0..10.');
    }
    if (attemptCount < 0) {
      throw const FormatException(
          'LessonProgress: attemptCount must be >= 0.');
    }
  }

  factory LessonProgress.initial(String targetId) =>
      LessonProgress(targetId: targetId, stars: 0, attemptCount: 0);

  /// True when the lesson has been practiced at least once.
  bool get hasBeenPracticed => attemptCount > 0;

  /// True when the lesson reached the MVP "completed at 10" acquisition
  /// ceiling. Lesson progress only - NOT mastery.
  bool get isCompleted => stars >= starCapacity;

  /// Applies one evaluation outcome to this progress and returns the next
  /// cumulative progress. No grading happens here: the outcome is already a
  /// frozen [EvaluationResult] (the runtime never owns the engine).
  LessonProgress applyEvaluationResult(EvaluationResult result) {
    if (result is EvaluatedResult) {
      final accumulated = stars + result.stars;
      return LessonProgress(
        targetId: targetId,
        stars: accumulated > starCapacity ? starCapacity : accumulated,
        attemptCount: attemptCount + 1,
      );
    }
    if (result is NotEnoughPerformanceResult) {
      return LessonProgress(
        targetId: targetId,
        stars: stars,
        attemptCount: attemptCount + 1,
      );
    }
    throw const FormatException(
        'LessonProgress: unknown EvaluationResult subtype.');
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'targetId': targetId,
        'stars': stars,
        'attemptCount': attemptCount,
      };

  factory LessonProgress.fromMap(Map<String, Object?> map) {
    final targetId = map['targetId'];
    final stars = map['stars'];
    final attemptCount = map['attemptCount'];
    if (targetId is! String || stars is! int || attemptCount is! int) {
      throw const FormatException(
          'LessonProgress.fromMap: fields must be {String targetId, '
          'int stars, int attemptCount}.');
    }
    return LessonProgress(
      targetId: targetId,
      stars: stars,
      attemptCount: attemptCount,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LessonProgress &&
          other.targetId == targetId &&
          other.stars == stars &&
          other.attemptCount == attemptCount;

  @override
  int get hashCode => Object.hash(targetId, stars, attemptCount);

  @override
  String toString() =>
      'LessonProgress($targetId: $stars stars / $attemptCount attempts)';
}