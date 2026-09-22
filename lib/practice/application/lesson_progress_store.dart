import 'lesson_progress.dart';

/// Persistence boundary for learner-facing [LessonProgress].
///
/// Persisted per target id only: `targetId`, `stars`, `attemptCount`.
/// Attempts, interactions, execution sessions, evidence, scheduler, mastery,
/// and raw MIDI are deliberately NOT part of this interface.
abstract interface class LessonProgressStore {
  /// Returns the stored progress for [targetId], or null when absent.
  Future<LessonProgress?> read(String targetId);

  /// Persists [progress] for its target id, overwriting any prior value.
  Future<void> write(LessonProgress progress);
}