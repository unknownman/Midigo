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
    return MidiTutorApp(
      discovery: FakeDiscovery(),
      connection: FakeConnection(),
      captureFactory: FakeMidiStream.new,
      progressStore: store,
      clock: FakeClock(DateTime(2025, 1, 1, 9, 0, 0)),
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

  ColoredBox filledBox(WidgetTester tester, String keyName) =>
      tester.widget<ColoredBox>(find.descendant(
        of: find.byKey(ValueKey<String>(keyName)),
        matching: find.byType(ColoredBox),
      ));

  testWidgets('teach view presents C Major right-hand block hand + fingering',
      (tester) async {
    store = InMemoryLessonProgressStore();
    await openLesson(tester, 'Lesson 1 · C Major');

    expect(find.text('Lesson 1 · C Major'), findsOneWidget);
    expect(find.text('C Major · Right Hand · Played together'), findsOneWidget);
    expect(find.text('Target notes: C4, E4, G4'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Right Hand'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Block'), findsOneWidget);
    expect(find.text('Right Hand fingering: 1, 3, 5'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('step-1')), findsNothing);

    for (final pitch in <int>[60, 64, 67]) {
      expect(filledBox(tester, 'key-$pitch').color,
          HandVisualStyle.right.color);
    }
  });

  testWidgets('teach view presents C Major right-hand arpeggio order and steps',
      (tester) async {
    store = InMemoryLessonProgressStore();
    await unlockTarget('major-c-rh-block');
    await openLesson(tester, 'Lesson 2 · C Major');

    expect(find.widgetWithText(Chip, 'Right Hand'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Arpeggio'), findsOneWidget);
    expect(find.text('Right Hand fingering: 1, 2, 3, 5'), findsOneWidget);
    expect(find.text('Played order: C \u2192 E \u2192 G \u2192 C'),
        findsOneWidget);
    for (var step = 1; step <= 4; step++) {
      expect(find.byKey(ValueKey<String>('step-$step')), findsOneWidget);
    }
    expect(filledBox(tester, 'key-67').color, HandVisualStyle.right.color);
  });

  testWidgets('teach view presents C Major left-hand block mirrored fingering',
      (tester) async {
    store = InMemoryLessonProgressStore();
    await unlockTarget('major-c-rh-block');
    await unlockTarget('major-c-rh-arpeggio');
    await openLesson(tester, 'Lesson 3 · C Major');

    expect(find.text('C Major · Left Hand · Played together'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Left Hand'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Block'), findsOneWidget);
    expect(find.text('Left Hand fingering: 5, 3, 1'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('step-1')), findsNothing);
    for (final pitch in <int>[60, 64, 67]) {
      expect(filledBox(tester, 'key-$pitch').color,
          HandVisualStyle.left.color);
    }
  });
}