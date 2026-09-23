import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/practice/application/in_memory_lesson_progress_store.dart';
import 'package:miditutor/practice/application/learning_catalog.dart';
import 'package:miditutor/practice/application/learning_path_service.dart';
import 'package:miditutor/practice/application/lesson_progress.dart';
import 'package:miditutor/practice/application/lesson_progress_service.dart';
import 'package:miditutor/practice/domain/learning_path.dart';

void main() {
  const catalog = LearningCatalog();
  late InMemoryLessonProgressStore store;
  late LessonProgressService progressService;
  late LearningPathService service;

  setUp(() {
    store = InMemoryLessonProgressStore();
    progressService = LessonProgressService(store: store);
    service = LearningPathService(
      catalog: catalog,
      progressService: progressService,
    );
  });

  Future<void> seed(String targetId, int stars, int attempts) async {
    await store.write(LessonProgress(
      targetId: targetId,
      stars: stars,
      attemptCount: attempts,
    ));
  }

  group('fresh path', () {
    test('first lesson is available, the rest are locked', () async {
      final path = await service.loadPath();
      expect(path.lessons, hasLength(6));
      expect(path.lessons[0].availability, LessonAvailability.available);
      expect(path.lessons[0].progress.stars, 0);
      for (var i = 1; i < path.lessons.length; i++) {
        expect(path.lessons[i].availability, LessonAvailability.locked);
      }
    });
  });

  group('progress unlocks the next lesson deterministically', () {
    test('lesson is available, next is locked', () async {
      await seed('major-c-rh-block', 0, 1);
      final path = await service.loadPath();
      expect(path.lessons[0].availability, LessonAvailability.inProgress);
      expect(path.lessons[1].availability, LessonAvailability.locked);
    });

    test('zero-star / NEP attempt does NOT complete or unlock', () async {
      await seed('major-c-rh-block', 0, 3);
      final path = await service.loadPath();
      expect(path.lessons[0].availability, LessonAvailability.inProgress);
      expect(path.lessons[1].availability, LessonAvailability.locked);
      expect(path.lessons[0].progress.isCompleted, isFalse);
    });

    test('10 stars completes lesson 1 and unlocks lesson 2', () async {
      await seed('major-c-rh-block', 10, 2);
      final path = await service.loadPath();
      expect(path.lessons[0].availability, LessonAvailability.completed);
      expect(path.lessons[0].progress.isCompleted, isTrue);
      expect(path.lessons[1].availability, LessonAvailability.available);
    });

    test('9 stars is not completed and does not unlock', () async {
      await seed('major-c-rh-block', 9, 2);
      final path = await service.loadPath();
      expect(path.lessons[0].availability, LessonAvailability.inProgress);
      expect(path.lessons[1].availability, LessonAvailability.locked);
    });

    test('chain unlocks up to an incomplete lesson', () async {
      await seed('major-c-rh-block', 10, 2);
      await seed('major-c-rh-arpeggio', 10, 2);
      await seed('major-c-lh-block', 4, 1);
      final path = await service.loadPath();
      expect(path.lessons[0].availability, LessonAvailability.completed);
      expect(path.lessons[1].availability, LessonAvailability.completed);
      expect(path.lessons[2].availability, LessonAvailability.inProgress);
      expect(path.lessons[3].availability, LessonAvailability.locked);
      expect(path.lessons[4].availability, LessonAvailability.locked);
      expect(path.lessons[5].availability, LessonAvailability.locked);
    });

    test('a mid-lesson gap keeps later lessons locked', () async {
      await seed('major-c-rh-block', 10, 2);
      await seed('major-c-rh-arpeggio', 4, 1);
      final path = await service.loadPath();
      expect(path.lessons[0].availability, LessonAvailability.completed);
      expect(path.lessons[1].availability, LessonAvailability.inProgress);
      expect(path.lessons[2].availability, LessonAvailability.locked);
      expect(path.lessons[3].availability, LessonAvailability.locked);
      expect(path.lessons[4].availability, LessonAvailability.locked);
      expect(path.lessons[5].availability, LessonAvailability.locked);
    });
  });

  group('missing progress loads as initial', () {
    test('an unknown target id is handled safely', () async {
      final path = await service.loadPath();
      expect(path.lessonById('lesson-unknown'), isNull);
      expect(path.nextLessonAfter('lesson-unknown'), isNull);
      expect(path.previousLessonBefore('lesson-unknown'), isNull);
    });

    test('lookups wrap forward and backward', () async {
      final path = await service.loadPath();
      final rhArp = path.lessonById('lesson-major-c-rh-arpeggio');
      expect(rhArp, isNotNull);
      expect(path.nextLessonAfter(rhArp!.lesson.id)!.lesson.id,
          'lesson-major-c-lh-block');
      expect(path.previousLessonBefore(rhArp.lesson.id)!.lesson.id,
          'lesson-major-c-rh-block');
    });
  });
}