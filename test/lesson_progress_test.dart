import 'package:flutter_test/flutter_test.dart';
import 'package:miditutor/midi/domain/evaluation_result.dart';
import 'package:miditutor/practice/application/in_memory_lesson_progress_store.dart';
import 'package:miditutor/practice/application/lesson_progress.dart';
import 'package:miditutor/practice/application/lesson_progress_service.dart';

void main() {
  const String targetId = 'major-c-rh-block';

  EvaluatedResult evaluated(int stars) => EvaluatedResult(
        stars: stars,
        dimensions: const [],
      );

  final NotEnoughPerformanceResult notEnough = NotEnoughPerformanceResult(
    dimensions: const [],
  );

  group('LessonProgress value', () {
    test('initial progress starts at 0 stars / 0 attempts', () {
      final p = LessonProgress.initial(targetId);
      expect(p.targetId, targetId);
      expect(p.stars, 0);
      expect(p.attemptCount, 0);
      expect(p.hasBeenPracticed, isFalse);
    });

    test('perfect C-major block adds 5 stars and one attempt', () {
      final p = LessonProgress.initial(targetId)
          .applyEvaluationResult(evaluated(5));
      expect(p.stars, 5);
      expect(p.attemptCount, 1);
      expect(p.hasBeenPracticed, isTrue);
    });

    test('zero-star evaluated result adds no stars but increments attempts',
        () {
      final p = LessonProgress.initial(targetId)
          .applyEvaluationResult(evaluated(0));
      expect(p.stars, 0);
      expect(p.attemptCount, 1);
    });

    test('not-enough-performance adds no stars but increments attempts', () {
      final p = LessonProgress.initial(targetId)
          .applyEvaluationResult(notEnough);
      expect(p.stars, 0);
      expect(p.attemptCount, 1);
    });

    test('stars accumulate but never decrease', () {
      var p = LessonProgress.initial(targetId)
          .applyEvaluationResult(evaluated(3));
      expect(p.stars, 3);
      p = p.applyEvaluationResult(evaluated(4));
      expect(p.stars, 7);
      p = p.applyEvaluationResult(evaluated(0));
      expect(p.stars, 7);
      p = p.applyEvaluationResult(notEnough);
      expect(p.stars, 7);
      p = p.applyEvaluationResult(evaluated(2));
      expect(p.stars, 9);
    });

    test('stars cap at 10', () {
      var p = LessonProgress.initial(targetId)
          .applyEvaluationResult(evaluated(5));
      expect(p.stars, 5);
      p = p.applyEvaluationResult(evaluated(5));
      expect(p.stars, 10);
      p = p.applyEvaluationResult(evaluated(5));
      expect(p.stars, 10);
      expect(p.attemptCount, 3);
    });

    test('single five-star result reaches cap 10 after two perfect attempts',
        () {
      final p = LessonProgress.initial(targetId)
          .applyEvaluationResult(evaluated(5))
          .applyEvaluationResult(evaluated(5));
      expect(p.stars, 10);
      expect(p.attemptCount, 2);
    });

    test('validation rejects out-of-range fields', () {
      expect(
        () => LessonProgress(targetId: targetId, stars: -1, attemptCount: 0),
        throwsFormatException,
      );
      expect(
        () => LessonProgress(targetId: targetId, stars: 11, attemptCount: 0),
        throwsFormatException,
      );
      expect(
        () => LessonProgress(targetId: targetId, stars: 0, attemptCount: -1),
        throwsFormatException,
      );
      expect(
        () => LessonProgress(targetId: '', stars: 0, attemptCount: 0),
        throwsFormatException,
      );
    });

    test('serializes and restores exactly targetId/stars/attemptCount', () {
      final original = LessonProgress(targetId: targetId, stars: 7, attemptCount: 4);
      final restored = LessonProgress.fromMap(original.toMap());
      expect(restored, original);
      expect(restored.toMap().keys,
          unorderedEquals(<String>['targetId', 'stars', 'attemptCount']));
    });
  });

  group('LessonProgressService', () {
    test('records results cumulatively through the store', () async {
      final service = LessonProgressService(store: InMemoryLessonProgressStore());
      final first = await service.recordResult(
          targetId: targetId, result: evaluated(5));
      expect(first.stars, 5);
      expect(first.attemptCount, 1);

      final second = await service.recordResult(
          targetId: targetId, result: notEnough);
      expect(second.stars, 5);
      expect(second.attemptCount, 2);

      final third = await service.recordResult(
          targetId: targetId, result: evaluated(0));
      expect(third.stars, 5);
      expect(third.attemptCount, 3);

      final loaded = await service.loadProgress(targetId);
      expect(loaded.stars, 5);
      expect(loaded.attemptCount, 3);
    });

    test('loadProgress returns initial progress when absent', () async {
      final service = LessonProgressService(store: InMemoryLessonProgressStore());
      final p = await service.loadProgress(targetId);
      expect(p, LessonProgress.initial(targetId));
    });
  });
}