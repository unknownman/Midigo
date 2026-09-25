import 'package:flutter/material.dart';

import '../../midi/domain/evaluation_result.dart';
import '../../practice/application/lesson_progress.dart';
import '../../practice/application/practice_session_controller.dart';
import '../widgets/star_display.dart';

/// Shows the outcome of the just-finished practice.
///
/// The screen branches on the authoritative [PracticeSessionSnapshot]
/// [PracticeSessionSnapshot.latestCompletedResult] from the frozen evaluation
/// pipeline - it never re-derives stars or correctness:
///   * [EvaluatedResult]: the attempt's stars (keyed `attempt-stars`) plus the
///     concise feedback string.
///   * [NotEnoughPerformanceResult]: a distinct "not enough performance" state
///     with no attempt-star row (an empty row would read like a zero-star pass).
///   * null: placeholder pending state.
/// Lesson progress is rendered separately (keyed `lesson-progress`) and can
/// never be confused with a single attempt's stars.
class ResultView extends StatelessWidget {
  const ResultView({
    super.key,
    required this.snapshot,
    required this.onRetry,
    required this.onContinue,
  });

  final PracticeSessionSnapshot snapshot;
  final VoidCallback onRetry;
  final Future<void> Function() onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Result', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          '${snapshot.lessonTitle} · Your Practice',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 24),
        ..._resultSection(theme),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 8),
        Text('Lesson Progress', style: theme.textTheme.titleSmall),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            KeyedSubtree(
              key: const ValueKey('lesson-progress'),
              child: StarDisplay(
                filled: snapshot.lessonStars,
                capacity: LessonProgress.starCapacity,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${snapshot.lessonStars} / ${LessonProgress.starCapacity} stars',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: onContinue,
                child: const Text('Continue'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _resultSection(ThemeData theme) {
    final result = snapshot.latestCompletedResult;
    if (result is EvaluatedResult) {
      return <Widget>[
        Center(
          child: KeyedSubtree(
            key: const ValueKey('attempt-stars'),
            child: StarDisplay(filled: result.stars, capacity: 5, size: 32),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            snapshot.resultMessage,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ),
      ];
    }
    if (result is NotEnoughPerformanceResult) {
      return <Widget>[
        Icon(Icons.music_off, size: 32, color: theme.colorScheme.outline),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Not enough performance to evaluate.',
            key: const ValueKey('nep-message'),
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ),
      ];
    }
    return <Widget>[
      Center(
        child: Text(
          'No completed practice result yet.',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ),
    ];
  }
}