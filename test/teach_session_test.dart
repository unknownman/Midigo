import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/practice/application/teach_session.dart';
import 'package:miditutor/practice/application/teach_step.dart';

TeachStep _step(int order, {bool showsKeyboard = false}) => TeachStep(
      id: 'step-$order',
      order: order,
      title: 'Step $order',
      content: 'Content $order',
      learnerAction: 'Action $order',
      showsKeyboard: showsKeyboard,
    );

void main() {
  group('TeachSessionSnapshot', () {
    test('opens on step 1: nothing completed, nothing advanceable backwards',
        () {
      final snapshot = TeachSessionSnapshot(
        steps: <TeachStep>[
          _step(1),
          _step(2),
          _step(3),
        ],
        currentIndex: 0,
        completedOrders: const <int>{},
        teachComplete: false,
      );

      expect(snapshot.totalSteps, 3);
      expect(snapshot.currentIndex, 0);
      expect(snapshot.canGoPrevious, isFalse);
      expect(snapshot.canAdvance, isTrue);
      expect(snapshot.isOnLastStep, isFalse);
      expect(snapshot.currentStepShowsKeyboard, isFalse);
      expect(snapshot.completedCount, 0);
      expect(snapshot.progress, 0);
      expect(snapshot.teachComplete, isFalse);
      expect(snapshot.currentStep.title, 'Step 1');
    });

    test('reports the keyboard demonstration flag for the shown step', () {
      final snapshot = TeachSessionSnapshot(
        steps: <TeachStep>[
          _step(1),
          _step(2, showsKeyboard: true),
        ],
        currentIndex: 1,
        completedOrders: const <int>{1},
        teachComplete: false,
      );

      expect(snapshot.currentStepShowsKeyboard, isTrue);
    });

    test('progress is completed/total; 1.0 once Teach is complete', () {
      final partial = TeachSessionSnapshot(
        steps: <TeachStep>[
          _step(1),
          _step(2),
          _step(3),
          _step(4),
        ],
        currentIndex: 2,
        completedOrders: const <int>{1, 2},
        teachComplete: false,
      );
      expect(partial.progress, 0.5);

      final done = TeachSessionSnapshot(
        steps: <TeachStep>[_step(1), _step(2)],
        currentIndex: 1,
        completedOrders: const <int>{1, 2},
        teachComplete: true,
      );
      expect(done.teachComplete, isTrue);
      expect(done.canAdvance, isFalse);
      expect(done.progress, 1.0);
    });

    test('exposes unmodifiable collections', () {
      final snapshot = TeachSessionSnapshot(
        steps: <TeachStep>[
          _step(1),
          _step(2),
        ],
        currentIndex: 0,
        completedOrders: const <int>{1},
        teachComplete: false,
      );

      expect(() => snapshot.steps.add(_step(3)), throwsUnsupportedError);
      expect(() => snapshot.completedOrders.add(3), throwsUnsupportedError);
    });
  });

  group('TeachSessionController', () {
    TeachSessionController controllerWith(int stepCount) =>
        TeachSessionController(
          steps: <TeachStep>[for (var o = 1; o <= stepCount; o++) _step(o)],
        );

    test('advance marks only the reached step and moves forward', () {
      final controller = controllerWith(3);
      controller.advance();

      var snapshot = controller.value;
      expect(snapshot.currentIndex, 1);
      expect(snapshot.completedOrders, <int>{1});
      expect(snapshot.canGoPrevious, isTrue);
      expect(snapshot.teachComplete, isFalse);
      expect(snapshot.progress, closeTo(1 / 3, 1e-9));

      controller.advance();
      snapshot = controller.value;
      expect(snapshot.currentIndex, 2);
      expect(snapshot.completedOrders, <int>{1, 2});
      expect(snapshot.progress, closeTo(2 / 3, 1e-9));
    });

    test('advancing past the final step completes Teach and moves no further',
        () {
      final controller = controllerWith(2);
      controller.advance();
      expect(controller.value.teachComplete, isFalse);

      controller.advance();
      final snapshot = controller.value;
      expect(snapshot.teachComplete, isTrue);
      expect(snapshot.completedOrders, <int>{1, 2});
      // The final step stays the shown step: completion is not a crash past N.
      expect(snapshot.currentIndex, 1);
      expect(snapshot.canAdvance, isFalse);
      expect(snapshot.progress, 1.0);
    });

    test('advance after Teach is complete is a no-op', () {
      final controller = controllerWith(1);
      controller.advance();
      final completed = controller.value;

      controller.advance();

      expect(controller.value == completed, isTrue);
      expect(controller.value.completedCount, 1);
    });

    test('future steps are never presented as completed', () {
      final controller = controllerWith(4);
      controller.advance();

      // Only step 1 is completed even though step 2 is already visible.
      expect(controller.value.completedOrders, <int>{1});
      expect(controller.value.completedOrders.contains(2), isFalse);
    });

    test('goPrevious moves back but never uncompletes a reached step', () {
      final controller = controllerWith(3);
      controller.advance();
      controller.advance();
      expect(controller.value.completedOrders, <int>{1, 2});

      controller.goPrevious();
      expect(controller.value.currentIndex, 1);
      expect(controller.value.completedOrders, <int>{1, 2});
      expect(controller.value.teachComplete, isFalse);

      controller.goPrevious();
      expect(controller.value.currentIndex, 0);
      expect(controller.value.completedOrders, <int>{1, 2});
    });

    test('goPrevious is guarded at the first step', () {
      final controller = controllerWith(3);
      controller.goPrevious();
      expect(controller.value.currentIndex, 0);
      expect(controller.value.completedOrders, isEmpty);
    });

    test('goPrevious is a no-op once Teach is complete', () {
      final controller = controllerWith(2);
      controller.advance();
      controller.advance();
      expect(controller.value.teachComplete, isTrue);

      controller.goPrevious();
      expect(controller.value.teachComplete, isTrue);
      expect(controller.value.currentIndex, 1);
    });

    test('back then forward does not double-complete the revisited step', () {
      final controller = controllerWith(3);
      controller.advance();
      controller.advance();
      controller.goPrevious();
      controller.advance();

      expect(controller.value.completedOrders, <int>{1, 2});
      expect(controller.value.completedCount, 2);
      expect(controller.value.currentIndex, 2);
    });

    test('a fresh controller starts a fresh session: completion never persists',
        () {
      final steps = <TeachStep>[_step(1), _step(2)];
      final first = TeachSessionController(steps: steps)
        ..advance()
        ..advance();
      expect(first.value.teachComplete, isTrue);

      final second = TeachSessionController(steps: steps);
      expect(second.value.completedCount, 0);
      expect(second.value.currentIndex, 0);
      expect(second.value.teachComplete, isFalse);
    });
  });
}