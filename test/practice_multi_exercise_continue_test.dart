import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/practice/application/in_memory_lesson_progress_store.dart';
import 'package:miditutor/practice/application/learning_catalog.dart';
import 'package:miditutor/practice/application/lesson_progress_service.dart';
import 'package:miditutor/practice/domain/practice_exercise.dart';
import 'package:miditutor/ui/lesson/lesson_screen.dart';
import 'package:miditutor/ui/review/normal_practice_screen.dart';

import 'fakes.dart';

/// H2.11 §16 - Continue across a Practice Sequence.
///
/// The canonical H2.8 catalog is N = 1, so there must never be a fake "Next
/// Exercise". But the Practice Sequence models and controller are already
/// N-capable, so when a lesson (via the deterministic `sequenceBuilder` seam)
/// does carry a second genuine exercise, Continue must advance through the
/// existing [PracticeSequenceController] - the next exercise gets a fresh
/// session/interaction, and only the last exercise closes the lesson. The
/// N = 1 catalog still ends at the Result / Continue / leave flow.
void main() {
  const catalog = LearningCatalog();
  final lesson = LearningCatalog.allLessons.first;

  PracticeSequence twoExerciseSequence() => PracticeSequence(
        lessonId: lesson.id,
        exercises: <PracticeExercise>[
          PracticeExercise(
            id: '${lesson.id}.exercise.01',
            order: 1,
            title: 'Guided Block Practice',
            targetId: lesson.targetId,
          ),
          PracticeExercise(
            id: '${lesson.id}.exercise.02',
            order: 2,
            title: 'Block Practice, Second Pass',
            targetId: lesson.targetId,
          ),
        ],
      );

  PracticeSequence twoExerciseDistinctTargets() => PracticeSequence(
        lessonId: lesson.id,
        exercises: <PracticeExercise>[
          PracticeExercise(
            id: '${lesson.id}.exercise.01',
            order: 1,
            title: 'Guided Block Practice',
            targetId: lesson.targetId,
          ),
          PracticeExercise(
            id: '${lesson.id}.exercise.02',
            order: 2,
            title: 'Guided Arpeggio Practice',
            targetId: 'major-c-rh-arpeggio',
          ),
        ],
      );

  Future<void> passThroughTeach(WidgetTester tester) async {
    while (find.widgetWithText(FilledButton, 'Next').evaluate().isNotEmpty) {
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Start Practice'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Finish Practice'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
  }

  group('Lesson with a second exercise (N-capable sequence)', () {
    testWidgets('Continue advances to the next exercise instead of leaving '
        'the lesson', (WidgetTester tester) async {
      final connection = FakeConnection();
      final stream = FakeMidiStream();
      final store = InMemoryLessonProgressStore();
      final clock = FakeClock(DateTime(2025, 1, 1, 9, 0, 0));

      await tester.pumpWidget(MaterialApp(
        home: LessonScreen(
          lesson: lesson,
          catalog: catalog,
          discovery: FakeDiscovery(),
          connection: connection,
          captureFactory: () => stream,
          progressService: LessonProgressService(store: store),
          clock: clock,
          sequenceBuilder: (_) => twoExerciseSequence(),
        ),
      ));
      await tester.pumpAndSettle();
      await passThroughTeach(tester);

      // Exercise 1 of 2.
      expect(find.text('Exercise 1 of 2 · Guided Block Practice'),
          findsOneWidget);
      stream.pushPerfectCMajorBlock();
      await tester.pumpAndSettle();
      await finish(tester);

      // Result shows the position, is NOT the whole sequence yet, Continue is
      // unlocked (the current exercise completed).
      expect(find.text('Exercise 1 of 2 · Guided Block Practice'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('practice-complete')), findsNothing);
      final firstContinue = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Continue'),
      );
      expect(firstContinue.onPressed, isNotNull);

      // Continue advances into exercise 2 (a fresh session) - the learner stays
      // inside the lesson, never sees a fake 'Next Exercise' button.
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(find.text('Exercise 2 of 2 · Block Practice, Second Pass'),
          findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Start Attempt'),
          findsOneWidget);

      // Exercise 2 of 2.
      await tester.tap(find.widgetWithText(FilledButton, 'Start Attempt'));
      await tester.pumpAndSettle();
      stream.pushPerfectCMajorBlock();
      await tester.pumpAndSettle();
      await finish(tester);

      // Both exercises done: the sequence - and the lesson's stars - are
      // complete, so Continue closes the lesson.
      expect(find.byKey(const ValueKey('practice-complete')), findsOneWidget);
      expect(find.text('Practice Complete'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();

      // 10 lesson stars unlocked lesson 2, so Continue hands over to it.
      expect(find.text('Lesson 2 · C Major'), findsOneWidget);
    });

    testWidgets('the canonical N=1 catalog never fabricates a next exercise',
        (WidgetTester tester) async {
      final connection = FakeConnection();
      final stream = FakeMidiStream();
      final store = InMemoryLessonProgressStore();

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const ValueKey('open-lesson'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LessonScreen(
                      lesson: lesson,
                      catalog: catalog,
                      discovery: FakeDiscovery(),
                      connection: connection,
                      captureFactory: () => stream,
                      progressService: LessonProgressService(store: store),
                      clock: FakeClock(DateTime(2025, 1, 1, 9, 0, 0)),
                    ),
                  ),
                ),
                child: const Text('Open Lesson'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const ValueKey('open-lesson')));
      await tester.pumpAndSettle();
      await passThroughTeach(tester);

      expect(find.text('Exercise 1 of 1 · Guided Block Practice'),
          findsOneWidget);
      stream.pushPerfectCMajorBlock();
      await tester.pumpAndSettle();
      await finish(tester);

      // Single-exercise lesson: Continue goes straight out of the lesson.
      expect(find.byKey(const ValueKey('practice-complete')), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Start Attempt'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Next'), findsNothing);

      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('open-lesson')), findsOneWidget);
    });
  });

  group('Start practice pins to the first exercise of a sequence', () {
    testWidgets('a two-exercise sequence still executes only exercises.first',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(600, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final connection = FakeConnection();
      final stream = FakeMidiStream();
      final store = InMemoryLessonProgressStore();

      await tester.pumpWidget(MaterialApp(
        home: NormalPracticeScreen(
          lesson: lesson,
          catalog: catalog,
          discovery: FakeDiscovery(),
          connection: connection,
          captureFactory: () => stream,
          progressService: LessonProgressService(store: store),
          clock: FakeClock(DateTime(2025, 1, 1, 9, 0, 0)),
          sequenceBuilder: (_) => twoExerciseDistinctTargets(),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
      await tester.pumpAndSettle();
      stream.pushPerfectCMajorBlock();
      await tester.pumpAndSettle();
      await finish(tester);

      // Exactly the first exercise's target was exercised; the second exercise
      // in the injected sequence never ran.
      final services = LessonProgressService(store: store);
      final block = await services.loadProgress(lesson.targetId);
      final arpeggio = await services.loadProgress('major-c-rh-arpeggio');
      expect(block.attemptCount, 1);
      expect(block.stars, greaterThan(0));
      expect(arpeggio.attemptCount, 0);
      expect(arpeggio.stars, 0);
    });
  });
}