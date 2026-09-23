import 'package:flutter/material.dart';

import '../../midi/domain/expected_musical_target.dart';
import '../../practice/application/lesson_instruction.dart';
import '../../practice/domain/learning_lesson.dart';
import '../widgets/hand_visual_style.dart';
import '../widgets/piano_keyboard_view.dart';

class TeachView extends StatelessWidget {
  const TeachView({
    super.key,
    required this.lesson,
    required this.noteNames,
    required this.pressInstruction,
    required this.instruction,
    required this.onStartPractice,
  });

  final LearningLesson lesson;
  final String noteNames;
  final String pressInstruction;
  final LessonInstruction instruction;
  final VoidCallback onStartPractice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hands = <HandVisualStyle>[
      if (instruction.hand == TargetHand.right ||
          instruction.hand == TargetHand.bothUnison)
        HandVisualStyle.right,
      if (instruction.hand == TargetHand.left ||
          instruction.hand == TargetHand.bothUnison)
        HandVisualStyle.left,
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Lesson ${lesson.order} · ${lesson.title}',
            style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(lesson.subtitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final hand in hands)
              Chip(
                avatar: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: hand.color,
                    shape: BoxShape.circle,
                  ),
                ),
                label: Text(hand.label),
              ),
            Chip(label: Text(instruction.modeLabel)),
          ],
        ),
        const SizedBox(height: 12),
        Text('Target notes: $noteNames', style: theme.textTheme.bodyLarge),
        const SizedBox(height: 8),
        Text(pressInstruction, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 12),
        Text(_fingeringLine(), style: theme.textTheme.bodyMedium),
        if (instruction.isArpeggio) ...[
          const SizedBox(height: 4),
          Text(_orderLine(), style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: 16),
        PianoKeyboardView(instruction: instruction),
        const SizedBox(height: 24),
        FilledButton.icon(
          icon: const Icon(Icons.piano),
          label: const Text('Start Practice'),
          onPressed: onStartPractice,
        ),
      ],
    );
  }

  String _fingeringLine() {
    final entries = <String>[];
    for (final key in instruction.keys) {
      if (key.fingers.length == 2) {
        final byHand = <TargetHand, int>{
          for (final finger in key.fingers) finger.hand: finger.finger,
        };
        entries.add('${byHand[TargetHand.right]}/${byHand[TargetHand.left]}');
      } else {
        entries.add('${key.fingers.single.finger}');
      }
    }
    return '${instruction.handLabel} fingering: ${entries.join(', ')}';
  }

  String _orderLine() {
    final letters = instruction.keys
        .map((key) => key.letterName)
        .join(' \u2192 ');
    return 'Played order: $letters';
  }
}