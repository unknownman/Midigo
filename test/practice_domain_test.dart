import 'package:flutter_test/flutter_test.dart';
import 'package:miditutor/midi/application/expected_musical_target_factory.dart';
import 'package:miditutor/midi/domain/expected_musical_target.dart';
import 'package:miditutor/practice/domain/attempt.dart';
import 'package:miditutor/practice/domain/exercise_instance.dart';
import 'package:miditutor/practice/domain/practice_clock.dart';
import 'package:miditutor/practice/domain/practice_interaction.dart';
import 'package:miditutor/practice/domain/practice_item.dart';

void main() {
  const ExpectedMusicalTargetFactory factory =
      ExpectedMusicalTargetFactory();

  final ExpectedMusicalTarget cMajorBlock = factory.build(
    quality: TargetQuality.major,
    root: TargetRoot.c,
    hand: TargetHand.right,
    mode: TargetMode.block,
    targetId: 'major-c-rh-block',
  );

  final ExerciseInstance cMajorInstance = ExerciseInstance(
    id: 'exercise-major-c-rh-block',
    expectedTarget: cMajorBlock,
  );

  final DateTime t0 = DateTime(2025, 1, 1, 10, 0, 0);
  final DateTime t1 = DateTime(2025, 1, 1, 10, 0, 5);
  final DateTime t2 = DateTime(2025, 1, 1, 10, 0, 9);

  group('PracticeClock', () {
    test('SystemPracticeClock returns a DateTime', () {
      expect(const SystemPracticeClock().now(), isA<DateTime>());
    });
  });

  group('ExerciseInstance', () {
    test('wraps a target and exposes deterministic identity', () {
      expect(cMajorInstance.id, 'exercise-major-c-rh-block');
      expect(cMajorInstance.targetId, 'major-c-rh-block');
      expect(cMajorInstance.expectedTarget, same(cMajorBlock));
    });

    test('rejects an empty id', () {
      expect(
        () => ExerciseInstance(id: '', expectedTarget: cMajorBlock),
        throwsFormatException,
      );
    });
  });

  group('Attempt lifecycle', () {
    test('equality of attempts is value-based on identity, item, state, time',
        () {
      final a = Attempt(
        id: 'attempt-1',
        practiceItemId: 'item-1',
        state: AttemptState.armed,
      );
      final b = Attempt(
        id: 'attempt-1',
        practiceItemId: 'item-1',
        state: AttemptState.armed,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('armed -> active records startedAt; startedAt is never clock-derived',
        () {
      final attempt = Attempt(
        id: 'attempt-1',
        practiceItemId: 'item-1',
        state: AttemptState.armed,
      ).copyWith(state: AttemptState.active, startedAt: t1);
      expect(attempt.state, AttemptState.active);
      expect(attempt.startedAt, t1);
      expect(attempt.endedAt, isNull);
    });

    test('active -> completed carries startedAt and endedAt from the clock', () {
      final attempt = Attempt(
        id: 'attempt-1',
        practiceItemId: 'item-1',
        state: AttemptState.active,
        startedAt: t1,
      ).copyWith(state: AttemptState.completed, endedAt: t2);
      expect(attempt.state, AttemptState.completed);
      expect(attempt.startedAt, t1);
      expect(attempt.endedAt, t2);
    });

    test('a completed attempt requires startedAt and endedAt', () {
      expect(
        () => Attempt(
          id: 'attempt-1',
          practiceItemId: 'item-1',
          state: AttemptState.completed,
          startedAt: t1,
        ),
        throwsFormatException,
      );
      expect(
        () => Attempt(
          id: 'attempt-1',
          practiceItemId: 'item-1',
          state: AttemptState.completed,
          endedAt: t2,
        ),
        throwsFormatException,
      );
    });
  });

  group('AttemptLifecycle', () {
    test('allowed transitions match the locked table', () {
      expect(
        AttemptLifecycle.allowedFrom(AttemptState.armed),
        containsAll(<AttemptState>[
          AttemptState.active,
          AttemptState.abandoned,
          AttemptState.invalidated,
        ]),
      );
      expect(
        AttemptLifecycle.allowedFrom(AttemptState.active),
        containsAll(<AttemptState>[
          AttemptState.paused,
          AttemptState.completed,
          AttemptState.abandoned,
          AttemptState.invalidated,
        ]),
      );
      expect(
        AttemptLifecycle.allowedFrom(AttemptState.paused),
        containsAll(<AttemptState>[
          AttemptState.active,
          AttemptState.completed,
          AttemptState.abandoned,
          AttemptState.invalidated,
        ]),
      );
    });

    test('terminal states admit no transitions', () {
      for (final terminal in AttemptLifecycle.terminalStates) {
        expect(AttemptLifecycle.allowedFrom(terminal), isEmpty,
            reason: '$terminal must be terminal');
      }
    });

    test('paused does not go backwards to armed; no state reaches armed', () {
      expect(
          AttemptLifecycle.canTransition(AttemptState.paused, AttemptState.armed),
          isFalse);
      for (final from in AttemptState.values) {
        expect(AttemptLifecycle.canTransition(from, AttemptState.armed), isFalse,
            reason: 'nothing may return to armed from $from');
      }
    });

    test('no failed state exists in the vocabulary', () {
      expect(
        AttemptState.values.map((s) => s.name),
        isNot(contains('failed')),
      );
      expect(
        AttemptState.values,
        <AttemptState>[
          AttemptState.armed,
          AttemptState.active,
          AttemptState.paused,
          AttemptState.completed,
          AttemptState.abandoned,
          AttemptState.invalidated,
        ],
      );
    });
  });

  group('PracticeItem', () {
    test('references exactly one exercise instance and owns attempts', () {
      final item = PracticeItem(
        id: 'pi-major-c-rh-block',
        exerciseInstance: cMajorInstance,
      );
      expect(item.id, 'pi-major-c-rh-block');
      expect(item.targetId, 'major-c-rh-block');
      expect(item.attempts, isEmpty);
    });

    test('copyWith appends recorded attempts immutably', () {
      final item = PracticeItem(
        id: 'pi-major-c-rh-block',
        exerciseInstance: cMajorInstance,
      );
      final attempt = Attempt(
        id: 'attempt-1',
        practiceItemId: item.id,
        state: AttemptState.completed,
        startedAt: t1,
        endedAt: t2,
      );
      final updated = item.copyWith(attempts: [attempt]);
      expect(item.attempts, isEmpty);
      expect(updated.attempts, [attempt]);
    });
  });

  group('PracticeInteraction / ExecutionSession (PR-015)', () {
    test('interaction owns exactly one execution session with 1:1 ids', () {
      final session = ExecutionSession(
        id: 'es-pi-1',
        practiceInteractionId: 'pi-1',
      );
      final interaction = PracticeInteraction(
        id: 'pi-1',
        executionSession: session,
        startedAt: t0,
      );
      expect(interaction.executionSession.id, 'es-pi-1');
      expect(interaction.executionSession.practiceInteractionId, interaction.id);
      expect(interaction.endedAt, isNull);
      expect(interaction.endReason, isNull);
    });

    test('rejects a session that references a different interaction (1:1)', () {
      final session = ExecutionSession(
        id: 'es-pi-2',
        practiceInteractionId: 'pi-2',
      );
      expect(
        () => PracticeInteraction(
          id: 'pi-1',
          executionSession: session,
          startedAt: t0,
        ),
        throwsFormatException,
      );
    });

    test('endReason requires an endedAt timestamp', () {
      final session = ExecutionSession(
        id: 'es-pi-1',
        practiceInteractionId: 'pi-1',
      );
      expect(
        () => PracticeInteraction(
          id: 'pi-1',
          executionSession: session,
          startedAt: t0,
          endReason: PracticeInteractionEndReason.completed,
        ),
        throwsFormatException,
      );
    });

    test('copyWith ends an interaction deterministically', () {
      final session = ExecutionSession(
        id: 'es-pi-1',
        practiceInteractionId: 'pi-1',
      );
      final interaction = PracticeInteraction(
        id: 'pi-1',
        executionSession: session,
        startedAt: t0,
      ).copyWith(
        endedAt: t2,
        endReason: PracticeInteractionEndReason.completed,
      );
      expect(interaction.endedAt, t2);
      expect(interaction.endReason, PracticeInteractionEndReason.completed);
    });
  });
}