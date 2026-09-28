import 'dart:convert';
import 'dart:io';

import 'review_schedule_store.dart';
import 'review_scheduler.dart';

/// Zero-dependency [ReviewScheduleStore] backed by one deterministic JSON file.
///
/// The file holds a single map: `{skillId: ReviewScheduleState}`. Only
/// eligible records with an established schedule are persisted; a missing
/// record is equivalent to never eligible. Writes are atomic (write to a temp
/// file, then rename) so a crash never leaves a half-written record.
class JsonReviewScheduleStore implements ReviewScheduleStore {
  /// Root directory that will contain `review_schedule.json`.
  final Directory root;

  JsonReviewScheduleStore({required this.root});

  File get _file =>
      File('${root.path}${Platform.pathSeparator}review_schedule.json');

  @override
  Future<ReviewScheduleState?> read(String skillId) async {
    final map = await _readAll();
    final value = map[skillId];
    if (value == null) {
      return null;
    }
    if (value is! Map) {
      throw const FormatException(
          'JsonReviewScheduleStore: schedule entry must be a JSON object.');
    }
    return ReviewScheduleState.fromMap(Map<String, Object?>.from(value));
  }

  @override
  Future<List<ReviewScheduleState>> readAll() async {
    final map = await _readAll();
    return [
      for (final value in map.values)
        ReviewScheduleState.fromMap(Map<String, Object?>.from(value as Map)),
    ];
  }

  @override
  Future<void> write(ReviewScheduleState state) async {
    final map = await _readAll();
    map[state.skillId] = state.toMap();
    await _writeAll(map);
  }

  Future<Map<String, Object?>> _readAll() async {
    if (!await _file.exists()) {
      return <String, Object?>{};
    }
    final content = await _file.readAsString();
    final decoded = jsonDecode(content);
    if (decoded is! Map) {
      throw const FormatException(
          'JsonReviewScheduleStore: file root must be a JSON object.');
    }
    return Map<String, Object?>.from(decoded);
  }

  Future<void> _writeAll(Map<String, Object?> map) async {
    await root.create(recursive: true);
    final temp = File('${_file.path}.tmp');
    await temp.writeAsString(jsonEncode(map), flush: true);
    await temp.rename(_file.path);
  }
}