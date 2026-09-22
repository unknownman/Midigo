import 'lesson_progress.dart';
import 'lesson_progress_store.dart';

/// In-memory [LessonProgressStore] for tests and in-memory sessions.
/// Not thread-safe; intended for single-isolate use.
class InMemoryLessonProgressStore implements LessonProgressStore {
  final Map<String, LessonProgress> _progressByTargetId =
      <String, LessonProgress>{};

  @override
  Future<LessonProgress?> read(String targetId) async =>
      _progressByTargetId[targetId];

  @override
  Future<void> write(LessonProgress progress) async {
    _progressByTargetId[progress.targetId] = progress;
  }
}