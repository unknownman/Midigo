import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/midi/domain/evaluation_result.dart';
import 'package:miditutor/practice/application/in_memory_lesson_progress_store.dart';
import 'package:miditutor/practice/application/in_memory_review_schedule_store.dart';
import 'package:miditutor/practice/application/lesson_progress_service.dart';
import 'package:miditutor/practice/application/spaced_review_scheduler.dart';

import 'fakes.dart';

void main() {
  const targetId = 'major-c-rh-block';
  final start = DateTime(2025, 3, 3, 9, 0, 0);

  late InMemoryLessonProgressStore store;
  late FakeClock clock;
  late SpacedReviewScheduler scheduler;
  late LessonProgressService service;

  EvaluatedResult result(int stars) =>
      EvaluatedResult(stars: stars, dimensions: const []);

  /// Records a sequence of detached star chunks summing to the lesson capacity.
  Future<void> recordStars(List<int> chunks) async {
    for (final stars in chunks) {
      await service.recordResult(targetId: targetId, result: result(stars));
    }
  }

  setUp(() {
    store = InMemoryLessonProgressStore();
    clock = FakeClock(start);
    scheduler = SpacedReviewScheduler(
      store: InMemoryReviewScheduleStore(),
      clock: clock,
      orderedSkillIds: const [targetId],
    );
    service = LessonProgressService(store: store, reviewScheduler: scheduler);
  });

  group('H2.9.3 eligibility registration', () {
    test('9/10 -> 10/10 transition registers the skill once', () async {
      await recordStars([5, 4]);
      expect((await scheduler.getState(targetId)).reviewEligible, isFalse);

      await service.recordResult(targetId: targetId, result: result(4));
      final state = await scheduler.getState(targetId);
      expect(state.reviewEligible, isTrue);
      expect(state.skillId, targetId);
      expect(state.currentIntervalDays,
          SpacedReviewScheduler.initialIntervalDays);
      expect(state.reviewCount, 0);
    });

    test('completion via a 1-star transition also registers', () async {
      await recordStars([5, 4]);
      await service.recordResult(targetId: targetId, result: result(1));
      final state = await scheduler.getState(targetId);
      expect(state.reviewEligible, isTrue);
      expect(state.currentIntervalDays, 1);
    });

    test('a first attempt never registers', () async {
      await service.recordResult(targetId: targetId, result: result(4));
      expect((await scheduler.getState(targetId)).reviewEligible, isFalse);
    });

    test('NotEnoughPerformance result never registers', () async {
      await service.recordResult(
        targetId: targetId,
        result: NotEnoughPerformanceResult(dimensions: const []),
      );
      expect((await scheduler.getState(targetId)).reviewEligible, isFalse);
    });

    test('an in-progress accumulation (5 + 4 = 9) does not register', () async {
      await recordStars([5, 4]);
      expect((await scheduler.getState(targetId)).reviewEligible, isFalse);
    });

    test('re-recording on an already-completed lesson never re-registers',
        () async {
      await recordStars([5, 5]);
      expect((await scheduler.getState(targetId)).reviewEligible, isTrue);

      await service.recordResult(targetId: targetId, result: result(5));
      expect((await scheduler.getState(targetId)).reviewEligible, isTrue);
      expect((await scheduler.getState(targetId)).reviewCount, 0);
    });

    test('scheduler never reads lesson progress (orchestration boundary)',
        () async {
      // Eligibility is driven by registerEligibleSkill alone - a lesson with
      // zero progress records is still eligible the moment it is registered by
      // the completion transition (a lesson cannot be 10/10 with zero records,
      // but a scheduler record does not depend on lesson records at all).
      await scheduler.registerEligibleSkill(targetId);
      final state = await scheduler.getState(targetId);
      expect(state.reviewEligible, isTrue);
    });
  });
}