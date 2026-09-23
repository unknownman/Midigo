import 'learning_lesson.dart';

/// Learner-facing availability of a lesson on the Learning Path.
///
/// These are the only progression states slice 2 models. There is no
/// scheduler, mastery, needs-review, relearning, or lapsed state here - those
/// are out of scope and must not leak into the availability model.
enum LessonAvailability { locked, available, inProgress, completed }

/// Type-neutral view of the persisted lesson progress fields the availability
/// rule needs. Keeps the path layer independent of the concrete
/// [LessonProgress] implementation and of evaluation types.
abstract interface class LessonProgressLike {
  int get stars;
  int get attemptCount;
}

/// A lesson together with its persisted progress and derived availability.
///
/// Pure composition of existing domain types: it never touches MIDI transport,
/// evaluation, or CoreMIDI types.
final class LessonState<P extends LessonProgressLike> {
  final LearningLesson lesson;
  final P progress;
  final LessonAvailability availability;

  const LessonState({
    required this.lesson,
    required this.progress,
    required this.availability,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LessonState<P> &&
          other.lesson == lesson &&
          other.progress == progress &&
          other.availability == availability;

  @override
  int get hashCode => Object.hash(lesson, progress, availability);

  @override
  String toString() => 'LessonState(${lesson.id}: $availability)';
}

/// An ordered, deterministic view of the whole Learning Path: every lesson
/// with its current availability, derived entirely from persisted progress.
///
/// [lessons] preserves the catalog order. Lookups are null-safe so unknown
/// lesson ids are handled safely instead of throwing.
final class LearningPath<P extends LessonProgressLike> {
  final List<LessonState<P>> lessons;

  const LearningPath(this.lessons);

  LessonState<P>? lessonById(String lessonId) {
    for (final state in lessons) {
      if (state.lesson.id == lessonId) {
        return state;
      }
    }
    return null;
  }

  /// The lesson that wraps [lessonId]'s target, or null when unknown/absent.
  LessonState<P>? nextLessonAfter(String lessonId) {
    final index = _indexOf(lessonId);
    if (index == null || index + 1 >= lessons.length) {
      return null;
    }
    return lessons[index + 1];
  }

  /// The lesson immediately before [lessonId], or null when unknown/first.
  LessonState<P>? previousLessonBefore(String lessonId) {
    final index = _indexOf(lessonId);
    if (index == null || index == 0) {
      return null;
    }
    return lessons[index - 1];
  }

  int? _indexOf(String lessonId) {
    for (var i = 0; i < lessons.length; i++) {
      if (lessons[i].lesson.id == lessonId) {
        return i;
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LearningPath<P> && _listEq(other.lessons, lessons);

  @override
  int get hashCode => Object.hashAll(lessons);
}

bool _listEq<P extends LessonProgressLike>(
    List<LessonState<P>> a, List<LessonState<P>> b) {
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