import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/main.dart';
import 'package:miditutor/midi/domain/evaluation_result.dart';
import 'package:miditutor/practice/application/evaluation_flow.dart';
import 'package:miditutor/practice/application/in_memory_lesson_progress_store.dart';
import 'package:miditutor/practice/application/learning_catalog.dart';
import 'package:miditutor/practice/application/lesson_progress_service.dart';
import 'package:miditutor/practice/application/practice_sequence_catalog.dart';
import 'package:miditutor/practice/application/practice_session_controller.dart';
import 'package:miditutor/practice/domain/attempt.dart';
import 'package:miditutor/practice/domain/exercise_instance.dart';
import 'package:miditutor/practice/domain/practice_exercise.dart';

import 'fakes.dart';

/// H2.11A - the canonical `PracticeExercise` execution boundary.
///
/// Before this correction `PracticeSessionController` reconstructed its own
/// execution object from a bare `targetProvider()`, so the selected curriculum
/// exercise was never the direct input to execution. These tests pin the
/// corrected boundary:
///
/// ```text
/// PracticeSequence
///     -> PracticeExercise
///     -> ExerciseInstance   (ExerciseInstance.fromExercise)
///     -> PracticeItem
///     -> PracticeInteraction
///     -> Attempt
/// ```
///
/// and prove the controller cannot execute an exercise it was not given.
void main() {
  const catalog = LearningCatalog();
  const sequenceCatalog = PracticeSequenceCatalog(catalog);
  const blockId = 'major-c-rh-block';
  const arpeggioId = 'major-c-rh-arpeggio';

  const lessonExercise = PracticeExercise(
    id: 'lesson-major-c-rh-block.exercise.01',
    order: 1,
    title: 'Guided Block Practice',
    targetId: blockId,
  );

  /// A second, genuinely different curriculum exercise. Different lesson,
  /// different target, different title.
  const otherExercise = PracticeExercise(
    id: 'lesson-major-c-rh-arpeggio.exercise.01',
    order: 1,
    title: 'Guided Arpeggio Practice',
    targetId: arpeggioId,
  );

  late FakeClock clock;
  late FakeConnection connection;
  late FakeMidiStream stream;
  late InMemoryLessonProgressStore store;

  setUp(() {
    clock = FakeClock(DateTime(2025, 1, 1, 11, 0, 0));
    connection = FakeConnection();
    stream = FakeMidiStream();
    store = InMemoryLessonProgressStore();
  });

  /// Builds a session for [exercise] and records every target id the controller
  /// resolves, so a test can see *which* curriculum input the target came from.
  Future<PracticeSessionController> connectAndStart(
    PracticeExercise exercise, {
    List<String>? resolvedTargetIds,
    bool recordLessonProgress = true,
  }) async {
    final controller = PracticeSessionController(
      discovery: FakeDiscovery(),
      connection: connection,
      captureFactory: () => stream,
      evaluation: const EvaluationFlowService(),
      progressService: LessonProgressService(store: store),
      clock: clock,
      exercise: exercise,
      targetFactory: (targetId) {
        resolvedTargetIds?.add(targetId);
        return catalog.buildTargetForTargetId(targetId);
      },
      recordLessonProgress: recordLessonProgress,
    );
    await controller.connect(kFakeSource);
    await controller.startAttempt();
    return controller;
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('ExerciseInstance.fromExercise - the single construction point', () {
    test('derives the runtime identity from the curriculum exercise', () {
      final instance = ExerciseInstance.fromExercise(
        exercise: lessonExercise,
        target: catalog.buildTargetForTargetId(lessonExercise.targetId),
      );

      // The identity is exactly the pre-H2.11A identity: no identity redesign.
      expect(instance.id, 'exercise-$blockId');
      expect(instance.targetId, blockId);
    });

    test('refuses a target that belongs to a different exercise', () {
      expect(
        () => ExerciseInstance.fromExercise(
          exercise: lessonExercise,
          target: catalog.buildTargetForTargetId(otherExercise.targetId),
        ),
        throwsFormatException,
      );
    });

    test('every catalog exercise is runtime-executable through it', () {
      for (final lesson in LearningCatalog.allLessons) {
        final exercise = sequenceCatalog.sequenceFor(lesson).exercises.single;

        final instance = ExerciseInstance.fromExercise(
          exercise: exercise,
          target: catalog.buildTargetForTargetId(exercise.targetId),
        );

        expect(instance.targetId, exercise.targetId);
        expect(instance.id, 'exercise-${exercise.targetId}');
      }
    });
  });

  group('PracticeSequenceCatalog.exerciseForTargetId - the review route', () {
    test('resolves the same executable exercise a lesson would', () {
      for (final lesson in LearningCatalog.allLessons) {
        final fromLesson =
            sequenceCatalog.sequenceFor(lesson).exercises.single;
        final fromTarget = sequenceCatalog.exerciseForTargetId(lesson.targetId);

        expect(fromTarget.targetId, fromLesson.targetId);
        expect(fromTarget.title, fromLesson.title);
        expect(fromTarget.order, fromLesson.order);
      }
    });

    test('is deterministic and never random or clock-derived', () {
      final a = sequenceCatalog.exerciseForTargetId(blockId);
      final b = sequenceCatalog.exerciseForTargetId(blockId);

      expect(a, equals(b));
      expect(a.id, 'review.$blockId.exercise.01');
    });

    test('gives different targets distinct exercise identities', () {
      final block = sequenceCatalog.exerciseForTargetId(blockId);
      final arpeggio = sequenceCatalog.exerciseForTargetId(arpeggioId);

      expect(block.id, isNot(arpeggio.id));
      expect(block.title, isNot(arpeggio.title));
    });
  });

  group('Test A - the selected PracticeExercise is the canonical input', () {
    test('execution builds its ExerciseInstance from the selected exercise',
        () async {
      final resolved = <String>[];
      final controller = await connectAndStart(
        lessonExercise,
        resolvedTargetIds: resolved,
      );
      addTearDown(controller.dispose);

      final item = controller.runtime.currentItems.single;

      // The Exercise Instance came from the selected curriculum exercise.
      expect(item.exerciseInstance.id, 'exercise-$blockId');
      expect(item.exerciseInstance.targetId, lessonExercise.targetId);

      // And every target the controller resolved was the exercise's own target:
      // there is no exercise-independent target source left to drift.
      expect(resolved, isNotEmpty);
      expect(resolved.toSet(), <String>{blockId});
    });

    test('the exercise, not a provider, owns the evaluation and progress '
        'target', () async {
      final controller = await connectAndStart(lessonExercise);
      addTearDown(controller.dispose);

      stream.pushPerfectCMajorBlock();
      await settle();
      await controller.endAttempt();

      // Progress was recorded against the selected exercise's target only.
      final progress = await LessonProgressService(store: store)
          .loadProgress(lessonExercise.targetId);
      expect(progress.attemptCount, 1);
      expect(progress.stars, greaterThan(0));

      // Evidence landed on the exercise's target stream, never another one.
      final contributions = controller.evidence.state.contributions;
      expect(contributions, isNotEmpty);
      expect(
        contributions.map((c) => c.identity.targetId).toSet(),
        <String>{lessonExercise.targetId},
      );
    });
  });

  group('Test B - execution follows the selected exercise, not another one', () {
    test('a different selected exercise executes that exercise', () async {
      final resolved = <String>[];
      final controller = await connectAndStart(
        otherExercise,
        resolvedTargetIds: resolved,
      );
      addTearDown(controller.dispose);

      final item = controller.runtime.currentItems.single;

      expect(item.exerciseInstance.targetId, otherExercise.targetId);
      expect(item.exerciseInstance.id, 'exercise-$arpeggioId');
      expect(resolved.toSet(), <String>{arpeggioId});
      expect(
        resolved.contains(blockId),
        isFalse,
        reason: 'the unselected exercise target was never resolved',
      );
    });

    test('two exercises on the same target stay distinct curriculum objects',
        () async {
      // Same target, different curriculum metadata: execution must follow the
      // selected exercise object rather than collapsing to "whatever target
      // happens to match".
      const lessonA = PracticeExercise(
        id: 'lesson-a.exercise.01',
        order: 1,
        title: 'Guided Block Practice',
        targetId: blockId,
      );
      const lessonB = PracticeExercise(
        id: 'lesson-b.exercise.02',
        order: 2,
        title: 'Block Practice, Second Pass',
        targetId: blockId,
      );

      final controllerA = await connectAndStart(lessonA);
      addTearDown(controllerA.dispose);
      final controllerB = await connectAndStart(lessonB);
      addTearDown(controllerB.dispose);

      // Same executable target (one lesson owns one target), but the controller
      // holds the *selected* exercise object, so the two sessions are not the
      // same curriculum execution even though the target coincides.
      expect(controllerA.exercise, lessonA);
      expect(controllerB.exercise, lessonB);
      expect(controllerA.exercise, isNot(controllerB.exercise));
      expect(
        controllerA.runtime.currentItems.single.exerciseInstance.targetId,
        controllerB.runtime.currentItems.single.exerciseInstance.targetId,
      );
    });

    test('a target from an unselected exercise cannot be injected', () async {
      // The only target seam takes a target id, so a foreign target can never
      // reach the execution instance - the exercise decides what is asked for.
      final controller = PracticeSessionController(
        discovery: FakeDiscovery(),
        connection: connection,
        captureFactory: () => stream,
        evaluation: const EvaluationFlowService(),
        progressService: LessonProgressService(store: store),
        clock: clock,
        exercise: lessonExercise,
        targetFactory: (targetId) =>
            catalog.buildTargetForTargetId(blockId == targetId ? blockId : arpeggioId),
      );
      addTearDown(controller.dispose);
      await controller.connect(kFakeSource);
      await controller.startAttempt();

      expect(
        controller.runtime.currentItems.single.exerciseInstance.targetId,
        blockId,
      );
    });
  });

  group('Test C - retry semantics survive the boundary correction', () {
    test('retry keeps the same exercise and interaction but arms a new attempt',
        () async {
      final controller = await connectAndStart(lessonExercise);
      addTearDown(controller.dispose);

      final interactionId = controller.runtime.currentInteraction!.id;
      final firstAttempt = controller.runtime.currentItems.single.attempts.single;

      stream.pushPerfectCMajorBlock();
      await settle();
      await controller.endAttempt();

      await controller.retryAttempt();

      final item = controller.runtime.currentItems.single;

      // Same interaction (retry is not a new engagement).
      expect(controller.runtime.currentInteraction!.id, interactionId);
      // Same exercise instance throughout.
      expect(item.exerciseInstance.targetId, lessonExercise.targetId);
      expect(item.exerciseInstance.id, 'exercise-$blockId');

      // A new attempt, distinct from the first.
      expect(item.attempts, hasLength(2));
      expect(item.attempts.first.id, firstAttempt.id);
      expect(item.attempts.last.id, isNot(firstAttempt.id));
      expect(item.attempts.last.state, AttemptState.armed);
    });

    test('retry starts a fresh capture with no previous event leakage',
        () async {
      final controller = await connectAndStart(lessonExercise);
      addTearDown(controller.dispose);

      stream.pushPerfectCMajorBlock();
      await settle();
      await controller.endAttempt();
      expect(
        controller.session.value.latestCompletedResult,
        isA<EvaluatedResult>(),
      );

      await controller.retryAttempt();

      // Finish the retried attempt without playing anything: if attempt 1's
      // events leaked into attempt 2's capture buffer, this would grade as a
      // real performance instead of ungraded input.
      await controller.endAttempt();

      expect(
        controller.session.value.latestCompletedResult,
        isA<NotEnoughPerformanceResult>(),
        reason: 'a fresh capture buffer must not inherit the previous '
            'attempt\'s MIDI events',
      );
    });
  });

  group('Test D - Lesson flow regression', () {
    Future<void> goToLesson(WidgetTester tester) async {
      await tester.pumpWidget(MidiTutorApp(
        discovery: FakeDiscovery(),
        connection: connection,
        captureFactory: () => stream,
        progressStore: store,
        reviewScheduler: newFakeReviewScheduler(clock),
        clock: clock,
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Learning Path'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lesson 1 · C Major'));
      await tester.pumpAndSettle();
    }

    Future<void> startPractice(WidgetTester tester) async {
      while (find.widgetWithText(FilledButton, 'Next').evaluate().isNotEmpty) {
        await tester.tap(find.widgetWithText(FilledButton, 'Next'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.widgetWithText(FilledButton, 'Start Practice'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
      await tester.pumpAndSettle();
    }

    testWidgets('Teach -> Practice -> Result -> Continue still works',
        (WidgetTester tester) async {
      await goToLesson(tester);
      await startPractice(tester);

      // The exercise still comes from the lesson's Practice Sequence.
      expect(find.text('Exercise 1 of 1 · Guided Block Practice'),
          findsOneWidget);

      stream.pushPerfectCMajorBlock();
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Finish Practice'));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Continue'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();

      // Continue leaves the lesson, proving the flow completed normally.
      expect(find.text('Learning Path'), findsOneWidget);
    });

    testWidgets('Retry from the Result screen re-practices the same exercise',
        (WidgetTester tester) async {
      await goToLesson(tester);
      await startPractice(tester);

      stream.pushPerfectCMajorBlock();
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Finish Practice'));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Exercise 1 of 1 · Guided Block Practice'),
          findsOneWidget);
      // Retry re-arms a fresh attempt inside the same session, so practice is
      // already in progress: the learner finishes the new attempt rather than
      // starting another one.
      expect(find.widgetWithText(FilledButton, 'Start Attempt'), findsNothing);
      final finishButton =
          tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Finish Practice'));
      expect(
        finishButton.onPressed,
        isNotNull,
        reason: 'the retried attempt is armed and ready to finish',
      );
    });
  });

  group('Test E - Review flow regression', () {
    Future<void> openReview(WidgetTester tester) async {
      tester.view.physicalSize = const Size(600, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final scheduler = newFakeReviewScheduler(clock);
      await makeReviewsReady(scheduler, clock, skillIds: const [blockId]);
      await tester.pumpWidget(MidiTutorApp(
        discovery: FakeDiscovery(),
        connection: connection,
        captureFactory: () => stream,
        progressStore: store,
        reviewScheduler: scheduler,
        clock: clock,
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Review'));
      await tester.pumpAndSettle();
    }

    testWidgets('Review -> Practice -> Result -> Continue still works',
        (WidgetTester tester) async {
      await openReview(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
      await tester.pumpAndSettle();

      stream.pushPerfectCMajorBlock();
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Finish Practice'));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Continue'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
    });

    testWidgets('Review never mutates lesson progress', (WidgetTester tester) async {
      await openReview(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
      await tester.pumpAndSettle();

      stream.pushPerfectCMajorBlock();
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Finish Practice'));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();

      final progress =
          await LessonProgressService(store: store).loadProgress(blockId);
      expect(
        progress.attemptCount,
        0,
        reason: 'review must not record into lesson progress',
      );
    });
  });

  group('Test F - Normal practice regression', () {
    Future<void> openNormalPractice(WidgetTester tester) async {
      tester.view.physicalSize = const Size(600, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final scheduler = newFakeReviewScheduler(clock);
      await makeReviewsReady(scheduler, clock, skillIds: const [blockId]);
      await tester.pumpWidget(MidiTutorApp(
        discovery: FakeDiscovery(),
        connection: connection,
        captureFactory: () => stream,
        progressStore: store,
        reviewScheduler: scheduler,
        clock: clock,
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Start'));
      await tester.pumpAndSettle();
    }

    testWidgets('Start opens ordinary practice against the lesson exercise',
        (WidgetTester tester) async {
      await openNormalPractice(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
      await tester.pumpAndSettle();

      stream.pushPerfectCMajorBlock();
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Finish Practice'));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();

      // Ordinary practice is not review, so it DOES record lesson progress.
      final progress =
          await LessonProgressService(store: store).loadProgress(blockId);
      expect(progress.attemptCount, 1);
    });
  });
}
