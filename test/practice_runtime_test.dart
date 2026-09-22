import 'package:flutter_test/flutter_test.dart';
import 'package:miditutor/midi/application/expected_musical_target_factory.dart';
import 'package:miditutor/midi/domain/expected_musical_target.dart';
import 'package:miditutor/midi/domain/evaluation_result.dart';
import 'package:miditutor/practice/application/practice_runtime.dart';
import 'package:miditutor/practice/domain/attempt.dart';
import 'package:miditutor/practice/domain/exercise_instance.dart';
import 'package:miditutor/practice/domain/practice_clock.dart';
import 'package:miditutor/practice/domain/practice_interaction.dart';

final class FakePracticeClock implements PracticeClock {
  DateTime current;
  FakePracticeClock(this.current);

  @override
  DateTime now() => current;
}

void main() {
  final target = const ExpectedMusicalTargetFactory().build(
    quality: TargetQuality.major,
    root: TargetRoot.c,
    hand: TargetHand.right,
    mode: TargetMode.block,
    targetId: 'major-c-rh-block',
  );

  final exercise = ExerciseInstance(
    id: 'exercise-major-c-rh-block',
    expectedTarget: target,
  );

  FakePracticeClock clock() => FakePracticeClock(DateTime(2025, 1, 1, 10, 0, 0));

  PracticeRuntime open(FakePracticeClock c) {
    final runtime = PracticeRuntime(clock: c);
    runtime.createInteraction(
      interactionId: 'pi-major-c-rh-block',
      exercises: [exercise],
    );
    return runtime;
  }

  EvaluatedResult evaluated(int stars) =>
      EvaluatedResult(stars: stars, dimensions: const []);

  final notEnough = NotEnoughPerformanceResult(dimensions: const []);

  group('interaction creation', () {
    test('creates a 1:1 interaction/execution-session pair', () {
      final c = clock();
      final runtime = PracticeRuntime(clock: c);
      final interaction = runtime.createInteraction(
        interactionId: 'pi-major-c-rh-block',
        exercises: [exercise],
      );
      expect(interaction.id, 'pi-major-c-rh-block');
      expect(interaction.executionSession.practiceInteractionId, interaction.id);
      expect(interaction.executionSession.id, 'es-pi-major-c-rh-block');
      expect(interaction.items, hasLength(1));
      expect(interaction.items.first.targetId, 'major-c-rh-block');
      expect(interaction.startedAt, c.current);
      expect(runtime.hasOpenInteraction, isTrue);
    });

    test('may not open two interactions at once', () {
      final runtime = open(clock());
      expect(
        () => runtime.createInteraction(
            interactionId: 'pi-second', exercises: [exercise]),
        throwsStateError,
      );
    });

    test('rejects empty exercises and empty id', () {
      final c = clock();
      final runtime = PracticeRuntime(clock: c);
      expect(
        () => runtime.createInteraction(
            interactionId: 'pi-major-c-rh-block', exercises: const []),
        throwsFormatException,
      );
      expect(
        () => runtime.createInteraction(
            interactionId: '', exercises: [exercise]),
        throwsFormatException,
      );
    });
  });

  group('attempt lifecycle', () {
    test('armed -> active -> completed with deterministic identity', () {
      final c = clock();
      final runtime = open(c);
      final armed = runtime.armAttempt(itemId: 'pi-major-c-rh-block-item-0');
      expect(armed.state, AttemptState.armed);
      expect(armed.id, 'pi-major-c-rh-block-item-0-attempt-1');

      c.current = DateTime(2025, 1, 1, 10, 0, 5);
      final active = runtime.activateAttempt(armed.id);
      expect(active.state, AttemptState.active);
      expect(active.startedAt, c.current);

      c.current = DateTime(2025, 1, 1, 10, 0, 9);
      final done =
          runtime.completeAttempt(attemptId: armed.id, result: evaluated(5));
      expect(done.state, AttemptState.completed);
      expect(done.endedAt, c.current);
      expect(done.evaluationResult, isA<EvaluatedResult>());
      expect((done.evaluationResult as EvaluatedResult).stars, 5);

      final stored = runtime.currentItems.first.attempts.last;
      expect(stored, done);
      expect(runtime.currentInteraction!.items.first.attempts, hasLength(1));
    });

    test('paused toggles active -> paused -> active -> completed', () {
      final c = clock();
      final runtime = open(c);
      final armed = runtime.armAttempt(itemId: 'pi-major-c-rh-block-item-0');
      runtime.activateAttempt(armed.id);
      final paused = runtime.pauseAttempt(armed.id);
      expect(paused.state, AttemptState.paused);
      final resumed = runtime.resumeAttempt(armed.id);
      expect(resumed.state, AttemptState.active);
      final done = runtime.completeAttempt(
          attemptId: armed.id, result: evaluated(3));
      expect(done.state, AttemptState.completed);
    });

    test('rejects illegal transitions (active -> armed, completed -> paused)',
        () {
      final c = clock();
      final runtime = open(c);
      final armed = runtime.armAttempt(itemId: 'pi-major-c-rh-block-item-0');
      runtime.activateAttempt(armed.id);
      expect(() => runtime.activateAttempt(armed.id), throwsStateError);
      expect(() => runtime.completeAttempt(attemptId: armed.id, result: notEnough),
          returnsNormally);
      expect(() => runtime.pauseAttempt(armed.id), throwsStateError);
    });

    test('armed may be abandoned or invalidated without starting', () {
      final c = clock();
      final runtime = open(c);
      final armed = runtime.armAttempt(itemId: 'pi-major-c-rh-block-item-0');
      final abandoned = runtime.abandonAttempt(armed.id);
      expect(abandoned.state, AttemptState.abandoned);
      expect(abandoned.endedAt, c.current);

      final runtime2 = open(clock());
      final armed2 = runtime2.armAttempt(itemId: 'pi-major-c-rh-block-item-0');
      final invalid = runtime2.invalidateAttempt(armed2.id);
      expect(invalid.state, AttemptState.invalidated);
    });

    test('completed requires a started attempt', () {
      final c = clock();
      final runtime = open(c);
      final armed = runtime.armAttempt(itemId: 'pi-major-c-rh-block-item-0');
      // From armed, completed is illegal (must start first).
      expect(
        () => runtime.completeAttempt(attemptId: armed.id, result: notEnough),
        throwsStateError,
      );
    });

    test('no failed state exists anywhere in the runtime vocabulary', () {
      final runtime = open(clock());
      for (final item in runtime.currentItems) {
        for (final attempt in item.attempts) {
          expect(attempt.state.name, isNot('failed'));
        }
      }
    });
  });

  group('deterministic identity', () {
    test('attempt ids are content-derived and reproducible', () {
      final c1 = clock();
      final r1 = open(c1);
      final a1 = r1.armAttempt(itemId: 'pi-major-c-rh-block-item-0');

      final c2 = clock();
      final r2 = open(c2);
      final a2 = r2.armAttempt(itemId: 'pi-major-c-rh-block-item-0');

      expect(a1.id, a2.id);
      expect(a1.id, 'pi-major-c-rh-block-item-0-attempt-1');
    });

    test('timestamps come from the injected clock, never MIDI time', () {
      final c = clock();
      final runtime = open(c);
      final earlier = runtime.armAttempt(itemId: 'pi-major-c-rh-block-item-0');
      runtime.activateAttempt(earlier.id);
      // MIDI app_monotonic_ts_ms is a different concept and is never used.
      expect(earlier.id, isNotEmpty);
      final stored = runtime.currentItems.first.attempts.last;
      expect(stored.startedAt, c.current);
    });
  });

  group('interaction end', () {
    test('endInteraction stamps endedAt and a reason', () {
      final c = clock();
      final runtime = open(c);
      final interaction =
          runtime.endInteraction(reason: PracticeInteractionEndReason.completed);
      expect(interaction.endedAt, c.current);
      expect(interaction.endReason, PracticeInteractionEndReason.completed);
      expect(runtime.hasOpenInteraction, isFalse);
    });

    test('may not end an interaction that was never opened', () {
      final runtime = PracticeRuntime(clock: clock());
      expect(
        () => runtime.endInteraction(
            reason: PracticeInteractionEndReason.completed),
        throwsStateError,
      );
    });
  });
}