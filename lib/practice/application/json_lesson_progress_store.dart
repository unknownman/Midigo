import 'dart:convert';
import 'dart:io';

import 'lesson_progress.dart';
import 'lesson_progress_store.dart';

/// Zero-dependency [LessonProgressStore] backed by one deterministic JSON file.
///
/// The file holds a single map: `{targetId: {stars, attemptCount}}`. Only the
/// agreed learner-facing fields are persisted. Writes are atomic (write to a
/// temp file, then rename) so a crash never leaves a half-written record.
class JsonLessonProgressStore implements LessonProgressStore {
  /// Root directory that will contain `lesson_progress.json`.
  final Directory root;

  JsonLessonProgressStore({required this.root});

  File get _file => File('${root.path}${Platform.pathSeparator}lesson_progress.json');

  @override
  Future<LessonProgress?> read(String targetId) async {
    final map = await _readAll();
    final value = map[targetId];
    if (value == null) {
      return null;
    }
    if (value is! Map) {
      throw const FormatException(
          'JsonLessonProgressStore: progress entry must be a JSON object.');
    }
    return LessonProgress.fromMap(Map<String, Object?>.from(value));
  }

  @override
  Future<void> write(LessonProgress progress) async {
    final map = await _readAll();
    map[progress.targetId] = progress.toMap();
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
          'JsonLessonProgressStore: file root must be a JSON object.');
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