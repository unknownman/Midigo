import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/main.dart';
import 'package:miditutor/practice/application/fingering_data.dart';
import 'package:miditutor/practice/application/in_memory_lesson_progress_store.dart';
import 'package:miditutor/practice/application/learning_catalog.dart';
import 'package:miditutor/practice/application/lesson_instruction.dart';
import 'package:miditutor/practice/application/teach_sequence.dart';
import 'package:miditutor/ui/lesson/teach_view.dart';
import 'package:miditutor/ui/widgets/piano_keyboard_view.dart';

import 'fakes.dart';

void main() {
  late InMemoryLessonProgressStore store;

  Widget app() {
    store = InMemoryLessonProgressStore();
    final clock = FakeClock(DateTime(2025, 1, 1, 9, 0, 0));
    return MidiTutorApp(
      discovery: FakeDiscovery(),
      connection: FakeConnection(),
      captureFactory: FakeMidiStream.new,
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

  Future<void> tapNext(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
  }

  Widget harness({required VoidCallback onStartPractice}) {
    final lesson = LearningCatalog.allLessons.first;
    const fingerings = FingeringCatalog();
    final instruction = LessonInstructionFactory().build(
      target: const LearningCatalog().buildTarget(lesson),
      fingerings: fingerings.fingeringsFor(lesson.targetId),
    );
    return MaterialApp(
      home: Scaffold(
        body: TeachView(
          lesson: lesson,
          instruction: instruction,
          steps: TeachSequence.cMajorVerbatim,
          onStartPractice: onStartPractice,
        ),
      ),
    );
  }

  testWidgets('TeachView walks one learner-facing step at a time', (tester) async {
    var practiced = false;
    await tester.pumpWidget(harness(onStartPractice: () => practiced = true));
    await tester.pumpAndSettle();

    expect(find.text('Lesson 1 · C Major'), findsOneWidget);
    expect(find.byKey(const ValueKey('teach-step-hud')), findsOneWidget);
    expect(find.text('Step 1 of 10'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Right Hand'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Block'), findsOneWidget);
    expect(find.byType(PianoKeyboardView), findsNothing);
    // On step 1 Back is disabled; only the current step is active.
    final back = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('teach-back')),
    );
    expect(back.onPressed, isNull);
    expect(find.widgetWithText(FilledButton, 'Next'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Start Practice'), findsNothing);

    await tapNext(tester);

    expect(find.text('Step 2 of 10'), findsOneWidget);
    expect(find.text('What is a Major chord?'), findsOneWidget);
    final f2p = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('teach-progress')),
    );
    expect(f2p.value, closeTo(0.1, 1e-9));
    final afterNext = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('teach-back')),
    );
    expect(afterNext.onPressed, isNotNull);

    // Back re-shows the previous content without uncompleting it.
    await tester.tap(find.byKey(const ValueKey('teach-back')));
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of 10'), findsOneWidget);
    expect(practiced, isFalse);
  });

  testWidgets('keyboard demonstration steps render the passive keyboard',
      (tester) async {
    await tester.pumpWidget(harness(onStartPractice: () {}));
    await tester.pumpAndSettle();

    for (var i = 0; i < 5; i++) {
      await tapNext(tester);
    }
    expect(find.text('Step 6 of 10'), findsOneWidget);
    expect(find.byType(PianoKeyboardView), findsOneWidget);
    expect(find.text('Where are C, E and G on the keyboard?'), findsOneWidget);

    await tapNext(tester);
    expect(find.text('Step 7 of 10'), findsOneWidget);
    expect(find.byType(PianoKeyboardView), findsOneWidget);
    expect(find.text('Right-hand fingering'), findsOneWidget);

    await tapNext(tester);
    expect(find.text('Step 8 of 10'), findsOneWidget);
    expect(find.byType(PianoKeyboardView), findsNothing);
  });

  testWidgets('advancing past the final step hands off to Practice', (tester) async {
    var practiced = false;
    await tester.pumpWidget(harness(onStartPractice: () => practiced = true));
    await tester.pumpAndSettle();

    for (var i = 0; i < 9; i++) {
      await tapNext(tester);
    }
    expect(find.text('Step 10 of 10'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Next'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Start Practice'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Start Practice'));
    await tester.pumpAndSettle();

    expect(practiced, isTrue);
  });

  testWidgets('app-level: opening a lesson enters Teach, completing it enters '
      'Practice', (tester) async {
    await goToLesson(tester);

    expect(find.text('Lesson 1 · C Major'), findsOneWidget);
    expect(find.text('Step 1 of 10'), findsOneWidget);

    for (var i = 0; i < 9; i++) {
      await tapNext(tester);
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Start Practice'));
    await tester.pumpAndSettle();

    // Teach completion transitions into the existing Practice stage.
    expect(find.text('Step 1 of 10'), findsNothing);
    expect(find.text('Practice'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);
  });
}