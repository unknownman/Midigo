import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/practice/application/learning_catalog.dart';
import 'package:miditutor/practice/application/practice_sequence_catalog.dart';
import 'package:miditutor/practice/domain/learning_lesson.dart';

const _lessonId = 'lesson-major-c-rh-block';

void main() {
  const catalog = LearningCatalog();
  const sequenceCatalog = PracticeSequenceCatalog(catalog);

  LearningLesson? lessonById(String id) => catalog.lessonById(id);

  group('LearningCatalog.buildTargetForTargetId', () {
    test('derives the same frozen target a lesson builds by target id', () {
      for (final lesson in LearningCatalog.allLessons) {
        final viaLesson = catalog.buildTarget(lesson);
        final viaTarget = catalog.buildTargetForTargetId(lesson.targetId);

        expect(viaTarget, equals(viaLesson));
      }
    });

    test('every lesson target id maps, including both-hands arpeggio', () {
      for (final lesson in LearningCatalog.allLessons) {
        expect(
          () => catalog.buildTargetForTargetId(lesson.targetId),
          returnsNormally,
        );
      }
    });

    test('unknown target ids throw instead of fabricating a form', () {
      expect(() => catalog.buildTargetForTargetId('unknown-target'),
          throwsStateError);
    });
  });

  group('PracticeSequenceCatalog', () {
    test('gives every lesson a deterministic sequence', () {
      for (final lesson in LearningCatalog.allLessons) {
        final sequence = sequenceCatalog.sequenceFor(lesson);

        expect(sequence.lessonId, lesson.id);
        expect(sequence.exercises, isNotEmpty);
      }
    });

    test('lesson 1 executes the C Major right-hand block target', () {
      final lesson = lessonById(_lessonId)!;
      final sequence = sequenceCatalog.sequenceFor(lesson);

      final exercise = sequence.exercises.single;
      expect(exercise.id, '$_lessonId.exercise.01');
      expect(exercise.order, 1);
      expect(exercise.targetId, lesson.targetId);
      expect(exercise.targetId, 'major-c-rh-block');
      expect(exercise.title, 'Guided Block Practice');
    });

    test('a same-form sequence is deterministic (same input -> same core)', () {
      final a = sequenceCatalog.sequenceFor(lessonById(_lessonId)!);
      final b = sequenceCatalog.sequenceFor(lessonById(_lessonId)!);

      expect(a.lessonId, b.lessonId);
      expect(a.exercises.single.id, b.exercises.single.id);
      expect(a.exercises.single.targetId, b.exercises.single.targetId);
    });

    test('currently N = 1: one real exercise per lesson', () {
      for (final lesson in LearningCatalog.allLessons) {
        final sequence = sequenceCatalog.sequenceFor(lesson);

        expect(
          sequence.exercises,
          hasLength(1),
          reason: 'H2.8 ships exactly one real exercise per sequence.',
        );
      }
    });

    test('easy arpeggio sequences are titled arpeggio, never block', () {
      for (final lesson in LearningCatalog.allLessons) {
        final sequence = sequenceCatalog.sequenceFor(lesson);
        final target = catalog.buildTargetForTargetId(lesson.targetId);
        final expectedTitle = target.mode.name == 'arpeggio'
            ? 'Guided Arpeggio Practice'
            : 'Guided Block Practice';

        expect(sequence.exercises.single.title, expectedTitle,
            reason: 'exercise wording must respect the target mode');
      }
    });

    test('every sequence exercise is runtime-executable (DAG via target)', () {
      for (final lesson in LearningCatalog.allLessons) {
        final sequence = sequenceCatalog.sequenceFor(lesson);
        for (final exercise in sequence.exercises) {
          expect(exercise.targetId, isNotEmpty);
          // The target resolves through the same factory the lesson uses.
          expect(catalog.buildTargetForTargetId(exercise.targetId).targetId,
              exercise.targetId);
        }
      }
    });
  });
}