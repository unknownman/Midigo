import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/practice/domain/practice_exercise.dart';

const _targetId = 'major-c-rh-block';

PracticeExercise _pinnedExercise() => const PracticeExercise(
      id: 'lesson-major-c-rh-block.exercise.01',
      order: 1,
      title: 'Guided Block Practice',
      targetId: _targetId,
    );

void main() {
  group('PracticeExercise', () {
    test('is an immutable value type with pinned identity', () {
      const exercise = PracticeExercise(
        id: 'lesson-major-c-rh-block.exercise.01',
        order: 1,
        title: 'Guided Block Practice',
        targetId: _targetId,
      );

      expect(exercise.id, 'lesson-major-c-rh-block.exercise.01');
      expect(exercise.order, 1);
      expect(exercise.title, 'Guided Block Practice');
      expect(exercise.targetId, _targetId);
    });

    test('holds the exercise completion threshold for evaluated stars', () {
      expect(PracticeExercise.completionStarThreshold, 3);
    });

    test('asserts a non-positive order', () {
      expect(
        () => PracticeExercise(
          id: 'x.exercise.00',
          order: 0,
          title: 'Guided Block Practice',
          targetId: _targetId,
        ),
        throwsAssertionError,
      );
    });

    test('equality ignores identity and equals by value', () {
      const a = PracticeExercise(
        id: 'x.exercise.01',
        order: 1,
        title: 'Guided Block Practice',
        targetId: _targetId,
      );
      const b = PracticeExercise(
        id: 'x.exercise.01',
        order: 1,
        title: 'Guided Block Practice',
        targetId: _targetId,
      );
      const differentTitle = PracticeExercise(
        id: 'x.exercise.01',
        order: 1,
        title: 'Guided Arpeggio Practice',
        targetId: _targetId,
      );
      const differentTarget = PracticeExercise(
        id: 'x.exercise.01',
        order: 1,
        title: 'Guided Block Practice',
        targetId: 'major-c-rh-arpeggio',
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(differentTitle)));
      expect(a, isNot(equals(differentTarget)));
    });

    test('exercise id is deterministic, never random or clock-derived', () {
      final first = _pinnedExercise();
      final second = _pinnedExercise();

      expect(first.id, 'lesson-major-c-rh-block.exercise.01');
      expect(first, equals(second));
    });
  });

  group('PracticeSequence', () {
    PracticeExercise exercise({
      required String id,
      required int order,
    }) {
      return PracticeExercise(
        id: id,
        order: order,
        title: 'Guided Block Practice',
        targetId: _targetId,
      );
    }

    test('holds the ordered immutable exercises of one lesson', () {
      final sequence = PracticeSequence(
        lessonId: 'lesson-major-c-rh-block',
        exercises: [
          exercise(id: 'lesson-major-c-rh-block.exercise.01', order: 1),
        ],
      );

      expect(sequence.lessonId, 'lesson-major-c-rh-block');
      expect(sequence.exercises, hasLength(1));
      expect(sequence.exercises.single.targetId, _targetId);
    });

    test('belongs to a lesson, not a scheduler', () {
      final sequence = PracticeSequence(
        lessonId: 'lesson-major-c-rh-block',
        exercises: [
          exercise(id: 'lesson-major-c-rh-block.exercise.01', order: 1),
        ],
      );

      expect(sequence.lessonId, isNotEmpty);
      expect(sequence.exercises.single.order, greaterThan(0));
    });

    test('is N-capable: accepts a multi-exercise sequence in order', () {
      final sequence = PracticeSequence(
        lessonId: 'lesson-major-c-rh-block',
        exercises: [
          exercise(id: 'lesson-major-c-rh-block.exercise.01', order: 1),
          exercise(id: 'lesson-major-c-rh-block.exercise.02', order: 2),
          exercise(id: 'lesson-major-c-rh-block.exercise.03', order: 3),
        ],
      );

      expect(sequence.exercises.map((e) => e.order), [1, 2, 3]);
      expect(sequence.exercises.last.targetId, _targetId);
    });

    test('rejects an empty sequence', () {
      expect(
        () => PracticeSequence(
          lessonId: 'lesson-major-c-rh-block',
          exercises: const <PracticeExercise>[],
        ),
        throwsFormatException,
      );
    });

    test('rejects duplicate exercise orders', () {
      expect(
        () => PracticeSequence(
          lessonId: 'lesson-major-c-rh-block',
          exercises: [
            exercise(id: 'lesson-major-c-rh-block.exercise.01', order: 1),
            exercise(id: 'lesson-major-c-rh-block.exercise.02', order: 1),
          ],
        ),
        throwsFormatException,
      );
    });

    test('rejects an empty lesson id', () {
      expect(
        () => PracticeSequence(
          lessonId: '',
          exercises: [
            exercise(id: 'lesson-major-c-rh-block.exercise.01', order: 1),
          ],
        ),
        throwsFormatException,
      );
    });

    test('rejects empty exercise ids and never fabricates identities', () {
      expect(
        () => PracticeSequence(
          lessonId: 'lesson-major-c-rh-block',
          exercises: [
            exercise(id: '', order: 1),
          ],
        ),
        throwsFormatException,
      );
    });

    test('is immutable: the exercises list cannot be mutated by callers', () {
      final sequence = PracticeSequence(
        lessonId: 'lesson-major-c-rh-block',
        exercises: [
          exercise(id: 'lesson-major-c-rh-block.exercise.01', order: 1),
        ],
      );

      expect(
        () => sequence.exercises.clear(),
        throwsUnsupportedError,
      );
    });

    test('equality is value-based over lesson and ordered exercises', () {
      PracticeSequence build() => PracticeSequence(
            lessonId: 'lesson-major-c-rh-block',
            exercises: [
              exercise(id: 'lesson-major-c-rh-block.exercise.01', order: 1),
              exercise(id: 'lesson-major-c-rh-block.exercise.02', order: 2),
            ],
          );

      expect(build(), equals(build()));
      expect(build().hashCode, build().hashCode);
      expect(
        build(),
        isNot(equals(PracticeSequence(
          lessonId: 'lesson-major-c-rh-block',
          exercises: [
            exercise(id: 'lesson-major-c-rh-block.exercise.01', order: 1),
          ],
        ))),
      );
    });
  });
}