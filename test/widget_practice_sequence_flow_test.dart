import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/main.dart';
import 'package:miditutor/midi/domain/evaluation_result.dart';
import 'package:miditutor/practice/application/in_memory_lesson_progress_store.dart';
import 'package:miditutor/practice/application/learning_catalog.dart';
import 'package:miditutor/practice/application/lesson_progress_service.dart';

import 'fakes.dart';

void main() {
  late FakeConnection connection;
  late FakeMidiStream stream;
  late InMemoryLessonProgressStore store;

  Widget app() {
    connection = FakeConnection();
    stream = FakeMidiStream();
    store = InMemoryLessonProgressStore();
    final clock = FakeClock(DateTime(2025, 1, 1, 9, 0, 0));
    return MidiTutorApp(
      discovery: FakeDiscovery(),
      connection: connection,
      captureFactory: () => stream,
      progressStore: store,
      reviewScheduler: newFakeReviewScheduler(clock),
      clock: clock,
    );
  }

  Future<void> goToLesson(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Learning Path'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lesson 1 · C Major'));
    await tester.pumpAndSettle();
  }

  Future<void> passThroughTeach(WidgetTester tester) async {
    while (find.widgetWithText(FilledButton, 'Next')
        .evaluate()
        .isNotEmpty) {
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Start Practice'));
    await tester.pumpAndSettle();
  }

  Future<void> startPractice(WidgetTester tester) async {
    await passThroughTeach(tester);
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

  FilledButton continueButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'));

  testWidgets('practice shows the exercise context for the only exercise',
      (WidgetTester tester) async {
    await goToLesson(tester);
    await startPractice(tester);

    expect(
      find.byKey(const ValueKey('practice-exercise-context')),
      findsOneWidget,
    );
    expect(
      find.text('Exercise 1 of 1 · Guided Block Practice'),
      findsOneWidget,
    );
    expect(find.text('Play all notes together.'), findsOneWidget);
  });

  testWidgets('a passing exercise completes the sequence and unlocks Continue',
      (WidgetTester tester) async {
    await goToLesson(tester);
    await startPractice(tester);

    stream.pushPerfectCMajorBlock();
    await tester.pumpAndSettle();
    await finish(tester);

    expect(find.text('Result'), findsOneWidget);
    expect(
      find.text('Exercise 1 of 1 · Guided Block Practice'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('practice-complete')), findsOneWidget);
    expect(find.text('Practice Complete'), findsOneWidget);
    expect(continueButton(tester).onPressed, isNotNull);
    expect(find.byKey(const ValueKey('continue-hint')), findsNothing);
  });

  testWidgets('a NEP attempt never completes the exercise and locks Continue',
      (WidgetTester tester) async {
    await goToLesson(tester);
    await startPractice(tester);

    await finish(tester);

    expect(find.byKey(const ValueKey('nep-message')), findsOneWidget);
    expect(find.byKey(const ValueKey('practice-complete')), findsNothing);
    expect(continueButton(tester).onPressed, isNull);
    expect(find.byKey(const ValueKey('continue-hint')), findsOneWidget);
    expect(find.textContaining('3 or more stars'), findsOneWidget);

    // Retry keeps the SAME exercise (still Exercise 1 of 1, no new position).
    await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Exercise 1 of 1 · Guided Block Practice'),
        findsOneWidget);
  });

  testWidgets('a zero-star evaluated attempt also never completes the exercise',
      (WidgetTester tester) async {
    await goToLesson(tester);
    await startPractice(tester);

    stream.pushMessyCMajorBlock();
    await tester.pumpAndSettle();
    await finish(tester);

    expect(find.byKey(const ValueKey('attempt-stars')), findsOneWidget);
    expect(find.byKey(const ValueKey('practice-complete')), findsNothing);
    expect(continueButton(tester).onPressed, isNull);
  });

  testWidgets('completion is sticky even when the learner retries afterwards',
      (WidgetTester tester) async {
    await goToLesson(tester);
    await startPractice(tester);

    stream.pushPerfectCMajorBlock();
    await tester.pumpAndSettle();
    await finish(tester);
    expect(find.byKey(const ValueKey('practice-complete')), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
    await tester.pumpAndSettle();
    stream.pushPerfectCMajorBlock();
    await tester.pumpAndSettle();
    await finish(tester);

    // Retrying the same exercise never un-completes the sequence.
    expect(find.byKey(const ValueKey('practice-complete')), findsOneWidget);
    expect(continueButton(tester).onPressed, isNotNull);
  });

  testWidgets('Continue after completion returns to the path with the next '
      'lesson locked', (WidgetTester tester) async {
    await goToLesson(tester);
    await startPractice(tester);

    stream.pushPerfectCMajorBlock();
    await tester.pumpAndSettle();
    await finish(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Learning Path'), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsNWidgets(5));
  });

  testWidgets('the arpeggio lesson carries its own exercise context',
      (WidgetTester tester) async {
    await tester.pumpWidget(app());
    // Pre-complete half of lesson 1 so a single 5-star practice completes it
    // and unlocks lesson 2 (arpeggio).
    await LessonProgressService(store: store).recordResult(
      targetId: LearningCatalog.allLessons.first.targetId,
      result: EvaluatedResult(stars: 5, dimensions: const []),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Learning Path'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lesson 1 · C Major'));
    await tester.pumpAndSettle();
    await passThroughTeach(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();
    stream.pushPerfectCMajorBlock();
    await tester.pumpAndSettle();
    await finish(tester);
    expect(find.byKey(const ValueKey('practice-complete')), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    // Opening lesson 2 lands on its own arpeggio practice sequence.
    await tester.tap(find.text('Lesson 2 · C Major'));
    await tester.pumpAndSettle();
    await passThroughTeach(tester);

    expect(
      find.text('Exercise 1 of 1 · Guided Arpeggio Practice'),
      findsOneWidget,
    );
  });
}