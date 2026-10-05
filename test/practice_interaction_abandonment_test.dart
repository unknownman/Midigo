import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/main.dart';
import 'package:miditutor/midi/application/expected_musical_target_factory.dart';
import 'package:miditutor/midi/domain/evaluation_result.dart';
import 'package:miditutor/midi/domain/expected_musical_target.dart';
import 'package:miditutor/practice/application/evaluation_flow.dart';
import 'package:miditutor/practice/application/evidence_aggregation_service.dart';
import 'package:miditutor/practice/application/evidence_store.dart';
import 'package:miditutor/practice/application/in_memory_lesson_progress_store.dart';
import 'package:miditutor/practice/application/lesson_progress_service.dart';
import 'package:miditutor/practice/application/practice_session_controller.dart';
import 'package:miditutor/practice/application/spaced_review_scheduler.dart';
import 'package:miditutor/practice/domain/attempt.dart';
import 'package:miditutor/practice/domain/evidence.dart';
import 'package:miditutor/practice/domain/practice_exercise.dart';
import 'package:miditutor/practice/domain/practice_interaction.dart';
import 'package:miditutor/ui/lesson/practice_view.dart';

import 'fakes.dart';

/// H2.13 - Practice Interaction exit & abandonment lifecycle.
///
/// A Practice Interaction is one learner-facing engagement (RT-002). It can end
/// in exactly two ways (RT-004): the learner finished it (`completed`), or the
/// learner left it (`abandoned`). Before this phase the second end reason was
/// modeled but unreachable, and a session disposed with an open interaction left
/// that interaction open forever - so Evidence could never obtain EVG-019's
/// `earlierInteraction.ended_at` operand and every later interaction stayed
/// dependent with it.
///
/// These tests drive the real [PracticeSessionController] and the real screens
/// over a deterministic [FakeClock]. They assert lifecycle and observable
/// effects only; identity is never asserted, and no Evidence contract, scheduler
/// contract, or identity rule is exercised or changed here.
void main() {
  final base = DateTime(2025, 5, 1, 10, 0, 0);

  const blockId = 'major-c-rh-block';
  const arpeggioId = 'major-c-rh-arpeggio';

  ExpectedMusicalTarget targetFor(String targetId, TargetMode mode) =>
      const ExpectedMusicalTargetFactory().build(
        quality: TargetQuality.major,
        root: TargetRoot.c,
        hand: TargetHand.right,
        mode: mode,
        targetId: targetId,
      );

  final blockTarget = targetFor(blockId, TargetMode.block);
  final arpeggioTarget = targetFor(arpeggioId, TargetMode.arpeggio);

  PracticeExercise exerciseFor(String targetId) => PracticeExercise(
        id: 'lesson-$targetId.exercise.01',
        order: 1,
        title: 'Guided Practice',
        targetId: targetId,
      );

  late FakeClock clock;
  late FakeConnection connection;
  late FakeMidiStream stream;
  late InMemoryLessonProgressStore progressStore;
  late SpacedReviewScheduler scheduler;
  late EvidenceStore evidenceStore;

  setUp(() {
    clock = FakeClock(base);
    connection = FakeConnection();
    stream = FakeMidiStream();
    progressStore = InMemoryLessonProgressStore();
    scheduler = newFakeReviewScheduler(clock);
    evidenceStore = InMemoryEvidenceStore();
  });

  PracticeSessionController buildController({
    required String targetId,
    required ExpectedMusicalTarget target,
    bool recordLessonProgress = true,
  }) {
    return PracticeSessionController(
      discovery: FakeDiscovery(),
      connection: connection,
      captureFactory: () => stream,
      evaluation: const EvaluationFlowService(),
      progressService: LessonProgressService(store: progressStore),
      clock: clock,
      exercise: exerciseFor(targetId),
      targetFactory: (_) => target,
      recordLessonProgress: recordLessonProgress,
      evidenceAggregator: PracticeEvidenceAggregator(
        store: evidenceStore,
        clock: clock,
      ),
    );
  }

  /// Connects and opens an interaction with one armed Attempt.
  Future<PracticeSessionController> engage({
    required String targetId,
    required ExpectedMusicalTarget target,
    bool recordLessonProgress = true,
  }) async {
    final controller = buildController(
      targetId: targetId,
      target: target,
      recordLessonProgress: recordLessonProgress,
    );
    await controller.connect(FakeDiscovery().sources.first);
    await controller.startAttempt();
    return controller;
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  // ---------------------------------------------------------------------------
  // Controller lifecycle
  // ---------------------------------------------------------------------------

  group('H2.13.1 / H2.13.4 abandonment ends the engagement', () {
    test('abandonAttempt ends the open interaction and reports one window to '
        'Evidence', () async {
      final controller = await engage(
        targetId: blockId,
        target: blockTarget,
      );
      expect(controller.runtime.hasOpenInteraction, isTrue);

      await controller.abandonAttempt();

      expect(controller.runtime.hasOpenInteraction, isFalse);
      final windows = controller.evidence.state.interactionWindows;
      expect(windows, hasLength(1));
      expect(windows.single.isOpen, isFalse);
    });

    test('the end reason is abandoned and the Attempt is abandoned, never '
        'failed or completed', () async {
      final controller = await engage(
        targetId: blockId,
        target: blockTarget,
      );

      await controller.abandonAttempt();

      expect(controller.runtime.currentInteraction!.endReason,
          PracticeInteractionEndReason.abandoned);
      final attempt =
          controller.runtime.currentItems.first.attempts.single;
      expect(attempt.state, AttemptState.abandoned);
      expect(attempt.endedAt, isNotNull);
    });

    test('the end is stamped from the PracticeClock, never the wall clock',
        () async {
      final controller = await engage(
        targetId: blockId,
        target: blockTarget,
      );
      expect(controller.runtime.currentInteraction!.startedAt, base);

      final abandonedAt = base.add(const Duration(seconds: 4));
      clock.current = abandonedAt;
      await controller.abandonAttempt();

      expect(controller.runtime.currentInteraction!.endedAt, abandonedAt);
      final window =
          controller.evidence.state.interactionWindow('pi-$blockId')!;
      expect(window.startedAt, base);
      expect(window.endedAt, abandonedAt);
    });

    test('an abandoned attempt never grades: no result, no stars, no evidence '
        'contribution', () async {
      final controller = await engage(
        targetId: blockId,
        target: blockTarget,
      );
      stream.pushPerfectCMajorBlock();
      await settle();

      await controller.abandonAttempt();

      final attempt = controller.runtime.currentItems.first.attempts.single;
      expect(attempt.evaluationResult, isNull);
      expect(controller.session.value.latestCompletedResult, isNull);
      expect(controller.session.value.currentStars, 0);
      expect(controller.evidence.state.contributions, isEmpty);
    });

    test('MIDI capture stops before the interaction is ended', () async {
      final controller = await engage(
        targetId: blockId,
        target: blockTarget,
      );
      expect(controller.isCapturing, isTrue);

      await controller.abandonAttempt();

      expect(controller.isCapturing, isFalse,
          reason: 'no event arriving after abandonment may reach the attempt');
      expect(controller.runtime.hasOpenInteraction, isFalse);
    });

    test('abandonment does not mutate LessonProgress', () async {
      final controller = await engage(
        targetId: blockId,
        target: blockTarget,
      );
      stream.pushPerfectCMajorBlock();
      await settle();

      await controller.abandonAttempt();

      expect(await progressStore.read(blockId), isNull,
          reason: 'an abandoned engagement creates no attempt record at all');
    });
  });

  group('H2.13.3 disposal safety is idempotent', () {
    test('dispose abandons an interaction that is still open', () async {
      final controller = await engage(
        targetId: blockId,
        target: blockTarget,
      );

      final disposedAt = base.add(const Duration(seconds: 4));
      clock.current = disposedAt;
      controller.dispose();

      expect(controller.runtime.hasOpenInteraction, isFalse);
      expect(controller.runtime.currentInteraction!.endReason,
          PracticeInteractionEndReason.abandoned);
      expect(controller.runtime.currentInteraction!.endedAt, disposedAt);
      expect(
        controller.evidence.state.interactionWindow('pi-$blockId')!.endedAt,
        disposedAt,
      );
    });

    test('dispose is a no-op when no interaction was ever opened', () async {
      final controller = buildController(
        targetId: blockId,
        target: blockTarget,
      );

      controller.dispose();

      expect(controller.runtime.currentInteraction, isNull);
      expect(controller.evidence.state.interactionWindows, isEmpty);
    });

    test('dispose does not rewrite a completed interaction', () async {
      final controller = await engage(
        targetId: blockId,
        target: blockTarget,
      );
      stream.pushPerfectCMajorBlock();
      await settle();
      await controller.endAttempt();

      final completedAt = base.add(const Duration(seconds: 2));
      clock.current = completedAt;
      controller.completeInteraction();
      controller.dispose();

      expect(controller.runtime.currentInteraction!.endReason,
          PracticeInteractionEndReason.completed,
          reason: 'disposal must never downgrade a completion');
      expect(
        controller.evidence.state.interactionWindow('pi-$blockId')!.endedAt,
        completedAt,
      );
      expect(controller.evidence.state.interactionWindows, hasLength(1));
    });

    test('dispose does not end an interaction that was already abandoned',
        () async {
      final controller = await engage(
        targetId: blockId,
        target: blockTarget,
      );
      final abandonedAt = base.add(const Duration(seconds: 4));
      clock.current = abandonedAt;
      await controller.abandonAttempt();

      clock.current = base.add(const Duration(minutes: 30));
      controller.dispose();

      expect(
        controller.evidence.state.interactionWindow('pi-$blockId')!.endedAt,
        abandonedAt,
        reason: 'the first end wins (EVG-021: a window is never rewritten)',
      );
      expect(controller.evidence.state.interactionWindows, hasLength(1));
    });

    test('repeated abandon then dispose yields exactly one interaction end',
        () async {
      final controller = await engage(
        targetId: blockId,
        target: blockTarget,
      );

      final abandonedAt = base.add(const Duration(seconds: 4));
      clock.current = abandonedAt;
      await controller.abandonAttempt();
      await controller.abandonAttempt();
      controller.dispose();

      final windows = controller.evidence.state.interactionWindows;
      expect(windows, hasLength(1), reason: 'no duplicate end');
      expect(windows.single.endedAt, abandonedAt);
      expect(
        identical(controller.evidence.state.interactionWindows.single, windows.single),
        isTrue,
        reason: 'the stored window is immutable and never re-created',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // H2.13 / §16-§18 the temporal operand an abandonment supplies
  // ---------------------------------------------------------------------------

  group('abandonment supplies EVG-019\'s second gap operand', () {
    test('a later interaction can now calculate the gap after an earlier '
        'abandonment', () async {
      // Interaction A: starts at 1000 ms, abandoned at 5000 ms.
      clock.current = base.add(const Duration(milliseconds: 1000));
      final a = await engage(targetId: blockId, target: blockTarget);
      expect(a.runtime.currentInteraction!.startedAt,
          base.add(const Duration(milliseconds: 1000)));

      clock.current = base.add(const Duration(seconds: 5));
      a.dispose();
      final aWindow = a.evidence.state.interactionWindow('pi-$blockId')!;

      // Interaction B: starts at 10000 ms, i.e. 5000 ms after A ended.
      clock.current = base.add(const Duration(seconds: 10));
      final b = await engage(targetId: arpeggioId, target: arpeggioTarget);
      addTearDown(b.dispose);

      expect(b.evidence.state.interactionWindow('pi-$arpeggioId'), isNull,
          reason: 'B is still open: it supplies only its own start');

      final bStart = b.runtime.currentInteraction!.startedAt;
      expect(aWindow.endedAt, isNotNull,
          reason: 'the earlier operand exists only once the interaction ended');
      expect(bStart.difference(aWindow.endedAt!), const Duration(seconds: 5));
    });

    test('the 15-minute independence boundary is unchanged by abandonment',
        () async {
      final a = await engage(targetId: blockId, target: blockTarget);
      clock.current = base.add(const Duration(seconds: 5));
      a.dispose();
      final aWindow = a.evidence.state.interactionWindow('pi-$blockId')!;

      // Gap of exactly 15:00 -> INDEPENDENT (EVG-008, boundary inclusive).
      clock.current = base.add(const Duration(minutes: 15, seconds: 5));
      final b = await engage(targetId: arpeggioId, target: arpeggioTarget);
      addTearDown(b.dispose);
      final bStart = b.runtime.currentInteraction!.startedAt;

      expect(bStart.difference(aWindow.endedAt!),
          const Duration(minutes: 15));
      expect(
        EvidenceAggregation.classify(
          earlier: aWindow,
          later: EvidenceInteractionWindow(
            practiceInteractionId: 'pi-$arpeggioId',
            startedAt: bStart,
          ),
        ),
        EvidenceDependency.independent,
      );
    });

    test('a gap below 15 minutes after an abandonment stays dependent',
        () async {
      final a = await engage(targetId: blockId, target: blockTarget);
      clock.current = base.add(const Duration(seconds: 5));
      a.dispose();
      final aWindow = a.evidence.state.interactionWindow('pi-$blockId')!;

      clock.current = base.add(const Duration(minutes: 14, seconds: 5));
      final b = await engage(targetId: arpeggioId, target: arpeggioTarget);
      addTearDown(b.dispose);
      final bStart = b.runtime.currentInteraction!.startedAt;

      expect(
        EvidenceAggregation.classify(
          earlier: aWindow,
          later: EvidenceInteractionWindow(
            practiceInteractionId: 'pi-$arpeggioId',
            startedAt: bStart,
          ),
        ),
        EvidenceDependency.dependent,
      );
    });
  });

  group('H2.13 the completion path is unchanged', () {
    test('Finish -> Result -> Continue still ends the interaction completed',
        () async {
      final controller = await engage(
        targetId: blockId,
        target: blockTarget,
      );
      stream.pushPerfectCMajorBlock();
      await settle();
      await controller.endAttempt();

      expect(controller.session.value.latestCompletedResult,
          isA<EvaluatedResult>());
      expect(controller.session.value.currentStars, 5);

      final completedAt = base.add(const Duration(seconds: 2));
      clock.current = completedAt;
      controller.completeInteraction();

      expect(controller.runtime.currentInteraction!.endReason,
          PracticeInteractionEndReason.completed);
      expect(
        controller.evidence.state.interactionWindow('pi-$blockId')!.endedAt,
        completedAt,
      );
      // Completing really did grade: unlike abandonment, it records progress.
      expect((await progressStore.read(blockId))!.stars, 5);
    });

    test('completed and abandoned engagements stay distinguishable',
        () async {
      final completed = await engage(
        targetId: blockId,
        target: blockTarget,
      );
      stream.pushPerfectCMajorBlock();
      await settle();
      await completed.endAttempt();
      completed.completeInteraction();

      final abandoned = await engage(
        targetId: arpeggioId,
        target: arpeggioTarget,
      );
      await abandoned.abandonAttempt();

      expect(completed.runtime.currentInteraction!.endReason,
          PracticeInteractionEndReason.completed);
      expect(abandoned.runtime.currentInteraction!.endReason,
          PracticeInteractionEndReason.abandoned);
    });
  });

  // ---------------------------------------------------------------------------
  // H2.13.2 exit-by-back, through the real screens
  // ---------------------------------------------------------------------------

  group('H2.13.2 a learner exit abandons the engagement', () {
    Widget app() => MidiTutorApp(
          discovery: FakeDiscovery(),
          connection: connection,
          captureFactory: () => stream,
          progressStore: progressStore,
          reviewScheduler: scheduler,
          clock: clock,
        );

    Future<void> pumpHome(WidgetTester tester) async {
      tester.view.physicalSize = const Size(600, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
    }

    Future<void> back(WidgetTester tester) async {
      await tester.runAsync(() async {
        await tester.tap(find.byType(BackButton));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
    }

    Future<void> startAttemptFromPractice(WidgetTester tester) async {
      if (find.widgetWithText(FilledButton, 'Connect').evaluate().isNotEmpty) {
        await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
        await tester.pumpAndSettle();
        return;
      }
      final startButton = find.widgetWithText(FilledButton, 'Start Attempt');
      await tester.ensureVisible(startButton);
      await tester.pumpAndSettle();
      await tester.tap(startButton);
      await tester.pumpAndSettle();
    }

    /// The live controller of the practice surface currently on screen. Captured
    /// before the exit, because the route - and with it the widget - is gone
    /// afterwards while the controller object itself survives.
    PracticeSessionController liveController(WidgetTester tester) =>
        tester.widget<PracticeView>(find.byType(PracticeView)).controller;

    Future<void> openLessonPractice(WidgetTester tester) async {
      await pumpHome(tester);
      await tester.tap(find.text('Learning Path'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lesson 1 · C Major'));
      await tester.pumpAndSettle();
      while (find.widgetWithText(FilledButton, 'Next').evaluate().isNotEmpty) {
        await tester.tap(find.widgetWithText(FilledButton, 'Next'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.widgetWithText(FilledButton, 'Start Practice'));
      await tester.pumpAndSettle();
      await startAttemptFromPractice(tester);
    }

    Future<void> openReviewSession(WidgetTester tester) async {
      await makeReviewsReady(scheduler, clock, skillIds: const [blockId]);
      await pumpHome(tester);
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Review'));
      await tester.pumpAndSettle();
      await startAttemptFromPractice(tester);
    }

    Future<void> openNormalPractice(WidgetTester tester) async {
      await makeReviewsReady(scheduler, clock, skillIds: const [blockId]);
      await pumpHome(tester);
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Start'));
      await tester.pumpAndSettle();
      await startAttemptFromPractice(tester);
    }

    testWidgets('Lesson: Back abandons the open interaction and records no '
        'progress', (WidgetTester tester) async {
      await openLessonPractice(tester);
      final controller = liveController(tester);
      expect(controller.runtime.hasOpenInteraction, isTrue);

      await back(tester);

      expect(controller.runtime.hasOpenInteraction, isFalse);
      expect(controller.runtime.currentInteraction!.endReason,
          PracticeInteractionEndReason.abandoned);
      expect(controller.evidence.state.interactionWindow('pi-$blockId'),
          isNotNull);
      expect(await progressStore.read(blockId), isNull,
          reason: 'leaving a lesson never creates lesson progress');
      expect(find.text('Learning Path'), findsOneWidget);
    });

    testWidgets('Lesson: Back from the Result stage is still an abandonment, '
        'never a completion', (WidgetTester tester) async {
      await openLessonPractice(tester);
      final controller = liveController(tester);

      stream.pushPerfectCMajorBlock();
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Finish Practice'));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(find.text('Result'), findsOneWidget);

      await back(tester);

      expect(controller.runtime.currentInteraction!.endReason,
          PracticeInteractionEndReason.abandoned,
          reason: 'a Back navigation is never converted into a completion');
    });

    testWidgets('Normal Practice: Back abandons and mutates neither the '
        'scheduler nor lesson progress', (WidgetTester tester) async {
      await openNormalPractice(tester);
      final controller = liveController(tester);
      final before = await scheduler.getState(blockId);

      await back(tester);

      expect(controller.runtime.currentInteraction!.endReason,
          PracticeInteractionEndReason.abandoned);
      expect(await progressStore.read(blockId), isNull);
      final after = await scheduler.getState(blockId);
      expect(after.reviewCount, before.reviewCount);
      expect(after.currentIntervalDays, before.currentIntervalDays);
      expect(after.nextReviewAt, before.nextReviewAt);
      expect(after.lastResponse, before.lastResponse);
    });

    testWidgets('Review: Back abandons the interaction, commits nothing, and '
        'leaves the item ready', (WidgetTester tester) async {
      await openReviewSession(tester);
      final controller = liveController(tester);
      final before = await scheduler.getState(blockId);
      expect(before.reviewEligible, isTrue);

      await back(tester);

      expect(controller.runtime.currentInteraction!.endReason,
          PracticeInteractionEndReason.abandoned);
      expect(controller.evidence.state.interactionWindow('pi-$blockId'),
          isNotNull);

      final after = await scheduler.getState(blockId);
      expect(after.reviewCount, 0);
      expect(after.successfulReviewCount, 0);
      expect(after.unsuccessfulReviewCount, 0);
      expect(after.currentIntervalDays, before.currentIntervalDays);
      expect(after.nextReviewAt, before.nextReviewAt);
      expect(after.lastResponse, isNull);

      // Still due: the hub keeps listing it.
      expect(find.byKey(const ValueKey('ready-count')), findsOneWidget);
      expect(find.text('1 review ready'), findsOneWidget);
    });
  });
}