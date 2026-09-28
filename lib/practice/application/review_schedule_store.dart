import 'review_scheduler.dart';

/// Persistence for the review scheduler.
abstract interface class ReviewScheduleStore {
  Future<ReviewScheduleState?> read(String skillId);

  Future<List<ReviewScheduleState>> readAll();

  Future<void> write(ReviewScheduleState state);
}