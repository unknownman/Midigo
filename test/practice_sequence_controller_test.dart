import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/practice/application/practice_sequence_controller.dart';
import 'package:miditutor/practice/domain/practice_exercise.dart';

const _lessonId = 'lesson-major-c-rh-block';
const _targetId = 'major-c-rh-block';

PracticeExercise _exercise(int order) {
  return PracticeExercise(
    id: '$_lessonId.exercise.${order.toString().padLeft(2, '0')}',
    order: order,
    title: 'Guided Block Practice',
    targetId: _targetId,
  );
}

PracticeSequence _sequence(int exerciseCount) {
  return PracticeSequence(
    lessonId: _lessonId,
    exercises: [
      for (var order = 1; order <= exerciseCount; order++) _exercise(order),
    ],
  );
}

void main() {
  group('PracticeSequenceSnapshot', () {
    test('starts the controller at exercise 1 with nothing completed', () {
      final controller = PracticeSequenceController(sequence: _sequence(3));

      final snapshot = controller.value;
      expect(snapshot.currentIndex, 0);
      expect(snapshot.currentExercise.order, 1);
      expect(snapshot.totalExercises, 3);
      expect(snapshot.completedOrders, isEmpty);
      expect(snapshot.sequenceComplete, isFalse);
      expect(snapshot.progress, 0);
    });

    test('rejects an out-of-range current index', () {
      expect(
        () => PracticeSequenceSnapshot(
          sequence: _sequence(1),
          currentIndex: 1,
          completedOrders: const <int>{},
        ),
        throwsRangeError,
      );
    });

    test('rejects completed orders that reference no exercise', () {
      expect(
        () => PracticeSequenceSnapshot(
          sequence: _sequence(1),
          currentIndex: 0,
          completedOrders: const <int>{99},
        ),
        throwsArgumentError,
      );
    });

    test('exposes completion interaction facts per exercise', () {
      final snapshot = PracticeSequenceSnapshot(
        sequence: _sequence(3),
        currentIndex: 1,
        completedOrders: const <int>{1},
      );

      expect(snapshot.currentExercise.order, 2);
      expect(snapshot.isCurrentExerciseCompleted, isFalse);
      expect(snapshot.canAdvance, isFalse);
      expect(snapshot.completedCount, 1);
      expect(snapshot.progress, closeTo(1 / 3, 0.0001));
    });

    test('value equality compares sequence, index, and completed set', () {
      PracticeSequenceSnapshot build() => PracticeSequenceSnapshot(
            sequence: _sequence(3),
            currentIndex: 1,
            completedOrders: const <int>{1, 2},
          );

      expect(build(), equals(build()));
      expect(build().hashCode, build().hashCode);
      expect(
        build(),
        isNot(equals(PracticeSequenceSnapshot(
          sequence: _sequence(3),
          currentIndex: 1,
          completedOrders: const <int>{1},
        ))),
      );
    });
  });

  group('PracticeSequenceController', () {
    test('completing the only exercise completes the sequence (N = 1)', () {
      final controller = PracticeSequenceController(sequence: _sequence(1));

      expect(controller.value.sequenceComplete, isFalse);
      controller.completeCurrentExercise();

      expect(controller.value.completedOrders, {1});
      expect(controller.value.isCurrentExerciseCompleted, isTrue);
      expect(controller.value.sequenceComplete, isTrue);
      expect(controller.value.progress, 1);
    });

    test('advance is a no-op on the last exercise even when completed', () {
      final controller = PracticeSequenceController(sequence: _sequence(1));
      controller.completeCurrentExercise();

      controller.advanceExercise();

      expect(controller.value.currentIndex, 0);
      expect(controller.value.sequenceComplete, isTrue);
    });

    test('advance is a no-op while the current exercise is incomplete', () {
      final controller = PracticeSequenceController(sequence: _sequence(3));

      controller.advanceExercise();
      expect(controller.value.currentIndex, 0);

      controller.completeCurrentExercise();
      controller.advanceExercise();
      expect(controller.value.currentIndex, 1);
    });

    test('completing every exercise in order completes the sequence', () {
      final controller = PracticeSequenceController(sequence: _sequence(3));

      for (var i = 1; i <= 3; i++) {
        expect(controller.value.sequenceComplete, isFalse);
        expect(controller.value.currentExercise.order, i);
        controller.completeCurrentExercise();
        controller.advanceExercise();
      }

      expect(controller.value.completedOrders, {1, 2, 3});
      expect(controller.value.sequenceComplete, isTrue);
      expect(controller.value.progress, 1);
    });

    test('completion is idempotent and sticky across retries', () {
      final controller = PracticeSequenceController(sequence: _sequence(1));

      controller.completeCurrentExercise();
      final complete = controller.value;
      // Retrying the same exercise never un-completes it.
      controller.completeCurrentExercise();
      controller.completeCurrentExercise();

      expect(controller.value.completedOrders, {1});
      expect(controller.value.sequenceComplete, isTrue);
      expect(controller.value, equals(complete));
    });

    test('sequence completion is structural, not a mastery claim', () {
      final controller = PracticeSequenceController(sequence: _sequence(1));
      controller.completeCurrentExercise();

      // The controller carries no stars/mastery; it only records that the
      // exercise met its completion condition (§12).
      expect(controller.value.completedCount, 1);
      expect(controller.value.totalExercises, 1);
      expect(controller.value.sequenceComplete, isTrue);
    });

    test('the controller notifies listeners on completion and advance', () {
      final controller = PracticeSequenceController(sequence: _sequence(2));
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.completeCurrentExercise();
      controller.advanceExercise();

      expect(notifications, 2);
      controller.dispose();
    });
  });
}