import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miditutor/midi/application/expected_musical_target_factory.dart';
import 'package:miditutor/midi/domain/evaluation_input.dart';
import 'package:miditutor/midi/domain/evaluation_policy.dart';
import 'package:miditutor/midi/domain/evaluation_result.dart';
import 'package:miditutor/midi/domain/expected_musical_target.dart';
import 'package:miditutor/practice/application/evaluation_flow.dart';
import 'package:miditutor/practice/application/evidence_aggregation_service.dart';
import 'package:miditutor/practice/application/evidence_store.dart';
import 'package:miditutor/practice/application/practice_runtime.dart';
import 'package:miditutor/practice/domain/attempt.dart';
import 'package:miditutor/practice/domain/evidence.dart';
import 'package:miditutor/practice/domain/exercise_instance.dart';
import 'package:miditutor/practice/domain/practice_interaction.dart';
import 'package:miditutor/practice/domain/practice_item.dart';

import 'fakes.dart';

const String _blockTargetId = 'major-c-rh-block';

/// The identity/version vocabulary a real flow run propagates out of the
/// frozen canonical input.
const EvaluationProvenance _evaluationProvenance = EvaluationProvenance(
  evaluationProfileId: 'mvp_default_v1',
  evaluationProfileVersion: 'v1.1',
  alignmentAlgorithmVersion: '1',
  observationExtractionAlgorithmVersion: '1',
  preparationAlgorithmVersion: '1',
  flowAlgorithmVersion: '1',
);

DimensionResult _graded(EvaluationDimension dimension) => DimensionResult(
      dimension: dimension,
      state: EvaluationDimensionState.enabled,
      dataAvailability: DataAvailability.available,
      severity: SeverityTier.none,
    );

DimensionResult _notApplicable(EvaluationDimension dimension) => DimensionResult(
      dimension: dimension,
      state: EvaluationDimensionState.notApplicable,
      dataAvailability: DataAvailability.unavailable,
      severity: SeverityTier.none,
    );

/// The exact dimension shape the frozen engine emits for a BLOCK target:
/// pitch/timing/simultaneity graded, order/ioi not applicable, Retrieval
/// Latency enabled but with no runtime performance anchor.
List<DimensionResult> _blockDimensions() => <DimensionResult>[
      _graded(EvaluationDimension.pitch),
      _graded(EvaluationDimension.timing),
      _notApplicable(EvaluationDimension.order),
      _graded(EvaluationDimension.simultaneity),
      _notApplicable(EvaluationDimension.ioi),
      DimensionResult(
        dimension: EvaluationDimension.retrievalLatency,
        state: EvaluationDimensionState.enabled,
        dataAvailability: DataAvailability.unavailable,
        severity: SeverityTier.none,
      ),
    ];

EvaluationFlowResult _flow(EvaluationResult result) => EvaluationFlowResult(
      result: result,
      targetId: _blockTargetId,
      sessionId: 'session-1',
      mode: TargetMode.block,
      provenance: _evaluationProvenance,
    );

EvaluatedResult _evaluated(int stars) =>
    EvaluatedResult(stars: stars, dimensions: _blockDimensions());

final NotEnoughPerformanceResult _nep =
    NotEnoughPerformanceResult(dimensions: _blockDimensions());

final ExpectedMusicalTarget _target =
    const ExpectedMusicalTargetFactory().build(
  quality: TargetQuality.major,
  root: TargetRoot.c,
  hand: TargetHand.right,
  mode: TargetMode.block,
  targetId: _blockTargetId,
);

final ExerciseInstance _exercise = ExerciseInstance(
  id: 'exercise-$_blockTargetId',
  expectedTarget: _target,
);

EvidenceIdentity _identity(EvaluationDimension dimension) =>
    EvidenceIdentity(targetId: _blockTargetId, dimension: dimension);

/// A practice runtime + evidence environment over one injected practice clock.
final class _Env {
  _Env(this.clock, {InMemoryEvidenceStore? store})
      : store = store ?? InMemoryEvidenceStore() {
    aggregator = PracticeEvidenceAggregator(store: this.store, clock: clock);
  }

  final FakeClock clock;
  final InMemoryEvidenceStore store;
  late final PracticeEvidenceAggregator aggregator;

  PracticeRuntime open(String interactionId) {
    final runtime = PracticeRuntime(clock: clock);
    runtime.createInteraction(
      interactionId: interactionId,
      exercises: <ExerciseInstance>[_exercise],
    );
    return runtime;
  }

