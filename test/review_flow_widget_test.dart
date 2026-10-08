import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/main.dart';
import 'package:miditutor/practice/application/in_memory_lesson_progress_store.dart';
import 'package:miditutor/practice/application/review_scheduler.dart';
import 'package:miditutor/practice/application/spaced_review_scheduler.dart';

import 'fakes.dart';

void main() {
  final start = DateTime(2025, 3, 3, 9, 0, 0);
  const block = 'major-c-rh-block';
  const arpeggio = 'major-c-rh-arpeggio';

  late FakeClock clock;
  late SpacedReviewScheduler scheduler;
  late InMemoryLessonProgressStore store;
  late FakeConnection connection;
  late FakeMidiStream stream;

  Widget app() {
    return MidiTutorApp(
      discovery: FakeDiscovery(),
      connection: connection,
      captureFactory: () => stream,
      progressStore: store,
      reviewScheduler: scheduler,
      clock: clock,
    );
  }

  setUp(() {
    clock = FakeClock(start);
    connection = FakeConnection();
    stream = FakeMidiStream();
    store = InMemoryLessonProgressStore();
    scheduler = newFakeReviewScheduler(clock);
  });

  Future<void> pumpApp(WidgetTester tester) async {
    // A tall test viewport keeps the pinned "I Already Know" button clear of
    // the practice controls inside the scrollable pane, so every attempt is
    // driven deterministically (no occluded taps, no scroll-induced capture
    // races).
    tester.view.physicalSize = const Size(600, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
  }

  Future<void> tapReviewCard(WidgetTester tester) async {
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
  }

  Future<void> openSingleItemFlow(WidgetTester tester) async {
    await makeReviewsReady(scheduler, clock, skillIds: const [block]);
    await pumpApp(tester);
    await tapReviewCard(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Review'));
    await tester.pumpAndSettle();
  }

  Future<void> connect(WidgetTester tester) async {
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

  Future<void> continueReview(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
  }

  /// Connects (or starts an attempt if already connected), plays a perfect
  /// performance ([pushArpeggio] selects the one-at-a-time form for an
  /// arpeggio skill), finishes, and confirms the review with Continue.
  Future<void> playPerfectAndContinue(WidgetTester tester,
      {bool pushArpeggio = false}) async {
    if (find.widgetWithText(FilledButton, 'Connect').evaluate().isNotEmpty) {
      await connect(tester);
    } else {
      final startButton = find.widgetWithText(FilledButton, 'Start Attempt');
      await tester.ensureVisible(startButton);
      await tester.pumpAndSettle();
      await tester.tap(startButton);
      await tester.pumpAndSettle();
    }
    if (pushArpeggio) {
      stream.pushPerfectCMajorArpeggio();
    } else {
      stream.pushPerfectCMajorBlock();
    }
    await tester.pumpAndSettle();
    await finish(tester);
    await continueReview(tester);
  }

  group('Review execution (H2.9.6 - H2.9.9)', () {
    testWidgets('a passing review commits exactly one successful response',
        (WidgetTester tester) async {
      await openSingleItemFlow(tester);
      await connect(tester);

      stream.pushPerfectCMajorBlock();
      await tester.pumpAndSettle();
      await finish(tester);

      expect(find.byKey(const ValueKey('review-stars')), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Continue'), findsOneWidget);

      await continueReview(tester);

      // Hub refreshed and empty; exactly one successful response was committed.
      expect(find.text("You're all caught up."), findsOneWidget);
      final state = await scheduler.getState(block);
      expect(state.reviewCount, 1);
      expect(state.successfulReviewCount, 1);
      expect(state.unsuccessfulReviewCount, 0);
      expect(state.currentIntervalDays, 2);
      expect(state.lastResponse, ReviewResponse.successfulReview);
      expect(state.nextReviewAt,
          clock.current.add(const Duration(days: 2)));
    });

    testWidgets('a 0-star review commits exactly one unsuccessful response',
        (WidgetTester tester) async {
      await openSingleItemFlow(tester);
      await connect(tester);

      stream.pushMessyCMajorBlock();
      await tester.pumpAndSettle();
      await finish(tester);

      expect(find.byKey(const ValueKey('review-stars')), findsOneWidget);
      await continueReview(tester);

      final state = await scheduler.getState(block);
      expect(state.reviewCount, 1);
      expect(state.successfulReviewCount, 0);
      expect(state.unsuccessfulReviewCount, 1);
      expect(state.currentIntervalDays,
          SpacedReviewScheduler.minimumIntervalDays);
      expect(state.lastResponse, ReviewResponse.unsuccessfulReview);
    });

    testWidgets('review never modifies lesson progress (H2.9.10)',
        (WidgetTester tester) async {
      await openSingleItemFlow(tester);
      await connect(tester);

      stream.pushPerfectCMajorBlock();
      await tester.pumpAndSettle();
      await finish(tester);
      await continueReview(tester);

      final progress = await store.read(block);
      expect(progress, isNull);
    });

    testWidgets('retry discards the first candidate; only the final attempt '
        'commits', (WidgetTester tester) async {
      await openSingleItemFlow(tester);
      await connect(tester);

      // Attempt A: messy (0 stars).
      stream.pushMessyCMajorBlock();
      await tester.pumpAndSettle();
      await finish(tester);
      expect(find.byKey(const ValueKey('review-stars')), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
      await tester.pumpAndSettle();

      // Attempt B: perfect (5 stars).
      stream.pushPerfectCMajorBlock();
      await tester.pumpAndSettle();
      await finish(tester);
      await continueReview(tester);

      final state = await scheduler.getState(block);
      expect(state.reviewCount, 1);
      expect(state.successfulReviewCount, 1);
      expect(state.unsuccessfulReviewCount, 0);
      expect(state.lastResponse, ReviewResponse.successfulReview);
    });

    testWidgets('a NEP review changes nothing and the item stays due',
        (WidgetTester tester) async {
      await openSingleItemFlow(tester);
      await connect(tester);
      final before = await scheduler.getState(block);

      await finish(tester);
      expect(find.byKey(const ValueKey('review-nep-message')), findsOneWidget);
      await continueReview(tester);

      final after = await scheduler.getState(block);
      expect(after.reviewCount, before.reviewCount);
      expect(after.successfulReviewCount, before.successfulReviewCount);
      expect(after.unsuccessfulReviewCount, before.unsuccessfulReviewCount);
      expect(after.nextReviewAt, before.nextReviewAt);
      expect(after.lastResponse, before.lastResponse);

      // Still due, still listed on the hub.
      expect(find.text('C Major · Right Hand · Played together'), findsOneWidget);
    });

    testWidgets('leaving without Continue changes nothing and keeps the item '
        'ready', (WidgetTester tester) async {
      await openSingleItemFlow(tester);
      await connect(tester);
      final before = await scheduler.getState(block);

      stream.pushPerfectCMajorBlock();
      await tester.pumpAndSettle();
      await finish(tester);
      expect(find.byKey(const ValueKey('review-stars')), findsOneWidget);

      // Learner backs out instead of committing.
      await tester.pageBack();
      await tester.pumpAndSettle();

      final after = await scheduler.getState(block);
      expect(after.reviewCount, before.reviewCount);
      expect(after.successfulReviewCount, before.successfulReviewCount);
      expect(after.lastResponse, before.lastResponse);
      expect(find.text('C Major · Right Hand · Played together'), findsOneWidget);
    });

    testWidgets('I Already Know commits without practicing and never touches '
        'counts', (WidgetTester tester) async {
      await openSingleItemFlow(tester);
      // Not connected: I Already Know is available pre-attempt.
      await tester.tap(find.byKey(const ValueKey('i-already-know')));
      await tester.pumpAndSettle();
      expect(find.text('I Already Know'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('confirm-i-already-know')));
      await tester.pumpAndSettle();

      expect(find.text("You're all caught up."), findsOneWidget);
      final state = await scheduler.getState(block);
      expect(state.lastResponse, ReviewResponse.iAlreadyKnow);
      expect(state.reviewCount, 0);
      expect(state.successfulReviewCount, 0);
      expect(state.unsuccessfulReviewCount, 0);
      expect(state.currentIntervalDays,
          SpacedReviewScheduler.minimumIntervalDays);
      // Not due again yet: next review is a full interval away.
      expect(state.nextReviewAt,
          clock.current.add(const Duration(days: 1)));
    });
  });

  group('Start All (H2.9.11)', () {
    testWidgets('reviews every due item in one session, in catalog order',
        (WidgetTester tester) async {
      // Register in reverse catalog order; Start All must still process
      // block first, then arpeggio.
      await makeReviewsReady(scheduler, clock, skillIds: const [
        arpeggio,
        block,
      ]);
      await pumpApp(tester);
      await tapReviewCard(tester);
      await tester.tap(find.byKey(const ValueKey('start-all')));
      await tester.pumpAndSettle();

      // Item 1 (block), namespaced by exercise context.
      expect(find.text('Review · C Major'), findsOneWidget);
      await playPerfectAndContinue(tester);

      // Item 2 (arpeggio) follows in the same session; an arpeggio skill is
      // practiced by playing the notes one at a time.
      expect(find.text('Review · C Major'), findsOneWidget);
      await playPerfectAndContinue(tester, pushArpeggio: true);

      expect(find.text("You're all caught up."), findsOneWidget);
      final blockState = await scheduler.getState(block);
      final arpeggioState = await scheduler.getState(arpeggio);
      expect(blockState.successfulReviewCount, 1);
      expect(arpeggioState.successfulReviewCount, 1);
      expect(blockState.nextReviewAt, clock.current.add(const Duration(days: 2)));
      expect(arpeggioState.nextReviewAt,
          clock.current.add(const Duration(days: 2)));
    });
  });
}