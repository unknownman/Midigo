import 'package:flutter/material.dart';

import '../../practice/application/lesson_progress_service.dart';

class TeachView extends StatelessWidget {
  const TeachView({
    super.key,
    required this.progressService,
    required this.onStartPractice,
  });

  final LessonProgressService progressService;
  final VoidCallback onStartPractice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Lesson 1 · C Major', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('C Major · Right Hand · Played together',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 16),
        Text('Target notes: C4, E4, G4', style: theme.textTheme.bodyLarge),
        const SizedBox(height: 8),
        Text('Press C, E, and G together on the right side of the keyboard.',
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: 32),
        FilledButton.icon(
          icon: const Icon(Icons.piano),
          label: const Text('Start Practice'),
          onPressed: onStartPractice,
        ),
      ],
    );
  }
}