  /// Arms, activates, completes one attempt and records its evidence.
  EvidenceRecordOutcome play(
    PracticeRuntime runtime,
    EvaluationResult result, {
    int stars = 5,
  }) {
    final attempt = runtime.armAttempt(itemId: runtime.currentItems.first.id);
    runtime.activateAttempt(attempt.id);
    final completed =
        runtime.completeAttempt(attemptId: attempt.id, result: result);
    return aggregator.recordAttempt(
      attempt: completed,
      interaction: runtime.currentInteraction!,
      evaluation: _flow(result),
    );
  }

  /// One evaluated contribution of [interactionId] created at [at].
  EvidenceContribution contribute(
    String interactionId, {
    required DateTime at,
    int stars = 5,
  }) {
    clock.current = at;
    final runtime = open(interactionId);
    final outcome = play(runtime, _evaluated(stars));
    end(runtime);
    return _only(outcome);
  }

  Attempt abandon(PracticeRuntime runtime) {
    final attempt = runtime.armAttempt(itemId: runtime.currentItems.first.id);
    runtime.activateAttempt(attempt.id);
    return runtime.abandonAttempt(attempt.id);
  }

  Attempt invalidate(PracticeRuntime runtime) {
    final attempt = runtime.armAttempt(itemId: runtime.currentItems.first.id);
    runtime.activateAttempt(attempt.id);
    return runtime.invalidateAttempt(attempt.id);
  }

  /// Ends the interaction and reports its end, exactly as the session
  /// controller does, so the store learns EVG-019's second gap operand.
  void end(PracticeRuntime runtime) => aggregator.recordInteractionEnd(
        runtime.endInteraction(reason: PracticeInteractionEndReason.completed),
      );
}

/// A Practice Interaction lifecycle window, as Evidence sees it (RT-004).
EvidenceInteractionWindow _window(
  String id, {
  required DateTime startedAt,
  DateTime? endedAt,
}) =>
    EvidenceInteractionWindow(
      practiceInteractionId: id,
      startedAt: startedAt,
      endedAt: endedAt,
    );

/// The dependency Evidence itself derives for two stored contributions, read
/// back through the store's aggregated state.
EvidenceDependency _dependencyInStore(
  _Env env,
  EvidenceContribution a,
  EvidenceContribution b,
) {
  final state = env.store.state;
  final windows = <String, EvidenceInteractionWindow>{
    for (final window in state.interactionWindows)
      window.practiceInteractionId: window,
  };
  final aWindow = EvidenceAggregation.resolveWindow(a, windows);
  final bWindow = EvidenceAggregation.resolveWindow(b, windows);
  return aWindow.startedAt.isAfter(bWindow.startedAt)
      ? EvidenceAggregation.classify(earlier: bWindow, later: aWindow)
      : EvidenceAggregation.classify(earlier: aWindow, later: bWindow);
}

EvidenceContribution _only(EvidenceRecordOutcome outcome) {
  expect(outcome.producedEvidence, isTrue);
  return outcome.contributions.first;
}

/// Strips every Dart comment so a source-level vocabulary audit is about code,
/// never about prose.
String _code(String source) =>
    source.split('\n').map((line) => line.split('//').first).join('\n');

