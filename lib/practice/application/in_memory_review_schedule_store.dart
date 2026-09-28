import 'review_schedule_store.dart';
import 'review_scheduler.dart';

/// In-memory [ReviewScheduleStore] for tests and in-memory sessions.
/// Not thread-safe; intended for single-isolate use.
class InMemoryReviewScheduleStore implements ReviewScheduleStore {
  final Map<String, ReviewScheduleState> _statesBySkillId =
      <String, ReviewScheduleState>{};

  @override
  Future<ReviewScheduleState?> read(String skillId) async =>
      _statesBySkillId[skillId];

  @override
  Future<List<ReviewScheduleState>> readAll() async =>
      _statesBySkillId.values.toList(growable: false);

  @override
  Future<void> write(ReviewScheduleState state) async {
    _statesBySkillId[state.skillId] = state;
  }
}