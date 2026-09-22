import '../../midi/domain/evaluation_result.dart';
import 'lesson_progress.dart';
import 'lesson_progress_store.dart';

/// Applies already-produced [EvaluationResult]s to cumulative learner-facing
/// [LessonProgress], persisted through a [LessonProgressStore].
///
/// This service does not grade: it consumes frozen evaluation outcomes and only
/// accumulates stars and attempt counts (see [LessonProgress]). Practice
/// attempts that end in abandoned/invalidated never reach this service.
class LessonProgressService {
  final LessonProgressStore store;

  LessonProgressService({required this.store});

  /// Loads current progress for [targetId] and records one [result].
  ///
  /// - [EvaluatedResult] with `stars` -> accumulates stars (cap 10), +1 attempt
  /// - [NotEnoughPerformanceResult] -> zero stars, +1 attempt
  /// - zero-star [EvaluatedResult] -> zero stars, +1 attempt
  Future<LessonProgress> recordResult({
    required String targetId,
    required EvaluationResult result,
  }) async {
    final current = await store.read(targetId);
    final base = current ?? LessonProgress.initial(targetId);
    final updated = base.applyEvaluationResult(result);
    await store.write(updated);
    return updated;
  }

  /// Loads the persisted progress for [targetId] (or initial when absent).
  Future<LessonProgress> loadProgress(String targetId) async =>
      await store.read(targetId) ?? LessonProgress.initial(targetId);
}