void main() {
  final DateTime t0 = DateTime(2025, 1, 1, 10, 0, 0);

  group('Evidence Aggregation Contract v1.1 fidelity', () {
    test('the only numeric Evidence policy is a 15-minute inclusive boundary',
        () {
      expect(EvidenceAggregationContract.contractName,
          'Evidence Aggregation Contract');
      expect(EvidenceAggregationContract.contractVersion, 'v1.1');
      expect(EvidenceAggregationContract.independenceThreshold,
          const Duration(minutes: 15));
      expect(EvidenceAggregationContract.independenceBoundaryInclusive, isTrue);
    });

    test('v1.1 defines exactly one contribution kind: practiceAttempt', () {
      expect(EvidenceContributionKind.values,
          <EvidenceContributionKind>[EvidenceContributionKind.practiceAttempt]);
    });

    test('the layer leaks no mastery and no scheduler vocabulary', () {
      const forbidden = <String>[
        'SUCCESS',
        'MARGINAL',
        'FAILURE',
        'FAILED',
        'INVALID',
        'RELEARNING',
        'ACQUISITION',
        'mastery',
        'Mastery',
        'confidence',
        'retention',
        'decay',
        'interval',
        'Interval',
        'eligible',
        'dueAt',
        'retrievalInstance',
      ];
      const sources = <String>[
        'lib/practice/domain/evidence.dart',
        'lib/practice/application/evidence_store.dart',
        'lib/practice/application/evidence_aggregation_service.dart',
      ];
      for (final path in sources) {
        final code = _code(File(path).readAsStringSync());
        for (final word in forbidden) {
          expect(code.contains(word), isFalse,
              reason: '$path must not declare evidence vocabulary "$word"');
        }
      }
    });
  });

  group('deterministic Evidence identity (EVG-002/EVG-020)', () {
    test('same target + same dimension -> the same identity', () {
      final a = _identity(EvaluationDimension.pitch);
      final b = EvidenceIdentity(
          targetId: _blockTargetId, dimension: EvaluationDimension.pitch);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.streamId, b.streamId);
      expect(a.streamId, 'evidence:major-c-rh-block:pitch');
    });

    test('a different target -> a different identity', () {
      final a = _identity(EvaluationDimension.pitch);
      final b = EvidenceIdentity(
          targetId: 'major-c-rh-arpeggio', dimension: EvaluationDimension.pitch);

      expect(a == b, isFalse);
      expect(a.streamId == b.streamId, isFalse);
    });

    test('a different dimension -> a different identity', () {
      final identities = <EvidenceIdentity>[
        for (final dimension in EvaluationDimension.values)
          EvidenceIdentity(targetId: _blockTargetId, dimension: dimension),
      ];

      expect(identities.map((i) => i.streamId).toSet(), hasLength(6));
      for (final dimension in EvaluationDimension.values) {
        expect(
          identities
              .singleWhere((i) => i.dimension == dimension)
              .streamId,
          'evidence:$_blockTargetId:${dimension.name}',
        );
      }
    });

    test('identity does not depend on any timestamp', () {
      final env = _Env(FakeClock(t0));
      final early = _only(env.play(env.open('pi-a'), _evaluated(5)));
      env.clock.current = t0.add(const Duration(days: 3));
      final late = _only(env.play(env.open('pi-b'), _evaluated(3)));

      expect(early.createdAt, isNot(late.createdAt));
      expect(early.identity, late.identity);
      expect(early.streamId, late.streamId);
      expect(early.provenance.practiceInteractionStartedAt,
          isNot(late.provenance.practiceInteractionStartedAt));
    });

    test('identity does not depend on random values or construction order', () {
      final first = _identity(EvaluationDimension.timing);
      for (var i = 0; i < 50; i++) {
        final again = _identity(EvaluationDimension.timing);
        expect(again, first);
        expect(again.streamId, first.streamId);
      }
    });

    test('identity stays stable across a process restart', () {
      final beforeEnv = _Env(FakeClock(t0));
      final before =
          _only(beforeEnv.play(beforeEnv.open('pi-major-c-rh-block'), _evaluated(5)));

      // A restart: brand new objects, a brand new store, a restarted clock and
      // the same deterministic attempt replayed.
      final afterEnv = _Env(FakeClock(t0.add(const Duration(days: 1))));
      final after =
          _only(afterEnv.play(afterEnv.open('pi-major-c-rh-block'), _evaluated(5)));

      expect(after.id, before.id);
      expect(after.identity.streamId, before.identity.streamId);
      expect(
        afterEnv.store.state.streams.map((stream) => stream.groups.single.id),
        beforeEnv.store.state.streams.map((stream) => stream.groups.single.id),
      );
    });

    test('a contribution id is derived from the stream and the attempt', () {
      expect(
        EvidenceAggregation.contributionId(
          identity: _identity(EvaluationDimension.pitch),
          attemptId: 'pi-1-item-0-attempt-1',
        ),
        'contribution:evidence:major-c-rh-block:pitch:pi-1-item-0-attempt-1',
      );

      // EVG-020: a contribution cannot carry a caller-chosen id, so its
      // identity is structurally content derived.
      final env = _Env(FakeClock(t0));
      final contribution = _only(env.play(env.open('pi-1'), _evaluated(5)));
      expect(
        contribution.id,
        'contribution:evidence:major-c-rh-block:pitch:pi-1-item-0-attempt-1',
      );
      expect(
        contribution.id,
        EvidenceAggregation.contributionId(
          identity: contribution.identity,
          attemptId: contribution.provenance.attemptId,
        ),
      );
    });
  });

  group('contribution creation (EVG-003/EVG-011..EVG-013)', () {
    test('a valid evaluated attempt creates one contribution per graded stream',
        () {
      final env = _Env(FakeClock(t0));

      final outcome = env.play(env.open('pi-1'), _evaluated(5));

      expect(outcome.producedEvidence, isTrue);
      expect(outcome.omission, isNull);
      expect(outcome.contributions, hasLength(3));
      expect(
        outcome.contributions.map((c) => c.identity.dimension).toSet(),
        <EvaluationDimension>{
          EvaluationDimension.pitch,
          EvaluationDimension.timing,
          EvaluationDimension.simultaneity,
        },
      );
      for (final contribution in outcome.contributions) {
        expect(contribution.kind, EvidenceContributionKind.practiceAttempt);
        expect(contribution.stars, 5);
        expect(contribution.dimensionState, EvaluationDimensionState.enabled);
        expect(contribution.dataAvailability, DataAvailability.available);
      }
    });

    test('5-, 3-, 1- and 0-star evaluated results are all evidence', () {
      for (final stars in <int>[5, 3, 1, 0]) {
        final env = _Env(FakeClock(t0));

        final outcome = env.play(env.open('pi-$stars'), _evaluated(stars));

        expect(outcome.producedEvidence, isTrue, reason: '$stars stars');
        expect(outcome.contributions, hasLength(3));
        expect(outcome.contributions.every((c) => c.stars == stars), isTrue,
            reason: 'the observed $stars stars are recorded as evidence');
      }
    });

    test('a zero-star evaluated result is evidence, never an absence', () {
      final env = _Env(FakeClock(t0));

      final outcome = env.play(env.open('pi-0'), _evaluated(0));

      expect(outcome.omission, isNull);
      expect(env.store.state.contributions, hasLength(3));
      expect(env.store.state.contributions.every((c) => c.stars == 0), isTrue);
    });

    test('not-enough-performance yields no contribution at all (EVG-012)', () {
      final env = _Env(FakeClock(t0));

      final outcome = env.play(env.open('pi-nep'), _nep);

      expect(outcome.producedEvidence, isFalse);
      expect(outcome.omission, EvidenceOmission.notEnoughPerformance);
      expect(outcome.contributions, isEmpty);
      expect(env.store.state.contributions, isEmpty);
      expect(env.store.state.streams, isEmpty);
    });

    test('NEP is never recorded as zero-star evidence', () {
      final env = _Env(FakeClock(t0));
      final runtime = env.open('pi-1');

      env.play(runtime, _nep);
      env.play(runtime, _evaluated(0));

      expect(env.store.state.contributions, hasLength(3));
      expect(env.store.state.contributions.map((c) => c.stars).toSet(), <int>{0});
    });

    test('an abandoned attempt contributes no evidence', () {
      final env = _Env(FakeClock(t0));
      final runtime = env.open('pi-1');
      final abandoned = env.abandon(runtime);

      final outcome = env.aggregator.recordAttempt(
        attempt: abandoned,
        interaction: runtime.currentInteraction!,
        evaluation: _flow(_evaluated(5)),
      );

      expect(outcome.producedEvidence, isFalse);
      expect(outcome.omission, EvidenceOmission.attemptNotCompleted);
      expect(env.store.state.contributions, isEmpty);
    });

    test('an invalidated attempt contributes no evidence', () {
      final env = _Env(FakeClock(t0));
      final runtime = env.open('pi-1');
      final invalidated = env.invalidate(runtime);

      final outcome = env.aggregator.recordAttempt(
        attempt: invalidated,
        interaction: runtime.currentInteraction!,
        evaluation: _flow(_evaluated(5)),
      );

      expect(outcome.producedEvidence, isFalse);
      expect(outcome.omission, EvidenceOmission.attemptNotCompleted);
      expect(env.store.state.contributions, isEmpty);
    });

    test('an armed attempt that never ran contributes no evidence', () {
      final env = _Env(FakeClock(t0));
      final runtime = env.open('pi-1');
      final armed = runtime.armAttempt(itemId: runtime.currentItems.first.id);

      final outcome = env.aggregator.recordAttempt(
        attempt: armed,
        interaction: runtime.currentInteraction!,
        evaluation: _flow(_evaluated(5)),
      );

      expect(outcome.omission, EvidenceOmission.attemptNotCompleted);
      expect(env.store.state.contributions, isEmpty);
    });

    test('an attempt owned by another interaction is never attributed', () {
      final env = _Env(FakeClock(t0));
      final runtime = env.open('pi-1');
      final attempt = runtime.armAttempt(itemId: runtime.currentItems.first.id);
      runtime.activateAttempt(attempt.id);
      runtime.completeAttempt(attemptId: attempt.id, result: _evaluated(5));
      final completed = runtime.currentInteraction!.items.first.attempts.last;

      final foreign = PracticeInteraction(
        id: 'pi-foreign',
        executionSession: ExecutionSession(
            id: 'es-pi-foreign', practiceInteractionId: 'pi-foreign'),
        items: <PracticeItem>[
          PracticeItem(
            id: 'pi-foreign-item-0',
            exerciseInstance: _exercise,
            attempts: <Attempt>[completed],
          ),
        ],
        startedAt: t0,
      );

      final outcome = env.aggregator.recordAttempt(
        attempt: completed,
        interaction: foreign,
        evaluation: _flow(_evaluated(5)),
      );

      expect(outcome.omission, EvidenceOmission.attemptNotOwnedByInteraction);
      expect(env.store.state.contributions, isEmpty);
    });

    test('Retrieval Latency receives no contribution (EVG-011)', () {
      final env = _Env(FakeClock(t0));
      final result = _evaluated(5);

      env.play(env.open('pi-1'), result);

      expect(env.store.streamFor(_identity(EvaluationDimension.retrievalLatency)),
          isNull);
      expect(
        env.store.state.contributions
            .any((c) => c.identity == _identity(EvaluationDimension.retrievalLatency)),
        isFalse,
      );
      // The dimension stays enabled-and-unavailable: the stream is defined, it
      // simply never receives a contribution.
      final latency = result.dimensions
          .firstWhere((d) => d.dimension == EvaluationDimension.retrievalLatency);
      expect(latency.state, EvaluationDimensionState.enabled);
      expect(latency.dataAvailability, DataAvailability.unavailable);
    });

    test('a result with no graded dimension contributes nothing', () {
      final env = _Env(FakeClock(t0));
      final ungraded = EvaluatedResult(
        stars: 4,
        dimensions: <DimensionResult>[
          for (final dimension in EvaluationDimension.values)
            _notApplicable(dimension),
        ],
      );

      final outcome = env.play(env.open('pi-1'), ungraded);

      expect(outcome.omission, EvidenceOmission.noGradedDimension);
      expect(env.store.state.contributions, isEmpty);
    });

    test('provenance answers attempt, interaction, item, target and dimension',
        () {
      final env = _Env(FakeClock(t0));
      final runtime = env.open('pi-1');

      final contribution = _only(env.play(runtime, _evaluated(5)));
      final attempt = runtime.currentInteraction!.items.first.attempts.last;

      expect(contribution.provenance.attemptId, attempt.id);
      expect(contribution.provenance.practiceInteractionId, 'pi-1');
      expect(contribution.provenance.executionSessionId, 'es-pi-1');
      expect(contribution.provenance.practiceItemId, attempt.practiceItemId);
      expect(contribution.provenance.targetId, _blockTargetId);
      expect(contribution.identity.dimension, EvaluationDimension.pitch);
      expect(contribution.provenance.mode, TargetMode.block);
      expect(contribution.provenance.captureSessionId, 'session-1');
      expect(contribution.provenance.evaluationProfileId, 'mvp_default_v1');
      expect(contribution.provenance.evaluationProfileVersion, 'v1.1');
      expect(contribution.provenance.alignmentAlgorithmVersion, '1');
      expect(contribution.provenance.practiceInteractionStartedAt, t0);
      expect(contribution.createdAt, t0);
    });
  });

  group('one contribution per attempt + stream (EVG-003)', () {
    test('recording the same attempt and stream again never duplicates', () {
      final env = _Env(FakeClock(t0));
      final runtime = env.open('pi-1');
      final attempt = runtime.armAttempt(itemId: runtime.currentItems.first.id);
      runtime.activateAttempt(attempt.id);
      final completed =
          runtime.completeAttempt(attemptId: attempt.id, result: _evaluated(5));
      final interaction = runtime.currentInteraction!;

      final first = env.aggregator.recordAttempt(
          attempt: completed,
          interaction: interaction,
          evaluation: _flow(_evaluated(5)));
      final second = env.aggregator.recordAttempt(
          attempt: completed,
          interaction: interaction,
          evaluation: _flow(_evaluated(5)));
      final third = env.aggregator.recordAttempt(
          attempt: completed,
          interaction: interaction,
          evaluation: _flow(_evaluated(5)));

      expect(first.contributions.map((c) => c.id),
          second.contributions.map((c) => c.id));
      expect(env.store.state.contributions, hasLength(3));
      expect(env.store.state.streams, hasLength(3));
      expect(env.store.state.groups, hasLength(3));
      for (final contribution in first.contributions) {
        expect(identical(env.store.contributionById(contribution.id),
            contribution), isTrue);
        expect(
          identical(
            second.contributions.firstWhere((c) => c.id == contribution.id),
            contribution,
          ),
          isTrue,
        );
        expect(
          identical(
            third.contributions.firstWhere((c) => c.id == contribution.id),
            contribution,
          ),
          isTrue,
        );
      }
    });

    test('a repeated record can never overwrite stored evidence', () {
      final env = _Env(FakeClock(t0));
      final runtime = env.open('pi-1');

      final first = _only(env.play(runtime, _evaluated(5)));
      // The same attempt id replayed with a different quality: evidence is
      // immutable, so the contribution already stored stands unchanged.
      env.play(runtime, _evaluated(1));

      expect(env.store.contributionById(first.id)!.stars, 5);
      expect(env.store.contributionById(first.id), first);
    });

    test('each retry is a distinct contribution of the same stream', () {
      final env = _Env(FakeClock(t0));
      final runtime = env.open('pi-1');

      env.play(runtime, _evaluated(5));
      env.play(runtime, _evaluated(3));
      env.play(runtime, _evaluated(0));

      final pitch = env.store.state.streamFor(_identity(EvaluationDimension.pitch))!;
      expect(pitch.contributionCount, 3);
      expect(pitch.contributions.map((c) => c.stars), <int>[5, 3, 0]);
      expect(
        pitch.contributions.map((c) => c.provenance.attemptId).toSet(),
        hasLength(3),
      );
      // One interaction, so all three stay in one dependent group.
      expect(pitch.groups, hasLength(1));
    });
  });

  group('contribution dependency semantics (EVG-007/008/019)', () {
    test('the 15-minute boundary is exact and inclusive', () {
      // An interaction that ended at t0 is the earlier operand.
      final earlier = _window('pi-a', startedAt: t0, endedAt: t0);

      for (final (gap, expected) in <(Duration, EvidenceDependency)>[
        (
          const Duration(minutes: 14, seconds: 59),
          EvidenceDependency.dependent
        ),
        (const Duration(minutes: 15), EvidenceDependency.independent),
        (
          const Duration(minutes: 15, seconds: 1),
          EvidenceDependency.independent
        ),
        (const Duration(minutes: 45), EvidenceDependency.independent),
      ]) {
        final startedAt = t0.add(gap);
        final later = _window(
          'pi-later-$gap',
          startedAt: startedAt,
          endedAt: startedAt.add(const Duration(minutes: 1)),
        );
        expect(
          EvidenceAggregation.independenceGap(
            earlier: earlier,
            later: later,
          ),
          gap,
          reason: 'gap $gap',
        );
        expect(
          EvidenceAggregation.classify(earlier: earlier, later: later),
          expected,
          reason: 'gap $gap',
        );
      }
    });

    test('the same Practice Interaction is always dependent', () {
      final open = _window('pi-a', startedAt: t0);
      final closed = _window('pi-a', startedAt: t0, endedAt: t0);

      expect(
        EvidenceAggregation.independenceGap(earlier: open, later: closed),
        isNull,
      );
      expect(
        EvidenceAggregation.classify(earlier: open, later: closed),
        EvidenceDependency.dependent,
      );
    });

    test('an interaction that has not ended yet stays dependent', () {
      // pi-a is still open three hours into pi-b: EVG-019's earlier ended_at
      // operand does not exist yet, so independence is never assumed.
      final stillOpen = _window('pi-a', startedAt: t0);
      final later = _window(
        'pi-b',
        startedAt: t0.add(const Duration(hours: 3)),
        endedAt: t0.add(const Duration(hours: 3, minutes: 1)),
      );

      expect(
        EvidenceAggregation.independenceGap(
          earlier: stillOpen,
          later: later,
        ),
        isNull,
      );
      expect(
        EvidenceAggregation.classify(earlier: stillOpen, later: later),
        EvidenceDependency.dependent,
      );
    });

    test('a reported interaction end is what makes the gap observable', () {
      final env = _Env(FakeClock(t0));
      // pi-a plays, and its end is deliberately NOT reported yet.
      final runtimeA = env.open('pi-a');
      final a = _only(env.play(runtimeA, _evaluated(5)));
      final closedA =
          runtimeA.endInteraction(reason: PracticeInteractionEndReason.completed);

      // 30 minutes later a new interaction starts, and pi-a is still open as
      // far as Evidence knows.
      env.clock.current = t0.add(const Duration(minutes: 30));
      final b = _only(env.play(env.open('pi-b'), _evaluated(5)));

      expect(_dependencyInStore(env, a, b), EvidenceDependency.dependent);

      // The Practice Runtime now reports that pi-a ended at t0: the real gap to
      // pi-b is 30:00, which crosses the boundary.
      env.aggregator.recordInteractionEnd(closedA);

      expect(_dependencyInStore(env, a, b), EvidenceDependency.independent);
      expect(env.store.state.interactionWindow('pi-a')!.endedAt, t0);
    });

    test('an open interaction keeps every stored contribution in one group',
        () {
      final env = _Env(FakeClock(t0));
      // pi-a is never ended, so its contributions cannot be declared
      // independent from anything that follows it.
      env.play(env.open('pi-a'), _evaluated(5));
      env.clock.current = t0.add(const Duration(hours: 2));
      env.play(env.open('pi-b'), _evaluated(5));

      final pitch =
          env.store.state.streamFor(_identity(EvaluationDimension.pitch))!;
      expect(pitch.groups, hasLength(1));
      expect(pitch.groups.single.contributions, hasLength(2));
    });
  });

  group('deterministic aggregation and grouping (EVG-009/EVG-010)', () {
    test('aggregation is a pure function of the contributions', () {
      final env = _Env(FakeClock(t0));
      env.play(env.open('pi-1'), _evaluated(5));

      final once = EvidenceAggregation.aggregate(env.store.state.contributions);
      final twice = EvidenceAggregation.aggregate(env.store.state.contributions);

      expect(once, twice);
      expect(once.hashCode, twice.hashCode);
      expect(env.store.state, once);
    });

    test('groups are delimited by independence boundaries', () {
      final env = _Env(FakeClock(t0));
      // Interaction A: two attempts, ends at t0 + 1m.
      env.clock.current = t0;
      final runtimeA = env.open('pi-a');
      env.play(runtimeA, _evaluated(5));
      env.clock.current = t0.add(const Duration(minutes: 1));
      env.play(runtimeA, _evaluated(5));
      env.end(runtimeA);

      // 14:59 after A ended -> dependent, so it stays in the same group.
      env.clock.current = t0.add(const Duration(minutes: 15, seconds: 59));
      final runtimeB = env.open('pi-b');
      env.play(runtimeB, _evaluated(5));
      env.end(runtimeB);

      // 15:00 after B ended -> independent, so a new group starts.
      env.clock.current = t0.add(const Duration(minutes: 30, seconds: 59));
      final runtimeC = env.open('pi-c');
      env.play(runtimeC, _evaluated(5));
      env.end(runtimeC);

      final pitch = env.store.state.streamFor(_identity(EvaluationDimension.pitch))!;
      expect(pitch.contributionCount, 4);
      expect(pitch.groups.map((g) => g.length), <int>[3, 1]);
      expect(pitch.groups.last.contributions.single.provenance
          .practiceInteractionId, 'pi-c');
    });

    test('a group is anchored on its first contribution, not chained', () {
      final env = _Env(FakeClock(t0));
      final a = env.contribute('pi-a', at: t0);
      // 14:59 after A ended: dependent of the anchor.
      final b = env.contribute(
          'pi-b', at: t0.add(const Duration(minutes: 14, seconds: 59)));
      // 14:59 after B ended (dependent of B) but 29:58 after A ended
      // (independent of the group anchor) -> starts a new group.
      final c = env.contribute(
          'pi-c', at: t0.add(const Duration(minutes: 29, seconds: 58)));

      expect(_dependencyInStore(env, a, b), EvidenceDependency.dependent);
      expect(_dependencyInStore(env, a, c), EvidenceDependency.independent);
      expect(_dependencyInStore(env, b, c), EvidenceDependency.dependent);

      final pitch = env.store.state.streamFor(_identity(EvaluationDimension.pitch))!;
      expect(pitch.groups.map((g) => g.length), <int>[2, 1]);
      expect(pitch.groups.first.contributions, <EvidenceContribution>[a, b]);
      expect(pitch.groups.last.contributions, <EvidenceContribution>[c]);
    });

    test('group identity is content derived and survives a rebuild', () {
      final env = _Env(FakeClock(t0));
      env.contribute('pi-a', at: t0);
      env.contribute('pi-b', at: t0.add(const Duration(minutes: 30)));

      final rebuilt = InMemoryEvidenceStore(
        contributions: env.store.state.contributions,
        interactionWindows: env.store.state.interactionWindows,
      );

      expect(rebuilt.state.groups.map((g) => g.id),
          env.store.state.groups.map((g) => g.id));
      expect(rebuilt.state, env.store.state);
      for (final group in rebuilt.state.groups) {
        expect(group.id, startsWith('evidence-group:'));
        expect(
          group.id,
          endsWith(group.contributions.first.id),
          reason: 'group identity is anchored on its first contribution',
        );
      }
    });

    test('every group holds only contributions of its own stream', () {
      final env = _Env(FakeClock(t0));
      env.play(env.open('pi-1'), _evaluated(5));

      for (final group in env.store.state.groups) {
        for (final contribution in group.contributions) {
          expect(contribution.identity, group.identity);
        }
      }
    });
  });

  group('immutability (EVG-021)', () {
    test('returned collections cannot mutate stored evidence', () {
      final env = _Env(FakeClock(t0));
      final outcome = env.play(env.open('pi-1'), _evaluated(5));

      expect(() => outcome.contributions.clear(), throwsUnsupportedError);
      expect(() => env.store.state.contributions.clear(),
          throwsUnsupportedError);
      expect(() => env.store.state.streams.clear(), throwsUnsupportedError);
      expect(() => env.store.state.groups.clear(), throwsUnsupportedError);
      expect(
          () => env.store.state.groups.first.contributions.clear(),
          throwsUnsupportedError);
      expect(() => env.store.state.streams.first.contributions.clear(),
          throwsUnsupportedError);
      expect(() => env.store.contributions.clear(), throwsUnsupportedError);
      expect(env.store.state.contributions, hasLength(3));
    });

    test('a mutated source collection cannot mutate aggregated evidence', () {
      final env = _Env(FakeClock(t0));
      env.play(env.open('pi-1'), _evaluated(5));
      final source = <EvidenceContribution>[...env.store.state.contributions];

      final aggregated = EvidenceAggregation.aggregate(source);
      source.clear();

      expect(aggregated.contributions, hasLength(3));
      expect(aggregated.streams, hasLength(3));
      expect(env.store.state.contributions, hasLength(3));
    });

    test('two equal contributions are indistinguishable after recording', () {
      final first = _Env(FakeClock(t0));
      final second = _Env(FakeClock(t0));

      final a = _only(first.play(first.open('pi-1'), _evaluated(5)));
      final b = _only(second.play(second.open('pi-1'), _evaluated(5)));

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.id, b.id);
    });

    test('a contribution cannot be built with stars outside 0..5', () {
      EvidenceProvenance provenance() => EvidenceProvenance(
            targetId: _blockTargetId,
            mode: TargetMode.block,
            captureSessionId: 'session-1',
            evaluationProfileId: 'mvp_default_v1',
            evaluationProfileVersion: 'v1.1',
            alignmentAlgorithmVersion: '1',
            observationExtractionAlgorithmVersion: '1',
            preparationAlgorithmVersion: '1',
            evaluationFlowAlgorithmVersion: '1',
            practiceInteractionId: 'pi-1',
            executionSessionId: 'es-pi-1',
            practiceItemId: 'pi-1-item-0',
            attemptId: 'pi-1-item-0-attempt-1',
            practiceInteractionStartedAt: t0,
          );

      expect(
        () => EvidenceContribution(
          identity: _identity(EvaluationDimension.pitch),
          kind: EvidenceContributionKind.practiceAttempt,
          provenance: provenance(),
          stars: 6,
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          createdAt: t0,
        ),
        throwsFormatException,
      );
      expect(
        () => EvidenceContribution(
          identity: _identity(EvaluationDimension.pitch),
          kind: EvidenceContributionKind.practiceAttempt,
          provenance: provenance(),
          stars: 3,
          dimensionState: EvaluationDimensionState.enabled,
          dataAvailability: DataAvailability.available,
          createdAt: t0,
        ),
        returnsNormally,
      );
    });
  });

  group('read model', () {
    test('the store is the whole read surface and hides storage details', () {
      final env = _Env(FakeClock(t0));
      env.play(env.open('pi-1'), _evaluated(5));

      expect(env.store.state.streams, hasLength(3));
      expect(
        env.store.state.streams.map((s) => s.identity.streamId).toList(),
        <String>[
          'evidence:major-c-rh-block:pitch',
          'evidence:major-c-rh-block:simultaneity',
          'evidence:major-c-rh-block:timing',
        ],
      );
      expect(env.store.streamFor(_identity(EvaluationDimension.pitch)),
          isNotNull);
      expect(
        env.store.streamFor(EvidenceIdentity(
            targetId: 'major-c-rh-arpeggio',
            dimension: EvaluationDimension.pitch)),
        isNull,
      );
      expect(env.store.contributionById('nope'), isNull);
    });

    test('an untouched store reads as empty', () {
      final store = InMemoryEvidenceStore();

      expect(store.state.contributions, isEmpty);
      expect(store.state.streams, isEmpty);
      expect(store.state.groups, isEmpty);
    });
  });
}
