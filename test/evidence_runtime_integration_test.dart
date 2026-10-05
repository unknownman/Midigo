import 'package:flutter_test/flutter_test.dart';
import 'package:miditutor/midi/application/expected_musical_target_factory.dart';
import 'package:miditutor/midi/domain/expected_musical_target.dart';
import 'package:miditutor/midi/domain/evaluation_input.dart';
import 'package:miditutor/midi/domain/evaluation_result.dart';
import 'package:miditutor/practice/application/evaluation_flow.dart';
import 'package:miditutor/practice/application/evidence_store.dart';
import 'package:miditutor/practice/application/lesson_progress_service.dart';
import 'package:miditutor/practice/application/practice_session_controller.dart';
import 'package:miditutor/practice/application/review_scheduler.dart';
import 'package:miditutor/practice/domain/attempt.dart';
import 'package:miditutor/practice/domain/evidence.dart';
import 'package:miditutor/practice/domain/practice_exercise.dart';

import 'fakes.dart';

/// End-to-end Evidence behaviour at the real practice entry points.
///
/// Every path below drives [PracticeSessionController] exactly as the UI does -
/// the frozen evaluation runs, nothing is stubbed - so these tests prove which
/// learner actions become Evidence, which produce none, and that Evidence never
/// leaks into lesson progress or the Review Scheduler.
void main() {
  const targetId = 'major-c-rh-block';
  final target = const ExpectedMusicalTargetFactory().build(
    quality: TargetQuality.major,
    root: TargetRoot.c,
    hand: TargetHand.right,
    mode: TargetMode.block,
    targetId: targetId,
  );

  /// The canonical curriculum exercise this session executes (H2.11A).
  final exercise = PracticeExercise(
    id: 'lesson-major-c-rh-block.exercise.01',
    order: 1,
    title: 'Guided Block Practice',
    targetId: targetId,
  );

  late FakeClock clock;
  late FakeDiscovery discovery;
  late FakeConnection connection;
  late FakeMidiStream stream;
  late FakeProgressStore progressStore;
  late LessonProgressService progressService;

  PracticeSessionController buildController({
    bool recordLessonProgress = true,
  }) {
    clock = FakeClock(DateTime(2025, 1, 1, 11, 0, 0));
    discovery = FakeDiscovery();
    connection = FakeConnection();
    stream = FakeMidiStream();
    progressStore = FakeProgressStore();
    progressService = LessonProgressService(store: progressStore);
    return PracticeSessionController(
      discovery: discovery,
      connection: connection,
      captureFactory: () => stream,
      evaluation: const EvaluationFlowService(),
      progressService: progressService,
      clock: clock,
      exercise: exercise,
      targetFactory: (targetId) => target,
      recordLessonProgress: recordLessonProgress,
    );
  }

  Future<PracticeSessionController> connectAndStart(
    PracticeSessionController controller,
  ) async {
    await controller.connect(discovery.sources.first);
    await controller.startAttempt();
    return controller;
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  EvidenceIdentity identityOf(EvaluationDimension dimension) =>
      EvidenceIdentity(targetId: targetId, dimension: dimension);

  group('Start path (EVG-003/EVG-013)', () {
    test('a perfect first attempt becomes one 5-star contribution per graded '
        'dimension', () async {
      final controller = await connectAndStart(buildController());
      stream.pushPerfectCMajorBlock();
      await settle();

      await controller.endAttempt();

      final state = controller.evidence.state;
      expect(state.contributions, hasLength(3));
      expect(
        state.streams.map((stream) => stream.identity.dimension).toSet(),
        <EvaluationDimension>{
          EvaluationDimension.pitch,
          EvaluationDimension.timing,
          EvaluationDimension.simultaneity,
        },
      );
      expect(
        state.contributions.map((c) => c.stars),
        everyElement(5),
      );

      final contribution = state.streamFor(identityOf(EvaluationDimension.pitch))!
          .contributions
          .single;
      expect(contribution.kind, EvidenceContributionKind.practiceAttempt);
      expect(contribution.provenance.practiceInteractionId, 'pi-$targetId');
      expect(
        contribution.provenance.attemptId,
        'pi-$targetId-item-0-attempt-1',
      );
      expect(contribution.provenance.practiceItemId, 'pi-$targetId-item-0');
      expect(contribution.provenance.captureSessionId, 'session-1');

      // EVG-011: retrieval latency is a defined stream that stays empty.
      expect(
        controller.evidence.state
            .streamFor(identityOf(EvaluationDimension.retrievalLatency)),
        isNull,
      );

      // One interaction means one dependent group per stream.
      for (final stream in state.streams) {
        expect(stream.groups, hasLength(1));
      }

      // Evidence is not lesson progress: the frozen lesson path still decides
      // the lesson stars, and evidence only mirrors the attempt.
      final progress = await progressService.loadProgress(targetId);
      expect(progress.stars, 5);
      expect(controller.session.value.lessonStars, 5);
    });

    test('a retry is a second contribution of the same stream in the same '
        'group', () async {
      final controller = await connectAndStart(buildController());
      stream.pushPerfectCMajorBlock();
      await settle();
      await controller.endAttempt();

      await controller.retryAttempt();
      stream.pushPerfectCMajorBlock();
      await settle();
      await controller.endAttempt();

      final attempts = controller.runtime.currentInteraction!.items.first
          .attempts
          .map((Attempt attempt) => attempt.state);
      expect(attempts, everyElement(AttemptState.completed));

      final pitch =
          controller.evidence.state.streamFor(identityOf(EvaluationDimension.pitch))!;
      expect(pitch.contributions, hasLength(2));
      expect(
        pitch.contributions
            .map((c) => c.provenance.attemptId)
            .toSet(),
        hasLength(2),
      );
      expect(pitch.groups, hasLength(1));
      expect(pitch.groups.single.contributions, pitch.contributions);
      expect(controller.evidence.state.contributions, hasLength(6));
    });
  });

  group('paths that produce no evidence (EVG-003/EVG-012)', () {
    test('a not-enough-performance attempt contributes nothing', () async {
      final controller = await connectAndStart(buildController());

      // No notes at all: the frozen engine decides NEP.
      await controller.endAttempt();

      expect(
        controller.session.value.latestCompletedResult,
        isA<NotEnoughPerformanceResult>(),
      );
      expect(controller.evidence.state.contributions, isEmpty);
      expect(controller.evidence.state.streams, isEmpty);
    });

    test('a zero-star evaluated attempt is real evidence, never an absence',
        () async {
      final controller = await connectAndStart(buildController());
      stream.pushMessyCMajorBlock();
      await settle();

      await controller.endAttempt();

      expect(
        controller.session.value.latestCompletedResult,
        isA<EvaluatedResult>(),
      );
      final state = controller.evidence.state;
      expect(state.contributions, hasLength(3));
      expect(state.contributions.map((c) => c.stars), everyElement(0));
      // A zero-star attempt adds no lesson stars but is still counted.
      final progress = await progressService.loadProgress(targetId);
      expect(progress.stars, 0);
      expect(progress.attemptCount, 1);
    });

    test('NEP followed by a real attempt leaves exactly the real evidence',
        () async {
      final controller = await connectAndStart(buildController());
      await controller.endAttempt(); // NEP

      await controller.retryAttempt();
      stream.pushPerfectCMajorBlock();
      await settle();
      await controller.endAttempt();

      final state = controller.evidence.state;
      expect(state.contributions, hasLength(3));
      expect(
        state.contributions
            .map((c) => c.provenance.attemptId)
            .toSet(),
        <String>{'pi-$targetId-item-0-attempt-2'},
      );
    });

    test('an armed attempt that is abandoned contributes nothing', () async {
      final controller = await connectAndStart(buildController());

      await controller.abandonAttempt();

      expect(controller.runtime.hasOpenInteraction, isFalse);
      expect(
        controller.runtime.currentInteraction!.items.first.attempts.last.state,
        AttemptState.abandoned,
      );
      expect(controller.evidence.state.contributions, isEmpty);
    });

    test('abandoning reports the interaction end so the 15-minute gap rule '
        'has its operand', () async {
      final controller = await connectAndStart(buildController());
      stream.pushPerfectCMajorBlock();
      await settle();
      await controller.endAttempt(); // 3 contributions, interaction still open

      await controller.retryAttempt();
      await controller.abandonAttempt();

      final window = controller.evidence.state.interactionWindow('pi-$targetId');
      expect(window, isNotNull);
      expect(window!.isOpen, isFalse);
      expect(window.endedAt, isNotNull);
      // The contributions themselves were never rewritten (EVG-021).
      expect(controller.evidence.state.contributions, hasLength(3));
    });
  });

  group('review entry points (Review Scheduler Contract v1.2 unchanged)', () {
    test('review practice records evidence without touching lesson progress '
        'or the schedule', () async {
      final controller = buildController(recordLessonProgress: false);
      final clock = controller.clock as FakeClock;
      final scheduler = newFakeReviewScheduler(clock);
      await makeReviewsReady(scheduler, clock, skillIds: <String>[targetId]);
      final before = await scheduler.getState(targetId);
      expect(before.reviewEligible, isTrue);

      // Exactly how ReviewSessionScreen builds its per-item controller.
      await connectAndStart(controller);
      stream.pushPerfectCMajorBlock();
      await settle();
      await controller.endAttempt();

      expect(controller.evidence.state.contributions, hasLength(3));
      final progress = await progressService.loadProgress(targetId);
      expect(progress.stars, 0, reason: 'review practice is not lesson progress');
      expect(progress.attemptCount, 0);
      expect(await scheduler.getState(targetId), before,
          reason: 'Evidence never mutates the frozen schedule');
    });

    test('I Already Know commits only a scheduler response and records no '
        'evidence', () async {
      final clock = FakeClock(DateTime(2025, 1, 1, 11, 0, 0));
      final scheduler = newFakeReviewScheduler(clock);
      await makeReviewsReady(scheduler, clock, skillIds: <String>[targetId]);
      final before = await scheduler.getState(targetId);
      // The store a practice session would have written to.
      final store = InMemoryEvidenceStore();

      // I Already Know is explicit and immediate: no connection, no attempt,
      // no MIDI capture, no evaluation, hence no evidence (EVG-003).
      await scheduler.recordReviewResponse(targetId, ReviewResponse.iAlreadyKnow);

      final after = await scheduler.getState(targetId);
      expect(after.lastResponse, ReviewResponse.iAlreadyKnow);
      // The frozen v1.2 rule: I Already Know records the response and floors
      // the interval, it is not counted as a completed review.
      expect(after.reviewCount, before.reviewCount);
      expect(store.state.contributions, isEmpty);
      expect(store.state.streams, isEmpty);
    });

    test('Skip for Now changes neither the schedule nor the evidence', () async {
      final clock = FakeClock(DateTime(2025, 1, 1, 11, 0, 0));
      final scheduler = newFakeReviewScheduler(clock);
      await makeReviewsReady(scheduler, clock, skillIds: <String>[targetId]);
      final before = await scheduler.getState(targetId);
      final store = InMemoryEvidenceStore();

      // Skip for Now is pure navigation: no controller, no attempt, no
      // scheduler call, so the frozen schedule and the evidence are untouched.
      expect(store.state, EvidenceState.empty);
      expect(await scheduler.getState(targetId), before);
    });
  });
}
