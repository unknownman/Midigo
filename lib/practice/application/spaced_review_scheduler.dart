import 'package:miditutor/practice/domain/practice_clock.dart';

import 'review_schedule_store.dart';
import 'review_scheduler.dart';

/// Spaced repetition scheduler per the Review Scheduler Contract v1.2.
///
/// Pure, deterministic transition logic with an injected [PracticeClock];
/// never reads wall clock directly and never reads lesson progress. Eligibility
/// is established only via [ReviewScheduler.registerEligibleSkill].
final class SpacedReviewScheduler implements ReviewScheduler {
  SpacedReviewScheduler({
    required this._store,
    required this._clock,
    required List<String> orderedSkillIds,
  }) : _orderedSkillIds = List<String>.unmodifiable(orderedSkillIds);

  /// D0 — initial interval in days.
  static const int initialIntervalDays = 1;

  /// Dmin — minimum interval in days.
  static const int minimumIntervalDays = 1;

  /// Dmax — maximum interval in days.
  static const int maximumIntervalDays = 21;

  final ReviewScheduleStore _store;
  final PracticeClock _clock;
  final List<String> _orderedSkillIds;

  @override
  Future<ReviewScheduleState> getState(String skillId) async {
    final state = await _store.read(skillId);
    return state ?? ReviewScheduleState.notEligible;
  }

  @override
  Future<List<ReviewItem>> getReadyReviews() async {
    final now = _clock.now();
    final ready = <ReviewItem>[];
    for (final skillId in _orderedSkillIds) {
      final state = await getState(skillId);
      if (!state.reviewEligible) {
        continue;
      }
      if (state.nextReviewAt.compareTo(now) <= 0) {
        ready.add(ReviewItem(skillId: skillId, state: state));
      }
    }
    return ready;
  }

  @override
  Future<void> registerEligibleSkill(String skillId) async {
    final existing = await _store.read(skillId);
    if (existing != null && existing.reviewEligible) {
      return;
    }
    final now = _clock.now();
    final state = ReviewScheduleState(
      skillId: skillId,
      reviewEligible: true,
      nextReviewAt: now.add(Duration(days: initialIntervalDays)),
      currentIntervalDays: initialIntervalDays,
      reviewCount: 0,
      successfulReviewCount: 0,
      unsuccessfulReviewCount: 0,
      lastResponse: null,
    );
    await _store.write(state);
  }

  @override
  Future<void> recordReviewResponse(
      String skillId, ReviewResponse response) async {
    final state = await _store.read(skillId);
    if (state == null || !state.reviewEligible) {
      return;
    }
    final next =
        transition(state: state, response: response, now: _clock.now());
    await _store.write(next);
  }

  /// Pure transition for one recorded response. IAK never increments counts.
  static ReviewScheduleState transition({
    required ReviewScheduleState state,
    required ReviewResponse response,
    required DateTime now,
  }) {
    final previousInterval = state.currentIntervalDays;
    late final int interval;
    int successfulCount = state.successfulReviewCount;
    int unsuccessfulCount = state.unsuccessfulReviewCount;
    int reviewCount = state.reviewCount;
    switch (response) {
      case ReviewResponse.successful:
        interval = _capInterval(previousInterval * 2);
        successfulCount += 1;
        reviewCount += 1;
      case ReviewResponse.unsuccessful:
        interval = _floorInterval(previousInterval ~/ 2);
        unsuccessfulCount += 1;
        reviewCount += 1;
      case ReviewResponse.iAlreadyKnow:
        interval = _floorInterval(previousInterval ~/ 2);
    }
    return state.copyWith(
      nextReviewAt: now.add(Duration(days: interval)),
      currentIntervalDays: interval,
      reviewCount: reviewCount,
      successfulReviewCount: successfulCount,
      unsuccessfulReviewCount: unsuccessfulCount,
      lastResponse: response,
    );
  }

  static int _capInterval(int interval) {
    if (interval > maximumIntervalDays) {
      return maximumIntervalDays;
    }
    return interval;
  }

  static int _floorInterval(int interval) {
    if (interval < minimumIntervalDays) {
      return minimumIntervalDays;
    }
    return interval;
  }
}