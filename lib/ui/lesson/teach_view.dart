import 'package:flutter/material.dart';

import '../../practice/domain/learning_lesson.dart';

class TeachView extends StatelessWidget {
  const TeachView({
    super.key,
    required this.lesson,
    required this.noteNames,
    required this.pressInstruction,
    required this.onStartPractice,
  });

  final LearningLesson lesson;
  final String noteNames;
  final String pressInstruction;
  final VoidCallback onStartPractice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Lesson ${lesson.order} · ${lesson.title}',
            style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(lesson.subtitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 16),
        Text('Target notes: $noteNames', style: theme.textTheme.bodyLarge),
        const SizedBox(height: 8),
        Text(pressInstruction, style: theme.textTheme.bodyMedium),
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