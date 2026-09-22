import 'package:flutter/material.dart';

import '../../practice/application/practice_session_controller.dart';
import '../widgets/star_display.dart';

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
        const SizedBox(height: 16),
        Center(
          child: StarDisplay(filled: snapshot.currentStars, capacity: 5, size: 32),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            snapshot.resultMessage,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Attempt ${snapshot.attemptCount} · Lesson progress: '
            '${snapshot.lessonStars} / 10 stars',
            style: theme.textTheme.bodyMedium,
          ),
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
}