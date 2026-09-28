import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/main.dart';
import 'package:miditutor/midi/domain/evaluation_result.dart';
import 'package:miditutor/practice/application/in_memory_lesson_progress_store.dart';
import 'package:miditutor/practice/application/lesson_progress_service.dart';
import 'package:miditutor/ui/widgets/hand_visual_style.dart';

import 'fakes.dart';

void main() {
  late InMemoryLessonProgressStore store;

  Widget app() {
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

  Future<void> unlockTarget(String targetId) async {
    final service = LessonProgressService(store: store);
    for (var i = 0; i < 2; i++) {
      await service.recordResult(
        targetId: targetId,
        result: EvaluatedResult(stars: 5, dimensions: const []),
      );
    }
  }

  Future<void> openLesson(WidgetTester tester, String label) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Learning Path'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> tapNext(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
  }

  Future<void> advanceToStep(WidgetTester tester, int step) async {
    for (var i = 1; i < step; i++) {
      await tapNext(tester);
    }
    expect(find.text('Step $step of 10'), findsOneWidget);
  }

  ColoredBox filledBox(WidgetTester tester, String keyName) =>
      tester.widget<ColoredBox>(find.descendant(
        of: find.byKey(ValueKey<String>(keyName)),
        matching: find.byType(ColoredBox),
      ));

  testWidgets('teach wizard shows C Major right-hand block hand + fingering',
      (tester) async {
    store = InMemoryLessonProgressStore();
    await openLesson(tester, 'Lesson 1 · C Major');

    expect(find.text('Lesson 1 · C Major'), findsOneWidget);
    expect(find.text('C Major · Right Hand · Played together'), findsOneWidget);
    expect(find.text('Step 1 of 10'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Right Hand'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Block'), findsOneWidget);
    expect(find.text('Target notes: C4, E4, G4'), findsNothing);

    await advanceToStep(tester, 6);

    expect(find.text('Where are C, E and G on the keyboard?'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('step-1')), findsNothing);
    for (final pitch in <int>[60, 64, 67]) {
      expect(filledBox(tester, 'key-$pitch').color,
          HandVisualStyle.right.color);
    }

    await tapNext(tester);

    expect(find.text('Right-hand fingering'), findsOneWidget);
    expect(find.textContaining('thumb (1) on C'), findsOneWidget);
    expect(find.textContaining('middle finger (3) on E'), findsOneWidget);
    expect(find.textContaining('pinky (5) on G'), findsOneWidget);
    expect(find.textContaining('Play all three together.'), findsOneWidget);
  });

  testWidgets('teach wizard shows C Major right-hand arpeggio order and steps',
      (tester) async {
    store = InMemoryLessonProgressStore();
    await unlockTarget('major-c-rh-block');
    await openLesson(tester, 'Lesson 2 · C Major');

    expect(find.text('Step 1 of 10'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Right Hand'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Arpeggio'), findsOneWidget);

    await advanceToStep(tester, 6);

    for (var step = 1; step <= 4; step++) {
      expect(find.byKey(ValueKey<String>('step-$step')), findsOneWidget);
    }
    expect(filledBox(tester, 'key-67').color, HandVisualStyle.right.color);
    expect(filledBox(tester, 'key-72').color, HandVisualStyle.right.color);

    await tapNext(tester);

    expect(find.textContaining('index finger (2) on E'), findsOneWidget);
    expect(find.textContaining('middle finger (3) on G'), findsOneWidget);
    expect(find.textContaining('pinky (5) on C'), findsOneWidget);
    expect(find.textContaining('Play the notes in order.'), findsOneWidget);
  });

  testWidgets('teach wizard shows C Major left-hand block mirrored fingering',
      (tester) async {
    store = InMemoryLessonProgressStore();
    await unlockTarget('major-c-rh-block');
    await unlockTarget('major-c-rh-arpeggio');
    await openLesson(tester, 'Lesson 3 · C Major');

    expect(find.text('C Major · Left Hand · Played together'), findsOneWidget);
    expect(find.text('Step 1 of 10'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Left Hand'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Block'), findsOneWidget);

    await advanceToStep(tester, 6);

    expect(find.byKey(const ValueKey<String>('step-1')), findsNothing);
    for (final pitch in <int>[60, 64, 67]) {
      expect(filledBox(tester, 'key-$pitch').color,
          HandVisualStyle.left.color);
    }

    await tapNext(tester);

    expect(find.textContaining('pinky (5) on C'), findsOneWidget);
    expect(find.textContaining('thumb (1) on G'), findsOneWidget);
    expect(find.textContaining('Play all notes together.'), findsOneWidget);
  });
}