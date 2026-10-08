import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/midi/domain/evaluation_result.dart';
import 'package:miditutor/practice/application/json_review_schedule_store.dart';
import 'package:miditutor/practice/application/review_scheduler.dart';
import 'package:miditutor/practice/application/spaced_review_scheduler.dart';

import 'fakes.dart';

void main() {
  final start = DateTime(2025, 3, 3, 9, 0, 0);

  late FakeClock clock;
  late SpacedReviewScheduler scheduler;

  EvaluatedResult result(int stars) =>
      EvaluatedResult(stars: stars, dimensions: const []);

  Future<ReviewScheduleState> makeEligible(String skillId) async {
    await scheduler.registerEligibleSkill(skillId);
    return scheduler.getState(skillId);
  }

  setUp(() {
    clock = FakeClock(start);
    scheduler = newFakeReviewScheduler(clock);
  });

  group('Review Scheduler Contract cases', () {
    test('unregistered skill is not eligible', () async {
      final state = await scheduler.getState('major-c-lh-block');
      expect(state.reviewEligible, isFalse);
    });

    test('missing record means not eligible and never ready', () async {
      final ready = await scheduler.getReadyReviews();
      expect(ready, isEmpty);
      expect((await scheduler.getState('major-c-lh-block')).reviewEligible,
          isFalse);
    });

    test('registerEligibleSkill creates an eligible record', () async {
      final state = await makeEligible('major-c-rh-block');
      expect(state.reviewEligible, isTrue);
      expect(state.skillId, 'major-c-rh-block');
    });

    test('initial current interval is D0 = 1 day', () async {
      final state = await makeEligible('major-c-rh-block');
      expect(state.currentIntervalDays, SpacedReviewScheduler.initialIntervalDays);
      expect(state.currentIntervalDays, 1);
    });

    test('initial nextReviewAt is register time + 1 day', () async {
      final state = await makeEligible('major-c-rh-block');
      expect(state.nextReviewAt, start.add(const Duration(days: 1)));
    });

    test('an exactly-on-time item is ready (inclusive due)', () async {
      await makeEligible('major-c-rh-block');
      clock.current = start.add(const Duration(days: 1));
      final ready = await scheduler.getReadyReviews();
      expect([for (final item in ready) item.skillId], [
        'major-c-rh-block',
      ]);
    });

    test('an item before its due time is not ready', () async {
      await makeEligible('major-c-rh-block');
      clock.current = start.add(const Duration(days: 1)).subtract(
        const Duration(hours: 1),
      );
      expect(await scheduler.getReadyReviews(), isEmpty);
    });

    test('a successful review doubles the interval and moves it out', () async {
      final registered = await makeEligible('major-c-rh-block');
      await scheduler.recordReviewResponse(
          'major-c-rh-block', ReviewResponse.successfulReview);
      final state = await scheduler.getState('major-c-rh-block');
      expect(state.currentIntervalDays, registered.currentIntervalDays * 2);
      expect(state.nextReviewAt,
          clock.current.add(const Duration(days: 2)));
    });

    test('a successful review caps the interval at Dmax = 21', () async {
      await makeEligible('major-c-rh-block');
      // Drive 1 -> 2 -> 4 -> 8 -> 16 -> 21 -> 21.
      for (var i = 0; i < 6; i++) {
        await scheduler.recordReviewResponse(
            'major-c-rh-block', ReviewResponse.successfulReview);
        final state = await scheduler.getState('major-c-rh-block');
        expect(state.currentIntervalDays, lessThanOrEqualTo(21));
      }
      final state = await scheduler.getState('major-c-rh-block');
      expect(state.currentIntervalDays, SpacedReviewScheduler.maximumIntervalDays);
    });

    test('an unsuccessful review halves the interval', () async {
      await makeEligible('major-c-rh-block');
      await scheduler.recordReviewResponse(
          'major-c-rh-block', ReviewResponse.successfulReview);
      final boosted = await scheduler.getState('major-c-rh-block');
      expect(boosted.currentIntervalDays, 2);
      await scheduler.recordReviewResponse(
          'major-c-rh-block', ReviewResponse.unsuccessfulReview);
      final state = await scheduler.getState('major-c-rh-block');
      expect(state.currentIntervalDays, 1);
    });

    test('an unsuccessful review floors the interval at Dmin = 1', () async {
      await makeEligible('major-c-rh-block');
      await scheduler.recordReviewResponse(
          'major-c-rh-block', ReviewResponse.unsuccessfulReview);
      final state = await scheduler.getState('major-c-rh-block');
      expect(state.currentIntervalDays, SpacedReviewScheduler.minimumIntervalDays);
      expect(state.currentIntervalDays, 1);
    });

    test('an I Already Know review halves the interval', () async {
      await makeEligible('major-c-rh-block');
      // Drive to interval 8.
      for (var i = 0; i < 3; i++) {
        await scheduler.recordReviewResponse(
            'major-c-rh-block', ReviewResponse.successfulReview);
      }
      final boosted = await scheduler.getState('major-c-rh-block');
      expect(boosted.currentIntervalDays, 8);
      await scheduler.recordReviewResponse(
          'major-c-rh-block', ReviewResponse.iAlreadyKnow);
      final state = await scheduler.getState('major-c-rh-block');
      expect(state.currentIntervalDays, 4);
      expect(state.lastResponse, ReviewResponse.iAlreadyKnow);
    });

    test('an I Already Know review floors the interval at Dmin', () async {
      await makeEligible('major-c-rh-block');
      await scheduler.recordReviewResponse(
          'major-c-rh-block', ReviewResponse.iAlreadyKnow);
      final state = await scheduler.getState('major-c-rh-block');
      expect(state.currentIntervalDays, SpacedReviewScheduler.minimumIntervalDays);
    });

    test('successful reviews increment counts and keep the invariant', () async {
      await makeEligible('major-c-rh-block');
      await scheduler.recordReviewResponse(
          'major-c-rh-block', ReviewResponse.successfulReview);
      final state = await scheduler.getState('major-c-rh-block');
      expect(state.reviewCount, 1);
      expect(state.successfulReviewCount, 1);
      expect(state.unsuccessfulReviewCount, 0);
      expect(state.reviewCount,
          state.successfulReviewCount + state.unsuccessfulReviewCount);
    });

    test('unsuccessful reviews increment counts and keep the invariant', () async {
      await makeEligible('major-c-rh-block');
      await scheduler.recordReviewResponse(
          'major-c-rh-block', ReviewResponse.unsuccessfulReview);
      final state = await scheduler.getState('major-c-rh-block');
      expect(state.reviewCount, 1);
      expect(state.unsuccessfulReviewCount, 1);
      expect(state.successfulReviewCount, 0);
      expect(state.reviewCount,
          state.successfulReviewCount + state.unsuccessfulReviewCount);
    });

    test('I Already Know never increments counts (Contract §5/§11)', () async {
      await makeEligible('major-c-rh-block');
      await scheduler.recordReviewResponse(
          'major-c-rh-block', ReviewResponse.iAlreadyKnow);
      final state = await scheduler.getState('major-c-rh-block');
      expect(state.reviewCount, 0);
      expect(state.successfulReviewCount, 0);
      expect(state.unsuccessfulReviewCount, 0);
    });

    test('counts never affect transition math', () async {
      final lowCount = ReviewScheduleState(
        skillId: 'x',
        reviewEligible: true,
        nextReviewAt: clock.current,
        currentIntervalDays: 8,
        reviewCount: 1,
        successfulReviewCount: 1,
        unsuccessfulReviewCount: 0,
        lastResponse: ReviewResponse.successfulReview,
      );
      final highCount = ReviewScheduleState(
        skillId: 'x',
        reviewEligible: true,
        nextReviewAt: clock.current,
        currentIntervalDays: 8,
        reviewCount: 42,
        successfulReviewCount: 40,
        unsuccessfulReviewCount: 2,
        lastResponse: ReviewResponse.successfulReview,
      );
      final a = SpacedReviewScheduler.transition(
        state: lowCount,
        response: ReviewResponse.successfulReview,
        now: clock.current,
      );
      final b = SpacedReviewScheduler.transition(
        state: highCount,
        response: ReviewResponse.successfulReview,
        now: clock.current,
      );
      expect(a.currentIntervalDays, b.currentIntervalDays);
      expect(a.nextReviewAt, b.nextReviewAt);
    });

    test('ready reviews follow catalog order deterministically', () async {
      await makeEligible('major-c-rh-arpeggio');
      await makeEligible('major-c-rh-block');
      await makeEligible('major-c-bothUnison-arpeggio');
      clock.current = start.add(const Duration(days: 2));
      final ready = await scheduler.getReadyReviews();
      expect([for (final item in ready) item.skillId], [
        'major-c-rh-block',
        'major-c-rh-arpeggio',
        'major-c-bothUnison-arpeggio',
      ]);
    });

    test('duplicate eligibility registration is safe and idempotent', () async {
      await makeEligible('major-c-rh-block');
      await scheduler.registerEligibleSkill('major-c-rh-block');
      final state = await scheduler.getState('major-c-rh-block');
      expect(state.reviewEligible, isTrue);
      expect(state.reviewCount, 0);
      expect(state.currentIntervalDays, 1);
    });

    test('a skill outside the catalog order is never surfaced ready', () async {
      await scheduler.registerEligibleSkill('unknown-skill');
      clock.current = start.add(const Duration(days: 30));
      expect(await scheduler.getReadyReviews(), isEmpty);
    });

    test('a recorded response returns an updated immutable state', () async {
      final before = await makeEligible('major-c-rh-block');
      await scheduler.recordReviewResponse(
          'major-c-rh-block', ReviewResponse.successfulReview);
      expect(before.reviewCount, 0);
      expect(before.currentIntervalDays, 1);
      final after = await scheduler.getState('major-c-rh-block');
      expect(after.reviewCount, 1);
      expect(after.currentIntervalDays, 2);
    });
  });

  group('reviewResponseFor mapping (Contract §9)', () {
    test('3 stars and above maps to successfulReview', () {
      expect(reviewResponseFor(result(5)), ReviewResponse.successfulReview);
      expect(reviewResponseFor(result(3)), ReviewResponse.successfulReview);
    });

    test('0..2 stars maps to unsuccessfulReview', () {
      expect(reviewResponseFor(result(2)), ReviewResponse.unsuccessfulReview);
      expect(reviewResponseFor(result(0)), ReviewResponse.unsuccessfulReview);
    });

    test('NotEnoughPerformanceResult maps to null (no mutation)', () {
      expect(
        reviewResponseFor(NotEnoughPerformanceResult(dimensions: const [])),
        isNull,
      );
    });

    test('null result (abandoned/invalidated) maps to null', () {
      expect(reviewResponseFor(null), isNull);
    });
  });

  group('response vocabulary alignment (Contract §7)', () {
    test('ReviewResponse values are exactly the contract vocabulary', () {
      expect(
        [for (final response in ReviewResponse.values) response.name],
        ['successfulReview', 'unsuccessfulReview', 'iAlreadyKnow'],
      );
    });

    test('each response serializes to its canonical contract name', () {
      expect(ReviewResponse.successfulReview.name, 'successfulReview');
      expect(ReviewResponse.unsuccessfulReview.name, 'unsuccessfulReview');
      expect(ReviewResponse.iAlreadyKnow.name, 'iAlreadyKnow');
    });

    test('lastResponse round-trips through toMap/fromMap for every response',
        () {
      for (final response in ReviewResponse.values) {
        final state = ReviewScheduleState(
          skillId: 'major-c-rh-block',
          reviewEligible: true,
          nextReviewAt: start.add(const Duration(days: 1)),
          currentIntervalDays: 1,
          reviewCount: 1,
          successfulReviewCount: 1,
          unsuccessfulReviewCount: 0,
          lastResponse: response,
        );
        final map = state.toMap();
        expect(map['lastResponse'], response.name);
        final decoded = ReviewScheduleState.fromMap(map);
        expect(decoded.lastResponse, response);
      }
    });

    test('fromMap rejects a non-canonical legacy response name', () {
      final map = ReviewScheduleState(
        skillId: 'major-c-rh-block',
        reviewEligible: true,
        nextReviewAt: start.add(const Duration(days: 1)),
        currentIntervalDays: 1,
        reviewCount: 0,
        successfulReviewCount: 0,
        unsuccessfulReviewCount: 0,
        lastResponse: ReviewResponse.successfulReview,
      ).toMap()
        ..['lastResponse'] = 'successful';
      expect(
        () => ReviewScheduleState.fromMap(map),
        throwsFormatException,
      );
    });

    test('the three transitions are unchanged by the vocabulary alignment',
        () {
      ReviewScheduleState state() => ReviewScheduleState(
            skillId: 'major-c-rh-block',
            reviewEligible: true,
            nextReviewAt: start,
            currentIntervalDays: 8,
            reviewCount: 5,
            successfulReviewCount: 3,
            unsuccessfulReviewCount: 2,
            lastResponse: ReviewResponse.successfulReview,
          );

      final success = SpacedReviewScheduler.transition(
        state: state(),
        response: ReviewResponse.successfulReview,
        now: start,
      );
      expect(success.currentIntervalDays, 16); // min(8 * 2, 21)
      expect(success.reviewCount, 6);
      expect(success.successfulReviewCount, 4);
      expect(success.unsuccessfulReviewCount, 2);

      final failure = SpacedReviewScheduler.transition(
        state: state(),
        response: ReviewResponse.unsuccessfulReview,
        now: start,
      );
      expect(failure.currentIntervalDays, 4); // max(8 ~/ 2, 1)
      expect(failure.reviewCount, 6);
      expect(failure.successfulReviewCount, 3);
      expect(failure.unsuccessfulReviewCount, 3);

      // Contract §11/§17: iAlreadyKnow increments none of the counts.
      final iak = SpacedReviewScheduler.transition(
        state: state(),
        response: ReviewResponse.iAlreadyKnow,
        now: start,
      );
      expect(iak.currentIntervalDays, 4); // max(8 ~/ 2, 1)
      expect(iak.reviewCount, 5);
      expect(iak.successfulReviewCount, 3);
      expect(iak.unsuccessfulReviewCount, 2);
      expect(iak.lastResponse, ReviewResponse.iAlreadyKnow);

      expect(
        success.reviewCount,
        success.successfulReviewCount + success.unsuccessfulReviewCount,
      );
      expect(
        failure.reviewCount,
        failure.successfulReviewCount + failure.unsuccessfulReviewCount,
      );
    });
  });

  group('review schedule persistence (H2.9.2)', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('review-schedule-test');
    });

    tearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Already gone.
      }
    });

    test('scheduler state persists through the JSON store', () async {
      final store = JsonReviewScheduleStore(root: dir);
      final scheduling = SpacedReviewScheduler(
        store: store,
        clock: FakeClock(start),
        orderedSkillIds: const ['major-c-rh-block'],
      );
      await scheduling.registerEligibleSkill('major-c-rh-block');
      await scheduling.recordReviewResponse(
          'major-c-rh-block', ReviewResponse.successfulReview);

      final reloaded = SpacedReviewScheduler(
        store: JsonReviewScheduleStore(root: dir),
        clock: FakeClock(start),
        orderedSkillIds: const ['major-c-rh-block'],
      );
      final state = await reloaded.getState('major-c-rh-block');
      expect(state.reviewEligible, isTrue);
      expect(state.currentIntervalDays, 2);
      expect(state.successfulReviewCount, 1);
      expect(state.reviewCount, 1);
    });

    test('JSON uses the documented camelCase map keys', () async {
      final store = JsonReviewScheduleStore(root: dir);
      await store.write(ReviewScheduleState(
        skillId: 'major-c-rh-block',
        reviewEligible: true,
        nextReviewAt: start.add(const Duration(days: 1)),
        currentIntervalDays: 1,
        reviewCount: 0,
        successfulReviewCount: 0,
        unsuccessfulReviewCount: 0,
        lastResponse: null,
      ));
      final file = File('${dir.path}${Platform.pathSeparator}'
          'review_schedule.json');
      final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final entry = decoded['major-c-rh-block'] as Map<String, dynamic>;
      expect(entry.keys, contains('skillId'));
      expect(entry.keys, contains('reviewEligible'));
      expect(entry.keys, contains('nextReviewAt'));
      expect(entry.keys, contains('currentIntervalDays'));
      expect(entry.keys, contains('reviewCount'));
      expect(entry.keys, contains('successfulReviewCount'));
      expect(entry.keys, contains('unsuccessfulReviewCount'));
    });

    test('a missing persisted record reloads as not eligible', () async {
      final store = JsonReviewScheduleStore(root: dir);
      final reloaded = SpacedReviewScheduler(
        store: store,
        clock: FakeClock(start),
        orderedSkillIds: const ['major-c-rh-block'],
      );
      final state = await reloaded.getState('major-c-rh-block');
      expect(state.reviewEligible, isFalse);
    });
  });
}