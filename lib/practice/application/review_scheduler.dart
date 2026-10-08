import 'package:miditutor/midi/domain/evaluation_result.dart';

/// Response a learner gives to a scheduled review, per the Review Scheduler
/// Contract v1.2.
enum ReviewResponse {
  successfulReview,
  unsuccessfulReview,
  iAlreadyKnow,
}

/// Sentinel timestamp used for records that are not eligible. A not-eligible
  /// record must never appear ready, so its [nextReviewAt] is far in the future.
final class ReviewScheduleState {
  final String skillId;
  final bool reviewEligible;
  final DateTime nextReviewAt;
  final int currentIntervalDays;
  final int reviewCount;
  final int successfulReviewCount;
  final int unsuccessfulReviewCount;
  final ReviewResponse? lastResponse;

  const ReviewScheduleState({
    required this.skillId,
    required this.reviewEligible,
    required this.nextReviewAt,
    required this.currentIntervalDays,
    required this.reviewCount,
    required this.successfulReviewCount,
    required this.unsuccessfulReviewCount,
    this.lastResponse,
  });

  static final DateTime neverDue = DateTime(2100, 1, 1);

  /// The not-eligible sentinel shown for any skill with no established review
  /// record (a missing record is equivalent to not eligible).
  static final ReviewScheduleState notEligible = ReviewScheduleState(
    skillId: '',
    reviewEligible: false,
    nextReviewAt: neverDue,
    currentIntervalDays: 0,
    reviewCount: 0,
    successfulReviewCount: 0,
    unsuccessfulReviewCount: 0,
    lastResponse: null,
  );

  ReviewScheduleState copyWith({
    bool? reviewEligible,
    DateTime? nextReviewAt,
    int? currentIntervalDays,
    int? reviewCount,
    int? successfulReviewCount,
    int? unsuccessfulReviewCount,
    ReviewResponse? lastResponse,
  }) {
    return ReviewScheduleState(
      skillId: skillId,
      reviewEligible: reviewEligible ?? this.reviewEligible,
      nextReviewAt: nextReviewAt ?? this.nextReviewAt,
      currentIntervalDays: currentIntervalDays ?? this.currentIntervalDays,
      reviewCount: reviewCount ?? this.reviewCount,
      successfulReviewCount:
          successfulReviewCount ?? this.successfulReviewCount,
      unsuccessfulReviewCount:
          unsuccessfulReviewCount ?? this.unsuccessfulReviewCount,
      lastResponse: lastResponse ?? this.lastResponse,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'skillId': skillId,
      'reviewEligible': reviewEligible,
      'nextReviewAt': nextReviewAt.toIso8601String(),
      'currentIntervalDays': currentIntervalDays,
      'reviewCount': reviewCount,
      'successfulReviewCount': successfulReviewCount,
      'unsuccessfulReviewCount': unsuccessfulReviewCount,
      if (lastResponse != null) 'lastResponse': lastResponse!.name,
    };
  }

  factory ReviewScheduleState.fromMap(Map<String, Object?> map) {
    final nextReviewAt = DateTime.tryParse(map['nextReviewAt']! as String);
    if (nextReviewAt == null) {
      throw const FormatException('Invalid nextReviewAt timestamp');
    }
    final lastResponseName = map['lastResponse'] as String?;
    ReviewResponse? lastResponse;
    if (lastResponseName != null) {
      lastResponse = ReviewResponse.values.firstWhere(
        (response) => response.name == lastResponseName,
        orElse: () => throw const FormatException('Invalid lastResponse'),
      );
    }
    return ReviewScheduleState(
      skillId: map['skillId']! as String,
      reviewEligible: map['reviewEligible']! as bool,
      nextReviewAt: nextReviewAt,
      currentIntervalDays: map['currentIntervalDays']! as int,
      reviewCount: map['reviewCount']! as int,
      successfulReviewCount: map['successfulReviewCount']! as int,
      unsuccessfulReviewCount: map['unsuccessfulReviewCount']! as int,
      lastResponse: lastResponse,
    );
  }

  @override
  String toString() =>
      'ReviewScheduleState(skillId: $skillId, reviewEligible: $reviewEligible, '
      'nextReviewAt: $nextReviewAt, currentIntervalDays: $currentIntervalDays, '
      'reviewCount: $reviewCount, successfulReviewCount: $successfulReviewCount, '
      'unsuccessfulReviewCount: $unsuccessfulReviewCount)';
}

/// A review item surfaced by the Review Hub.
final class ReviewItem {
  final String skillId;
  final ReviewScheduleState state;

  const ReviewItem({required this.skillId, required this.state});
}

/// Maps an evaluation result to the scheduler response the learner earned.
///
/// `3 or more stars -> successfulReview`, `0..2 stars -> unsuccessfulReview`,
/// `NotEnoughPerformanceResult` and null (no result, e.g. abandoned or
/// invalidated) -> null, meaning no scheduler mutation is allowed.
ReviewResponse? reviewResponseFor(EvaluationResult? result) {
  if (result is EvaluatedResult) {
    return result.stars >= 3
        ? ReviewResponse.successfulReview
        : ReviewResponse.unsuccessfulReview;
  }
  return null;
}

/// The scheduler facing the rest of the app (Review Hub / Review Session).
///
/// Everything the app needs to refuse re-implementing scheduling logic.
abstract interface class ReviewScheduler {
  Future<ReviewScheduleState> getState(String skillId);

  /// All skills that are eligible and due at or before `clock.now()`,
  /// in the deterministic skill order the scheduler was configured with.
  Future<List<ReviewItem>> getReadyReviews();

  /// Marks a skill as eligible for review. Idempotent.
  Future<void> registerEligibleSkill(String skillId);

  /// Records a review response. Mutative only when the learner advanced past
  /// the Review Result (commit point); NEP / abandoned / invalidated attempts
  /// never produce a response.
  Future<void> recordReviewResponse(String skillId, ReviewResponse response);
}