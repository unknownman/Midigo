import 'package:flutter_test/flutter_test.dart';
import 'package:miditutor/midi/application/expected_musical_target_factory.dart';
import 'package:miditutor/midi/domain/evaluation_input.dart';
import 'package:miditutor/midi/domain/evaluation_result.dart';
import 'package:miditutor/midi/domain/expected_musical_target.dart';
import 'package:miditutor/practice/application/evaluation_flow.dart';
import 'package:miditutor/practice/application/evidence_store.dart';
import 'package:miditutor/practice/application/lesson_progress_service.dart';
import 'package:miditutor/practice/application/practice_session_controller.dart';
import 'package:miditutor/practice/domain/attempt.dart';
import 'package:miditutor/practice/domain/evidence.dart';
import 'package:miditutor/practice/domain/practice_interaction.dart';

import 'fakes.dart';

/// H2.10.1 - Evidence temporal semantics correction.
///
/// Evidence v1.1 classifies two contributions by the Practice Interaction
/// window they belong to:
///
/// ```text
/// same interaction                        -> dependent
/// different interaction, gap < 15:00      -> dependent
/// different interaction, gap >= 15:00     -> independent
/// ```
///
/// where the gap is exactly `laterInteraction.started_at - earlierInteraction.
/// ended_at` in practice-domain time (EVG-019, boundary inclusive per EVG-008).
///
/// The gap therefore only exists once the runtime reports an interaction END.
/// Before this correction the runtime reported an end on abandonment alone, so a
/// normally *completed* interaction stayed "still open" forever and every later
/// interaction was forced to stay dependent with it.
///
/// Every test below drives the real [PracticeSessionController] over a
/// deterministic [FakeClock] - the same path the Start, Lesson and Review entry
/// points use - and the temporal operands are the real interaction windows the
/// runtime produced, never hand-built values.
void main() {
  const targetId = 'major-c-rh-block';
  final target = const ExpectedMusicalTargetFactory().build(
    quality: TargetQuality.major,
    root: TargetRoot.c,
    hand: TargetHand.right,
    mode: TargetMode.block,
    targetId: targetId,
  );

  final DateTime t0 = DateTime(2025, 1, 1, 11, 0, 0);

  late FakeClock clock;
  late FakeDiscovery discovery;
  late FakeConnection connection;
  late FakeMidiStream stream;
  late LessonProgressService progressService;

  PracticeSessionController buildController({
    bool recordLessonProgress = true,
    DateTime? start,
  }) {
    clock = FakeClock(start ?? t0);
    discovery = FakeDiscovery();
    connection = FakeConnection();
    stream = FakeMidiStream();
    progressService =
        LessonProgressService(store: FakeProgressStore());
    return PracticeSessionController(
      discovery: discovery,
      connection: connection,
      captureFactory: () => stream,
      evaluation: const EvaluationFlowService(),
      progressService: progressService,
      clock: clock,
      targetProvider: () => target,
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

  /// Plays a perfect C-major block and finishes the attempt, exactly as
  /// PracticeView's Finish action does.
  Future<void> playAndFinish(PracticeSessionController controller) async {
    stream.pushPerfectCMajorBlock();
    await settle();
    await controller.endAttempt();
  }

  EvidenceIdentity pitchIdentity() =>
      EvidenceIdentity(targetId: targetId, dimension: EvaluationDimension.pitch);

  /// The dependency Evidence itself derives for the two windows, read back from
  /// the aggregated state - the same judgement `aggregate` uses for grouping.
  EvidenceDependency dependencyBetween(
    PracticeSessionController controller,
    String earlierInteractionId,
    String laterInteractionId,
  ) {
    final state = controller.evidence.state;
    final earlier = state.interactionWindow(earlierInteractionId);
    final later = state.interactionWindow(laterInteractionId);
    expect(earlier, isNotNull,
        reason: '$earlierInteractionId must have a known window');
    expect(later, isNotNull,
        reason: '$laterInteractionId must have a known window');
    expect(earlier!.startedAt.isAfter(later!.startedAt), isFalse,
        reason: 'operands must be supplied earliest-first');
    return EvidenceAggregation.classify(earlier: earlier, later: later);
  }

  group('A. a completed practice interaction closes', () {
    test('Practice -> Evaluation -> Result -> Continue records the interaction '
        'end', () async {
      final controller = await connectAndStart(buildController());
      stream.pushPerfectCMajorBlock();
      await settle();
      await controller.endAttempt();

      // The result exists but the engagement is not over: still open.
      expect(controller.session.value.latestCompletedResult,
          isA<EvaluatedResult>());
      expect(controller.runtime.hasOpenInteraction, isTrue);
      expect(
        controller.evidence.state.interactionWindow('pi-$targetId'),
        isNull,
        reason: 'no end has been reported yet',
      );

      // The completion boundary: the learner continues past the result.
      clock.current = t0.add(const Duration(minutes: 2));
      controller.completeInteraction();

      final interaction = controller.runtime.currentInteraction!;
      expect(interaction.endReason, PracticeInteractionEndReason.completed);
      expect(interaction.endedAt, t0.add(const Duration(minutes: 2)));
      expect(controller.runtime.hasOpenInteraction, isFalse);

      // The interaction end reached the Evidence temporal layer as a window.
      final window = controller.evidence.state.interactionWindow('pi-$targetId');
      expect(window, isNotNull);
      expect(window!.isOpen, isFalse);
      expect(window.startedAt, t0);
      expect(window.endedAt, t0.add(const Duration(minutes: 2)));
      expect(window.endedAt, interaction.endedAt,
          reason: 'the end is practice-runtime time, not evidence time');
    });

    test('the end is stamped from the practice clock, never the wall clock',
        () async {
      final controller = await connectAndStart(buildController());
      await playAndFinish(controller);

      final closedAt = t0.add(const Duration(seconds: 45));
      clock.current = closedAt;
      controller.completeInteraction();

      expect(controller.evidence.state.interactionWindow('pi-$targetId')!.endedAt,
          closedAt);
    });

    test('completing with no open interaction is a no-op, never an error',
        () async {
      final controller = await connectAndStart(buildController());
      await playAndFinish(controller);
      controller.completeInteraction();
      final firstEnd =
          controller.evidence.state.interactionWindow('pi-$targetId')!.endedAt;

      // Continue pressed twice / abandoned after Continue.
      controller.completeInteraction();
      await controller.abandonAttempt();

      expect(
        controller.evidence.state.interactionWindow('pi-$targetId')!.endedAt,
        firstEnd,
        reason: 'the known window is never rewritten (EVG-021)',
      );
    });
  });

  group('B. an abandoned practice interaction still closes', () {
    test('abandon ends the interaction and reports the end to Evidence',
        () async {
      final controller = await connectAndStart(buildController());
      stream.pushPerfectCMajorBlock();
      await settle();
      await controller.endAttempt();

      clock.current = t0.add(const Duration(minutes: 3));
      await controller.retryAttempt();
      await controller.abandonAttempt();

      final interaction = controller.runtime.currentInteraction!;
      expect(interaction.endReason, PracticeInteractionEndReason.abandoned);
      expect(interaction.endedAt, t0.add(const Duration(minutes: 3)));

      final window = controller.evidence.state.interactionWindow('pi-$targetId');
      expect(window!.isOpen, isFalse);
      expect(window.endedAt, t0.add(const Duration(minutes: 3)));
    });

    test('abandoning before any attempt still ends the interaction', () async {
      final controller = await connectAndStart(buildController());

      clock.current = t0.add(const Duration(minutes: 1));
      await controller.abandonAttempt();

      expect(
        controller.runtime.currentInteraction!.endReason,
        PracticeInteractionEndReason.abandoned,
      );
      expect(
        controller.evidence.state.interactionWindow('pi-$targetId'),
        isNotNull,
      );
      expect(controller.evidence.state.contributions, isEmpty,
          reason: 'an abandoned interaction contributes no evidence (EVG-003)');
    });

    test('an invalidated attempt is NOT an interaction end (existing RT '
        'semantics preserved)', () async {
      final controller = await connectAndStart(buildController());

      final attemptId =
          controller.runtime.currentItems.first.attempts.last.id;
      final invalidated = controller.runtime.invalidateAttempt(attemptId);

      // RT-008: INVALIDATED is a terminal *attempt* state. The Practice Runtime
      // contract defines only two interaction end reasons (completed, abandoned)
      // and invalidation is neither, so the interaction stays open - exactly as
      // it behaves for every caller, before and after this correction.
      expect(invalidated.state, AttemptState.invalidated);
      expect(controller.runtime.hasOpenInteraction, isTrue);
      expect(
        controller.evidence.state.interactionWindow('pi-$targetId'),
        isNull,
        reason: 'an invalidated attempt must not be reported as an interaction end',
      );
    });
  });

  group('C. not-enough-performance keeps the existing semantics', () {
    test('NEP contributes no evidence and still ends its interaction', () async {
      final controller = await connectAndStart(buildController());

      await controller.endAttempt(); // no notes at all -> frozen NEP

      expect(controller.session.value.latestCompletedResult,
          isA<NotEnoughPerformanceResult>());
      expect(controller.evidence.state.contributions, isEmpty,
          reason: 'EVG-012: NEP is ungraded, never zero-star evidence');

      clock.current = t0.add(const Duration(minutes: 4));
      controller.completeInteraction();

      // The interaction lifecycle is unchanged by the correction: the focus
      // item was completed (AttemptState.completed with an ungraded result),
      // so the engagement ends `completed`, exactly like a graded one.
      expect(
        controller.runtime.currentItems.first.attempts.last.state,
        AttemptState.completed,
      );
      expect(controller.runtime.currentInteraction!.endReason,
          PracticeInteractionEndReason.completed);
      expect(
        controller.evidence.state.interactionWindow('pi-$targetId')!.isOpen,
        isFalse,
      );
      expect(controller.evidence.state.contributions, isEmpty);
    });
  });

  group('D. a completed interaction plus a later interaction', () {
    /// Drives two full practice engagements of the same target in one session:
    /// A is completed and closed, then [gap] later B is opened and completed.
    Future<PracticeSessionController> twoEngagements({
      required Duration gap,
    }) async {
      final controller = await connectAndStart(buildController());
      await playAndFinish(controller);
      // A's engagement ends here, at t0.
      controller.completeInteraction();

      // B starts exactly `gap` after A's end - the EVG-019 operand.
      clock.current = t0.add(gap);
      await controller.startAttempt();
      await playAndFinish(controller);
      controller.completeInteraction();
      return controller;
    }

    test('a completed interaction no longer keeps a later interaction '
        'dependent', () async {
      final controller =
          await twoEngagements(gap: const Duration(minutes: 30));

      // Two genuinely different Practice Interactions (RT-002: one engagement
      // each) - not two attempts of one interaction.
      final ids = controller.evidence.state.contributions
          .map((c) => c.provenance.practiceInteractionId)
          .toSet();
      expect(ids, <String>{'pi-$targetId', 'pi-$targetId-2'});

      expect(
        dependencyBetween(controller, 'pi-$targetId', 'pi-$targetId-2'),
        EvidenceDependency.independent,
      );
      final pitch = controller.evidence.state.streamFor(pitchIdentity())!;
      expect(pitch.groups, hasLength(2),
          reason: 'the 30-minute boundary starts a new group');
    });

    test('this is the central H2.10.1 regression: the interaction end is '
        'exactly what makes the later interaction independent', () async {
      final controller = await connectAndStart(buildController());
      await playAndFinish(controller);
      controller.completeInteraction(); // A ends at t0.

      clock.current = t0.add(const Duration(minutes: 30));
      await controller.startAttempt();
      await playAndFinish(controller);
      controller.completeInteraction(); // B ends at t0 + 30:00.

      final state = controller.evidence.state;
      final pitch = state.streamFor(pitchIdentity())!;
      final a = pitch.contributions
          .singleWhere((c) => c.provenance.practiceInteractionId == 'pi-$targetId');
      final b = pitch.contributions.singleWhere(
          (c) => c.provenance.practiceInteractionId == 'pi-$targetId-2');

      // Pre-correction: the runtime never reported the completed interaction's
      // end, so Evidence only ever had A's *start* and fell back to the open
      // window the contribution itself observed. There is no earlier
      // `ended_at`, therefore no gap, therefore forced dependence - forever.
      const noEnds = <String, EvidenceInteractionWindow>{};
      final openA = EvidenceAggregation.resolveWindow(a, noEnds);
      expect(openA.isOpen, isTrue);
      expect(
        EvidenceAggregation.independenceGap(
          earlier: openA,
          later: EvidenceAggregation.resolveWindow(b, noEnds),
        ),
        isNull,
      );
      expect(
        EvidenceAggregation.classify(
          earlier: openA,
          later: EvidenceAggregation.resolveWindow(b, noEnds),
        ),
        EvidenceDependency.dependent,
      );

      // Post-correction: the same two contributions, with the end the completed
      // lifecycle now reports, cross the 15-minute boundary.
      expect(dependencyBetween(controller, 'pi-$targetId', 'pi-$targetId-2'),
          EvidenceDependency.independent);
      expect(pitch.groups, hasLength(2));
      expect(
        pitch.groups.map((g) => g.contributions.single.provenance
            .practiceInteractionId),
        <String>['pi-$targetId', 'pi-$targetId-2'],
      );
    });

    test('a second engagement of the same target is a distinct interaction, '
        'not a collision of the first one', () async {
      final controller =
          await twoEngagements(gap: const Duration(minutes: 30));

      // A shared id would have made the two attempts of the second engagement
      // reuse the first one's contribution identities, silently dropping real
      // evidence. Interaction identity stays deterministic (RT-003): no clock,
      // no randomness - a plain per-session ordinal.
      final attemptIds = controller.evidence.state.contributions
          .map((c) => c.provenance.attemptId)
          .toSet();
      expect(attemptIds, hasLength(2));
      expect(
        controller.evidence.state.contributionById(
            'contribution:evidence:$targetId:pitch:pi-$targetId-2-item-0-attempt-1'),
        isNotNull,
      );
    });
  });

  group('E/F/G. the exact 15-minute boundary on the real runtime operands', () {
    for (final (gap, expected) in <(Duration, EvidenceDependency)>[
      (const Duration(minutes: 14, seconds: 59), EvidenceDependency.dependent),
      (const Duration(minutes: 15), EvidenceDependency.independent),
      (const Duration(minutes: 15, seconds: 1), EvidenceDependency.independent),
    ]) {
      test('gap $gap is $expected', () async {
        final controller = await connectAndStart(buildController());
        await playAndFinish(controller);
        controller.completeInteraction(); // A ends at t0.

        clock.current = t0.add(gap);
        await controller.startAttempt();
        await playAndFinish(controller);
        controller.completeInteraction(); // B ends at t0 + gap.

        // The operands are exactly EVG-019's: later.started_at minus
        // earlier.ended_at, in practice-domain time.
        final state = controller.evidence.state;
        final a = state.interactionWindow('pi-$targetId')!;
        final b = state.interactionWindow('pi-$targetId-2')!;
        expect(a.startedAt, t0);
        expect(a.endedAt, t0);
        expect(b.startedAt, t0.add(gap));
        expect(
          EvidenceAggregation.independenceGap(earlier: a, later: b),
          gap,
        );

        expect(dependencyBetween(controller, 'pi-$targetId', 'pi-$targetId-2'),
            expected);

        final pitch = state.streamFor(pitchIdentity())!;
        expect(pitch.groups, hasLength(expected == EvidenceDependency.dependent ? 1 : 2),
            reason: 'grouping must follow the same classification');
      });
    }
  });

  group('H. recording an end never back-writes evidence', () {
    test('stored contributions are the identical objects after the end',
        () async {
      final controller = await connectAndStart(buildController());
      await playAndFinish(controller);

      final before = List<EvidenceContribution>.of(
        controller.evidence.state.contributions,
      );
      expect(before, hasLength(3));
      for (final contribution in before) {
        expect(contribution.provenance.practiceInteractionStartedAt, t0);
      }

      clock.current = t0.add(const Duration(minutes: 20));
      controller.completeInteraction();

      final after = controller.evidence.state.contributions;
      expect(after, hasLength(3));
      for (var i = 0; i < before.length; i++) {
        expect(identical(after[i], before[i]), isTrue,
            reason: 'contribution ${after[i].id} must be the same immutable '
                'object, never a mutated copy');
        expect(after[i], before[i]);
      }
      // The end is a separate immutable record, not a field of the
      // contribution: EvidenceContribution has no end operand at all.
      final window = controller.evidence.state.interactionWindow('pi-$targetId')!;
      expect(window.isOpen, isFalse);
      expect(
        before.every((c) => c.provenance.practiceInteractionStartedAt == t0),
        isTrue,
      );
    });

    test('re-recording an end never rewrites a known window', () async {
      final controller = await connectAndStart(buildController());
      await playAndFinish(controller);
      controller.completeInteraction();
      final first =
          controller.evidence.state.interactionWindow('pi-$targetId')!;

      clock.current = t0.add(const Duration(hours: 3));
      controller.completeInteraction();

      expect(
        identical(controller.evidence.state.interactionWindow('pi-$targetId'),
            first),
        isTrue,
      );
    });
  });

  group('I. Review uses the same interaction-end path', () {
    test('review practice closes its interaction identically', () async {
      // Exactly how ReviewSessionScreen builds its per-item controller:
      // recordLessonProgress: false, same runtime, same clock.
      final controller =
          await connectAndStart(buildController(recordLessonProgress: false));
      await playAndFinish(controller);

      expect(controller.evidence.state.interactionWindow('pi-$targetId'), isNull);

      clock.current = t0.add(const Duration(minutes: 5));
      controller.completeInteraction();

      // There is no Review-specific lifecycle: the same
      // PracticeInteractionEndReason.completed, the same window, the same
      // evidence - and still no lesson progress.
      final interaction = controller.runtime.currentInteraction!;
      expect(interaction.endReason, PracticeInteractionEndReason.completed);
      final window = controller.evidence.state.interactionWindow('pi-$targetId');
      expect(window!.isOpen, isFalse);
      expect(window.endedAt, t0.add(const Duration(minutes: 5)));
      expect(window.endedAt, interaction.endedAt);

      final progress = await progressService.loadProgress(targetId);
      expect(progress.attemptCount, 0,
          reason: 'review practice is not lesson progress');
    });

    test('a completed review interaction and a later one become independent',
        () async {
      final controller =
          await connectAndStart(buildController(recordLessonProgress: false));
      await playAndFinish(controller);
      controller.completeInteraction();

      clock.current = t0.add(const Duration(minutes: 15));
      await controller.startAttempt();
      await playAndFinish(controller);
      controller.completeInteraction();

      expect(
        dependencyBetween(controller, 'pi-$targetId', 'pi-$targetId-2'),
        EvidenceDependency.independent,
      );
      expect(controller.evidence.state.streamFor(pitchIdentity())!.groups,
          hasLength(2));
    });
  });

  group('J. retry semantics are unchanged', () {
    test('a retry is a new attempt of the SAME interaction, which stays open',
        () async {
      final controller = await connectAndStart(buildController());
      await playAndFinish(controller);

      // The learner retries instead of continuing: no interaction end.
      await controller.retryAttempt();
      expect(controller.runtime.hasOpenInteraction, isTrue);
      expect(controller.evidence.state.interactionWindow('pi-$targetId'), isNull);
      expect(
        controller.runtime.currentInteraction!.items.first.attempts,
        hasLength(2),
      );

      await playAndFinish(controller);
      controller.completeInteraction();

      final pitch = controller.evidence.state.streamFor(pitchIdentity())!;
      expect(pitch.contributionCount, 2);
      expect(pitch.groups, hasLength(1),
          reason: 'the same interaction is always dependent (EVG-007)');
      expect(
        pitch.contributions
            .map((c) => c.provenance.practiceInteractionId)
            .toSet(),
        <String>{'pi-$targetId'},
      );
      expect(
        pitch.contributions.map((c) => c.provenance.attemptId).toSet(),
        <String>{
          'pi-$targetId-item-0-attempt-1',
          'pi-$targetId-item-0-attempt-2',
        },
      );
      expect(controller.evidence.state.interactionWindow('pi-$targetId')!.isOpen,
          isFalse);
    });

    test('retrying never ends the interaction on its own', () async {
      final controller = await connectAndStart(buildController());
      await playAndFinish(controller);
      await controller.retryAttempt();
      await controller.retryAttempt();

      expect(controller.runtime.hasOpenInteraction, isTrue);
      expect(controller.evidence.state.interactionWindow('pi-$targetId'), isNull);
      expect(
        controller.runtime.currentItems.first.attempts.last.state,
        AttemptState.armed,
      );
    });
  });

  group('an interaction with no reported end is still open', () {
    test('an unfinished engagement never gains an end implicitly', () async {
      final controller = await connectAndStart(buildController());
      await playAndFinish(controller);

      expect(
        controller.evidence.state.interactionWindow('pi-$targetId'),
        isNull,
      );
      expect(controller.runtime.hasOpenInteraction, isTrue);

      // Even much later, an unreported end stays unreported.
      clock.current = t0.add(const Duration(days: 3));
      expect(
        controller.evidence.state.interactionWindow('pi-$targetId'),
        isNull,
      );
      expect(
        controller.evidence.state.streamFor(pitchIdentity())!.groups,
        hasLength(1),
      );
    });

    test('a window without an end is never treated as independent', () {
      final openA = EvidenceInteractionWindow(
        practiceInteractionId: 'pi-a',
        startedAt: t0,
      );
      final laterB = EvidenceInteractionWindow(
        practiceInteractionId: 'pi-b',
        startedAt: t0.add(const Duration(days: 3)),
        endedAt: t0.add(const Duration(days: 3, minutes: 1)),
      );

      expect(
        EvidenceAggregation.independenceGap(earlier: openA, later: laterB),
        isNull,
      );
      expect(
        EvidenceAggregation.classify(earlier: openA, later: laterB),
        EvidenceDependency.dependent,
      );
      expect(openA.isOpen, isTrue);
    });
  });

  group('the store rejects a window that was never closed', () {
    test('a still-open interaction cannot be reported as ended', () async {
      final store = InMemoryEvidenceStore();
      final stillOpen = PracticeInteraction(
        id: 'pi-open',
        executionSession: ExecutionSession(
            id: 'es-pi-open', practiceInteractionId: 'pi-open'),
        startedAt: t0,
      );

      expect(
        () => store.recordInteractionEnd(stillOpen),
        throwsStateError,
        reason: 'the Practice Runtime must end the interaction first',
      );
    });
  });
}
