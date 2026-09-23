import '../domain/learning_lesson.dart';
import '../domain/learning_path.dart';
import 'learning_catalog.dart';
import 'lesson_progress.dart';
import 'lesson_progress_service.dart';

/// Derives the whole Learning Path from persisted [LessonProgress].
///
/// Locked behind the catalog: it knows the ordered lessons (deterministic),
/// loads each target's persisted progress via the frozen [LessonProgressService],
/// and applies the single availability/completion rule. It never grades,
/// never schedules, and never evaluates - it only derives state.
final class LearningPathService {
  final LearningCatalog catalog;
  final LessonProgressService progressService;

  const LearningPathService({
    required this.catalog,
    required this.progressService,
  });

  /// Loads every lesson's progress and derives each lesson's availability.
  Future<LearningPath<LessonProgress>> loadPath() async {
    final lessons = LearningCatalog.allLessons;
    final states = <LessonState<LessonProgress>>[];
    var previousCompleted = false;
    for (var i = 0; i < lessons.length; i++) {
      final state = await _deriveFor(
        lessons[i],
        isFirst: i == 0,
        previousCompleted: previousCompleted,
      );
      states.add(state);
      previousCompleted = state.progress.isCompleted;
    }
    return LearningPath<LessonProgress>(states);
  }

  /// Derives the availability for [lesson] given its persisted progress.
  Future<LessonState<LessonProgress>> _deriveFor(
    LearningLesson lesson, {
    required bool isFirst,
    required bool previousCompleted,
  }) async {
    final progress =
        await progressService.loadProgress(lesson.targetId);
    final availability = availableFor(
      progress: progress,
      isFirst: isFirst,
      previousCompleted: previousCompleted,
    );
    return LessonState<LessonProgress>(
      lesson: lesson,
      progress: progress,
      availability: availability,
    );
  }

  /// The single availability rule of the Learning Path.
  ///
  /// * `completed`  -> 10/10 stars (per MVP "completed at 10"); NOT mastery.
  /// * `inProgress` -> practiced but not yet completed.
  /// * `available`  -> unlocked, no practice yet (or nothing practiced at all).
  /// * `locked`     -> the immediately preceding lesson has not completed yet.
  ///
  /// A zero-star / NEP attempt never reaches `completed`, so it never unlocks
  /// the next lesson.
  static LessonAvailability availableFor({
    required LessonProgress progress,
    required bool isFirst,
    required bool previousCompleted,
  }) {
    if (progress.isCompleted) {
      return LessonAvailability.completed;
    }
    if (progress.hasBeenPracticed) {
      return LessonAvailability.inProgress;
    }
    if (isFirst || previousCompleted) {
      return LessonAvailability.available;
    }
    return LessonAvailability.locked;
  }
}