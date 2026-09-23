import '../../midi/application/expected_musical_target_factory.dart';
import '../../midi/domain/expected_musical_target.dart';
import '../domain/learning_lesson.dart';

/// Deterministic Learning Path catalog: the ordered "Piano Foundations" phase.
///
/// This is a boundary only - a fixed catalog listing six deterministic lessons
/// in stable order. Lesson identities and target ids are pinned and stable
/// (no UUIDs, no Random, no clock, no array-index-as-identity). Lesson 1
/// intentionally reuses the Slice-1 canonical identities
/// (`lesson-major-c-rh-block` / `major-c-rh-block`) so all Slice-1 persisted
/// progress keeps loading.
///
/// The catalog owns the musical forms (quality/root/hand/mode) per lesson so
/// the curriculum domain (`LearningLesson`) stays free of MIDI types. Targets
/// are derived through the frozen [ExpectedMusicalTargetFactory] with the
/// pinned target id.
final class LearningCatalog {
  const LearningCatalog();

  /// The musical form of one lesson (catalog-owned, not curriculum-owned).
  static const Map<String, ({TargetQuality quality, TargetRoot root, TargetHand hand, TargetMode mode})>
      _formsByLessonId = <String, ({
    TargetQuality quality,
    TargetRoot root,
    TargetHand hand,
    TargetMode mode
  })>{
    'lesson-major-c-rh-block': (
      quality: TargetQuality.major,
      root: TargetRoot.c,
      hand: TargetHand.right,
      mode: TargetMode.block,
    ),
    'lesson-major-c-rh-arpeggio': (
      quality: TargetQuality.major,
      root: TargetRoot.c,
      hand: TargetHand.right,
      mode: TargetMode.arpeggio,
    ),
    'lesson-major-c-lh-block': (
      quality: TargetQuality.major,
      root: TargetRoot.c,
      hand: TargetHand.left,
      mode: TargetMode.block,
    ),
    'lesson-major-c-lh-arpeggio': (
      quality: TargetQuality.major,
      root: TargetRoot.c,
      hand: TargetHand.left,
      mode: TargetMode.arpeggio,
    ),
    'lesson-major-c-bothUnison-block': (
      quality: TargetQuality.major,
      root: TargetRoot.c,
      hand: TargetHand.bothUnison,
      mode: TargetMode.block,
    ),
    'lesson-major-c-bothUnison-arpeggio': (
      quality: TargetQuality.major,
      root: TargetRoot.c,
      hand: TargetHand.bothUnison,
      mode: TargetMode.arpeggio,
    ),
  };

  /// Ordered lessons of the Learning Path (stable order = catalog order).
  static const List<LearningLesson> allLessons = <LearningLesson>[
    LearningLesson(
      id: 'lesson-major-c-rh-block',
      title: 'C Major',
      subtitle: 'C Major · Right Hand · Played together',
      order: 1,
      targetId: 'major-c-rh-block',
    ),
    LearningLesson(
      id: 'lesson-major-c-rh-arpeggio',
      title: 'C Major',
      subtitle: 'C Major · Right Hand · Played one at a time',
      order: 2,
      targetId: 'major-c-rh-arpeggio',
    ),
    LearningLesson(
      id: 'lesson-major-c-lh-block',
      title: 'C Major',
      subtitle: 'C Major · Left Hand · Played together',
      order: 3,
      targetId: 'major-c-lh-block',
    ),
    LearningLesson(
      id: 'lesson-major-c-lh-arpeggio',
      title: 'C Major',
      subtitle: 'C Major · Left Hand · Played one at a time',
      order: 4,
      targetId: 'major-c-lh-arpeggio',
    ),
    LearningLesson(
      id: 'lesson-major-c-bothUnison-block',
      title: 'C Major',
      subtitle: 'C Major · Both Hands · Played together',
      order: 5,
      targetId: 'major-c-bothUnison-block',
    ),
    LearningLesson(
      id: 'lesson-major-c-bothUnison-arpeggio',
      title: 'C Major',
      subtitle: 'C Major · Both Hands · Played one at a time',
      order: 6,
      targetId: 'major-c-bothUnison-arpeggio',
    ),
  ];

  /// The lesson with [id], or null when unknown.
  LearningLesson? lessonById(String id) {
    for (final lesson in allLessons) {
      if (lesson.id == id) {
        return lesson;
      }
    }
    return null;
  }

  /// The lesson that follows [id] in the catalog, or null when unknown/last.
  LearningLesson? nextLessonAfter(String id) {
    for (var i = 0; i < allLessons.length; i++) {
      if (allLessons[i].id == id) {
        return i + 1 < allLessons.length ? allLessons[i + 1] : null;
      }
    }
    return null;
  }

  /// The lesson immediately before [id], or null when unknown/first.
  LearningLesson? previousLessonBefore(String id) {
    for (var i = 0; i < allLessons.length; i++) {
      if (allLessons[i].id == id) {
        return i > 0 ? allLessons[i - 1] : null;
      }
    }
    return null;
  }

  /// Builds the deterministic expected target for [lesson].
  ///
  /// By construction every catalog lesson has a pinned form; unknown ids throw
  /// a clear [StateError] instead of silently producing nothing.
  ExpectedMusicalTarget buildTarget(LearningLesson lesson) {
    final form = _formsByLessonId[lesson.id];
    if (form == null) {
      throw StateError('LearningCatalog: no form for lesson "${lesson.id}".');
    }
    return const ExpectedMusicalTargetFactory().build(
      quality: form.quality,
      root: form.root,
      hand: form.hand,
      mode: form.mode,
      targetId: lesson.targetId,
    );
  }
}