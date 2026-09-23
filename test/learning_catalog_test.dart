import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/midi/domain/expected_musical_target.dart';
import 'package:miditutor/practice/application/learning_catalog.dart';
import 'package:miditutor/practice/domain/learning_lesson.dart';

void main() {
  const catalog = LearningCatalog();

  group('catalog order and identity', () {
    test('exposes six deterministic lessons in catalog order', () {
      expect(LearningCatalog.allLessons, hasLength(6));
      expect(
        LearningCatalog.allLessons.map((l) => l.id),
        <String>[
          'lesson-major-c-rh-block',
          'lesson-major-c-rh-arpeggio',
          'lesson-major-c-lh-block',
          'lesson-major-c-lh-arpeggio',
          'lesson-major-c-bothUnison-block',
          'lesson-major-c-bothUnison-arpeggio',
        ],
      );
    });

    test('lesson order is 1..6 and unique', () {
      final orders = LearningCatalog.allLessons.map((l) => l.order).toList();
      expect(orders, <int>[1, 2, 3, 4, 5, 6]);
    });

    test('lesson 1 reuses the Slice-1 canonical lesson/target ids', () {
      final first = LearningCatalog.allLessons.first;
      expect(first.id, 'lesson-major-c-rh-block');
      expect(first.targetId, 'major-c-rh-block');
      expect(first.title, 'C Major');
    });

    test('each targetId is unique', () {
      final targets = LearningCatalog.allLessons.map((l) => l.targetId).toSet();
      expect(targets, hasLength(6));
    });
  });

  group('catalog lookups', () {
    test('lessonById finds a known lesson', () {
      final lesson = catalog.lessonById('lesson-major-c-rh-block');
      expect(lesson, isNotNull);
      expect(lesson!.targetId, 'major-c-rh-block');
    });

    test('lessonById returns null for an unknown id', () {
      expect(catalog.lessonById('lesson-unknown'), isNull);
    });

    test('nextLessonAfter returns the following lesson', () {
      final next = catalog.nextLessonAfter('lesson-major-c-rh-block');
      expect(next!.id, 'lesson-major-c-rh-arpeggio');
    });

    test('nextLessonAfter returns null for last and unknown', () {
      expect(
          catalog.nextLessonAfter('lesson-major-c-bothUnison-arpeggio'), isNull);
      expect(catalog.nextLessonAfter('lesson-unknown'), isNull);
    });

    test('previousLessonBefore returns the preceding lesson', () {
      final prev = catalog.previousLessonBefore('lesson-major-c-lh-block');
      expect(prev!.id, 'lesson-major-c-rh-arpeggio');
    });

    test('previousLessonBefore returns null for first and unknown', () {
      expect(catalog.previousLessonBefore('lesson-major-c-rh-block'), isNull);
      expect(catalog.previousLessonBefore('lesson-unknown'), isNull);
    });
  });

  group('target derivation', () {
    test('buildTarget derives the pinned C Major RH block target', () {
      final lesson = LearningCatalog.allLessons.first;
      final target = catalog.buildTarget(lesson);
      expect(target.targetId, 'major-c-rh-block');
      expect(target.quality, TargetQuality.major);
      expect(target.root, TargetRoot.c);
      expect(target.hand, TargetHand.right);
      expect(target.mode, TargetMode.block);
      expect(target.notes.map((n) => n.pitch), <int>[60, 64, 67]);
    });

    test('buildTarget derives the pinned arpeggio target with 4 notes', () {
      final lesson =
          catalog.lessonById('lesson-major-c-lh-arpeggio')!;
      final target = catalog.buildTarget(lesson);
      expect(target.targetId, 'major-c-lh-arpeggio');
      expect(target.hand, TargetHand.left);
      expect(target.mode, TargetMode.arpeggio);
      expect(target.notes.map((n) => n.pitch), <int>[60, 64, 67, 72]);
      expect(target.onsetGroups, hasLength(4));
    });

    test('buildTarget derives the canonical bothUnison hand identity', () {
      final lesson =
          catalog.lessonById('lesson-major-c-bothUnison-block')!;
      final target = catalog.buildTarget(lesson);
      expect(target.targetId, 'major-c-bothUnison-block');
      expect(target.hand, TargetHand.bothUnison);
    });

    test('buildTarget throws for a lesson without a pinned form', () {
      final orphan = const LearningLesson(
        id: 'lesson-orphan',
        title: 'Orphan',
        subtitle: 'Orphan',
        order: 99,
        targetId: 'orphan-target',
      );
      expect(() => catalog.buildTarget(orphan),
          throwsA(isA<StateError>()));
    });
  });
}