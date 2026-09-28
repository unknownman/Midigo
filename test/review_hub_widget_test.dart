import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/main.dart';
import 'package:miditutor/practice/application/in_memory_lesson_progress_store.dart';
import 'package:miditutor/practice/application/spaced_review_scheduler.dart';

import 'fakes.dart';

void main() {
  final start = DateTime(2025, 3, 3, 9, 0, 0);

  late FakeClock clock;
  late SpacedReviewScheduler scheduler;
  late FakeConnection connection;
  late FakeMidiStream stream;

  Widget app() {
    return MidiTutorApp(
      discovery: FakeDiscovery(),
      connection: connection,
      captureFactory: () => stream,
      progressStore: InMemoryLessonProgressStore(),
      reviewScheduler: scheduler,
      clock: clock,
    );
  }

  setUp(() {
    clock = FakeClock(start);
    connection = FakeConnection();
    stream = FakeMidiStream();
    scheduler = newFakeReviewScheduler(clock);
  });

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
  }

  Future<void> openHub(WidgetTester tester) async {
    await pumpHome(tester);
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
  }

  group('Review Hub (H2.9.5)', () {
    testWidgets('home reflects the ready count and the hub shows the empty state',
        (WidgetTester tester) async {
      await pumpHome(tester);
      expect(find.text('No reviews due'), findsOneWidget);

      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(find.text("You're all caught up."), findsOneWidget);
      expect(find.byKey(const ValueKey('start-all')), findsNothing);
    });

    testWidgets('a due item appears with every review action',
        (WidgetTester tester) async {
      await makeReviewsReady(scheduler, clock, skillIds: const [
        'major-c-rh-block',
      ]);
      await pumpHome(tester);
      expect(find.text('1 ready'), findsOneWidget);

      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('ready-count')), findsOneWidget);
      expect(find.text('1 review ready'), findsOneWidget);
      expect(find.text('C Major · Right Hand · Played together'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Review'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Start'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Lesson'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Skip for Now'), findsOneWidget);
      expect(find.byKey(const ValueKey('start-all')), findsOneWidget);
    });

    testWidgets('multiple due items render in catalog order',
        (WidgetTester tester) async {
      // Register in non-catalog order; the hub must surface them deterministically.
      await makeReviewsReady(scheduler, clock, skillIds: const [
        'major-c-bothUnison-arpeggio',
        'major-c-rh-block',
        'major-c-rh-arpeggio',
      ]);
      await openHub(tester);

      expect(find.text('3 reviews ready'), findsOneWidget);
      final first = tester.getTopLeft(
          find.text('C Major · Right Hand · Played together')).dy;
      final second = tester.getTopLeft(
          find.text('C Major · Right Hand · Played one at a time')).dy;
      final third = tester
          .getTopLeft(find.text('C Major · Both Hands · Played one at a time'))
          .dy;
      expect(first < second, isTrue);
      expect(second < third, isTrue);
    });

    testWidgets('an item that is not due yet is not surfaced',
        (WidgetTester tester) async {
      await scheduler.registerEligibleSkill('major-c-rh-block');
      await openHub(tester);
      expect(find.text("You're all caught up."), findsOneWidget);
    });

    testWidgets('Start opens ordinary practice and never touches the scheduler',
        (WidgetTester tester) async {
      await makeReviewsReady(scheduler, clock, skillIds: const [
        'major-c-rh-block',
      ]);
      await openHub(tester);

      final before = await scheduler.getState('major-c-rh-block');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Start'));
      await tester.pumpAndSettle();

      expect(find.text('Connect your MIDI keyboard to start.'), findsOneWidget);
      final after = await scheduler.getState('major-c-rh-block');
      expect(after.reviewCount, before.reviewCount);
      expect(after.nextReviewAt, before.nextReviewAt);
      expect(after.reviewEligible, isTrue);
    });

    testWidgets('Lesson opens the normal lesson and never touches the scheduler',
        (WidgetTester tester) async {
      await makeReviewsReady(scheduler, clock, skillIds: const [
        'major-c-rh-block',
      ]);
      await openHub(tester);

      final before = await scheduler.getState('major-c-rh-block');
      await tester.tap(find.widgetWithText(TextButton, 'Lesson'));
      await tester.pumpAndSettle();

      expect(find.text('Step 1 of 10'), findsOneWidget);
      final after = await scheduler.getState('major-c-rh-block');
      expect(after.reviewCount, before.reviewCount);
      expect(after.reviewEligible, isTrue);
    });

    testWidgets('Skip for Now leaves the item due and the scheduler untouched',
        (WidgetTester tester) async {
      await makeReviewsReady(scheduler, clock, skillIds: const [
        'major-c-rh-block',
      ]);
      await openHub(tester);

      final before = await scheduler.getState('major-c-rh-block');
      await tester.tap(find.widgetWithText(TextButton, 'Skip for Now'));
      await tester.pumpAndSettle();

      // Still due, still listed, zero mutation.
      expect(find.text('1 review ready'), findsOneWidget);
      expect(find.text('C Major · Right Hand · Played together'), findsOneWidget);
      final after = await scheduler.getState('major-c-rh-block');
      expect(after.reviewCount, before.reviewCount);
      expect(after.nextReviewAt, before.nextReviewAt);
      expect(after.lastResponse, before.lastResponse);
    });

    testWidgets('Review opens the scheduled review flow',
        (WidgetTester tester) async {
      await makeReviewsReady(scheduler, clock, skillIds: const [
        'major-c-rh-block',
      ]);
      await openHub(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Review'));
      await tester.pumpAndSettle();

      expect(find.text('Review'), findsOneWidget);
      expect(find.text('Review · C Major'), findsOneWidget);
      expect(find.text('Connect your MIDI keyboard to start.'), findsOneWidget);
      expect(find.byKey(const ValueKey('i-already-know')), findsOneWidget);
    });
  });
}