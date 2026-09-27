import 'package:flutter/material.dart';

import '../../midi/domain/expected_musical_target.dart';
import '../../practice/application/lesson_instruction.dart';
import '../../practice/application/teach_session.dart';
import '../../practice/application/teach_step.dart';
import '../../practice/domain/learning_lesson.dart';
import '../widgets/hand_visual_style.dart';
import '../widgets/piano_keyboard_view.dart';

/// Ordered, learner-advanced Teach wizard (Learning Curriculum & Lesson
/// Architecture v1.0 §5).
///
/// One step is shown at a time ("Step X of N"); only the current step is
/// active, future steps are never presented as completed, and progress is
/// visible on a linear bar. The learner advances explicitly and may move back
/// where appropriate; advancing past the final step completes Teach and hands
/// off to Practice via [onStartPractice].
///
/// Step completion is session-scoped and transient only: it is never persisted
/// and is NOT mastery, evaluation, practice completion, or scheduler state.
/// MVP content is text-first; the keyboard demonstration steps reuse the
/// existing passive [PianoKeyboardView] (no MIDI input, no audio).
class TeachView extends StatefulWidget {
  const TeachView({
    super.key,
    required this.lesson,
    required this.instruction,
    required this.steps,
    required this.onStartPractice,
  });

  final LearningLesson lesson;
  final LessonInstruction instruction;
  final List<TeachStep> steps;
  final VoidCallback onStartPractice;

  @override
  State<TeachView> createState() => _TeachViewState();
}

class _TeachViewState extends State<TeachView> {
  late final TeachSessionController _session;

  @override
  void initState() {
    super.initState();
    _session = TeachSessionController(steps: widget.steps);
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  void _advance() {
    _session.advance();
    if (_session.value.teachComplete) {
      widget.onStartPractice();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TeachSessionSnapshot>(
      valueListenable: _session,
      builder: (context, snapshot, _) {
        final theme = Theme.of(context);
        final step = snapshot.currentStep;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Fixed header + progress stay on screen while the step scrolls.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Lesson ${widget.lesson.order} · ${widget.lesson.title}',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.lesson.subtitle,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  _HandModeChips(instruction: widget.instruction),
                  const SizedBox(height: 16),
                  Text(
                    'Step ${snapshot.currentIndex + 1} of '
                    '${snapshot.totalSteps}',
                    key: const ValueKey('teach-step-hud'),
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      key: const ValueKey('teach-progress'),
                      value: snapshot.progress,
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Only the step content scrolls; the keyboard demo never hides the
            // wizard navigation.
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          step.title,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          step.content,
                          key: const ValueKey('teach-content'),
                          style: theme.textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          step.learnerAction,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontStyle: FontStyle.italic),
                        ),
                        if (snapshot.currentStepShowsKeyboard) ...<Widget>[
                          const SizedBox(height: 16),
                          PianoKeyboardView(instruction: widget.instruction),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Pinned wizard navigation, always built and always reachable.
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('teach-back'),
                      onPressed: snapshot.canGoPrevious
                          ? () => _session.goPrevious()
                          : null,
                      child: const Text('Back'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('teach-next'),
                      onPressed: snapshot.canAdvance ? _advance : null,
                      child: Text(
                        snapshot.isOnLastStep ? 'Start Practice' : 'Next',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Hand chips (right/left colors) plus the mode chip, mirroring the Practice
/// screen so hand + mode identity stay consistent across stages.
class _HandModeChips extends StatelessWidget {
  const _HandModeChips({required this.instruction});

  final LessonInstruction instruction;

  @override
  Widget build(BuildContext context) {
    final hands = <HandVisualStyle>[
      if (instruction.hand == TargetHand.right ||
          instruction.hand == TargetHand.bothUnison)
        HandVisualStyle.right,
      if (instruction.hand == TargetHand.left ||
          instruction.hand == TargetHand.bothUnison)
        HandVisualStyle.left,
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
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
    );
  }
}