import '../../midi/domain/evaluation_result.dart';
import 'lesson_progress.dart';
import 'lesson_progress_store.dart';
import 'review_scheduler.dart';

/// Applies already-produced [EvaluationResult]s to cumulative learner-facing
/// [LessonProgress], persisted through a [LessonProgressStore].
///
/// This service does not grade: it consumes frozen evaluation outcomes and only
/// accumulates stars and attempt counts (see [LessonProgress]). Practice
/// attempts that end in abandoned/invalidated never reach this service.
///
/// When a lesson transitions to completed (`!completed -> completed` at the
/// 10-star capacity), the learner's [ReviewScheduler] is informed through
/// [ReviewScheduler.registerEligibleSkill]. The transition happens exactly
/// once per completion: re-recording results on an already-completed lesson
/// never re-registers.
class LessonProgressService {
  final LessonProgressStore store;
  final ReviewScheduler? reviewScheduler;

  LessonProgressService({required this.store, this.reviewScheduler});

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
    final registrar = reviewScheduler;
    if (registrar != null && !base.isCompleted && updated.isCompleted) {
      await registrar.registerEligibleSkill(targetId);
    }
    return updated;
  }

  /// Loads the persisted progress for [targetId] (or initial when absent).
  Future<LessonProgress> loadProgress(String targetId) async =>
      await store.read(targetId) ?? LessonProgress.initial(targetId);
}