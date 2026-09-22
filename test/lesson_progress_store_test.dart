import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miditutor/practice/application/in_memory_lesson_progress_store.dart';
import 'package:miditutor/practice/application/json_lesson_progress_store.dart';
import 'package:miditutor/practice/application/lesson_progress.dart';

void main() {
  final Directory tempDir = Directory.systemTemp.createTempSync('miditutor_store_test');

  tearDownAll(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  LessonProgress progress(String id, int stars, int attempts) =>
      LessonProgress(targetId: id, stars: stars, attemptCount: attempts);

  group('InMemoryLessonProgressStore', () {
    test('read returns null for unknown target; write then read round-trips', () async {
      final store = InMemoryLessonProgressStore();
      expect(await store.read('a'), isNull);
      await store.write(progress('a', 3, 1));
      final loaded = await store.read('a');
      expect(loaded!.stars, 3);
      expect(loaded.attemptCount, 1);
    });

    test('write overwrites the previous value for the same target', () async {
      final store = InMemoryLessonProgressStore();
      await store.write(progress('a', 1, 1));
      await store.write(progress('a', 9, 4));
      expect((await store.read('a'))!.stars, 9);
      expect((await store.read('a'))!.attemptCount, 4);
    });

    test('targets are independent', () async {
      final store = InMemoryLessonProgressStore();
      await store.write(progress('a', 5, 1));
      await store.write(progress('b', 2, 3));
      expect((await store.read('a'))!.stars, 5);
      expect((await store.read('b'))!.stars, 2);
    });
  });

  group('JsonLessonProgressStore', () {
    test('read returns null when no file exists', () async {
      final store = JsonLessonProgressStore(root: tempDir);
      expect(await store.read('a'), isNull);
    });

    test('write persists a deterministic JSON object with only agreed fields', () async {
      final store = JsonLessonProgressStore(root: tempDir);
      await store.write(progress('major-c-rh-block', 7, 2));

      final file = File('${tempDir.path}${Platform.pathSeparator}lesson_progress.json');
      expect(file.existsSync(), isTrue);
      final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final entry = decoded['major-c-rh-block'] as Map<String, dynamic>;
      expect(entry.keys, unorderedEquals(<String>['targetId', 'stars', 'attemptCount']));
      expect(entry['stars'], 7);
      expect(entry['attemptCount'], 2);
    });

    test('round-trips through the file including updates', () async {
      final store = JsonLessonProgressStore(root: tempDir);
      await store.write(progress('major-c-rh-block', 3, 1));
      await store.write(progress('other-target', 10, 6));
      await store.write(progress('major-c-rh-block', 8, 3));

      expect((await store.read('major-c-rh-block'))!.stars, 8);
      expect((await store.read('major-c-rh-block'))!.attemptCount, 3);
      expect((await store.read('other-target'))!.stars, 10);
      expect((await store.read('missing')), isNull);
    });

    test('file content uses the deterministic targetId key and survives re-read', () async {
      final store = JsonLessonProgressStore(root: tempDir);
      await store.write(progress('major-c-rh-block', 5, 1));

      final reopened = JsonLessonProgressStore(root: tempDir);
      expect((await reopened.read('major-c-rh-block'))!.stars, 5);
    });
  });
}