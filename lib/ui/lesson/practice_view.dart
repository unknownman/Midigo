import 'package:flutter/material.dart';

import 'package:miditutor/midi/domain/midi_source_info.dart';

import '../../midi/domain/expected_musical_target.dart';
import '../../practice/application/lesson_instruction.dart';
import '../../practice/application/practice_session_controller.dart';
import '../../practice/application/target_prompt.dart';
import '../widgets/hand_visual_style.dart';
import '../widgets/piano_keyboard_view.dart';

class PracticeView extends StatefulWidget {
  const PracticeView({
    super.key,
    required this.controller,
    required this.instruction,
    required this.onFinished,
  });

  final PracticeSessionController controller;
  final LessonInstruction instruction;
  final VoidCallback onFinished;

  @override
  State<PracticeView> createState() => _PracticeViewState();
}

class _PracticeViewState extends State<PracticeView> {
  late Future<List<MidiSourceInfo>> _sources;

  @override
  void initState() {
    super.initState();
    _sources = widget.controller.listSources();
    widget.controller.resolveSourceName();
  }

  void _refresh() {
    setState(() {
      _sources = widget.controller.listSources();
    });
  }

  Future<void> _connect(MidiSourceInfo source) async {
    final connected = await widget.controller.connect(source);
    if (!connected) {
      // The connection error is already on the snapshot; never start an attempt
      // on a failed connection, so the real error stays visible.
      if (mounted) {
        setState(() {});
      }
      return;
    }
    await widget.controller.startAttempt();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _finish() async {
    await widget.controller.endAttempt();
    if (mounted) {
      widget.onFinished();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PracticeSessionSnapshot>(
      valueListenable: widget.controller.session,
      builder: (context, snapshot, _) {
        if (!snapshot.isConnected) {
          return _buildConnectionPanel(context, snapshot);
        }
        return _buildPracticePanel(context, snapshot);
      },
    );
  }

  String _liveStatus(PracticeSessionSnapshot snapshot) {
    if (!snapshot.attemptInProgress) {
      return 'Ready';
    }
    final pressed = snapshot.pressedNotes.toList()..sort();
    if (pressed.isEmpty) {
      return 'Practice in progress';
    }
    final names = pressed.map(TargetPrompt.pitchName).join(', ');
    return 'Pressed: $names · ${pressed.length} / '
        '${widget.instruction.keys.length} target notes';
  }

  Widget _buildConnectionPanel(BuildContext context, PracticeSessionSnapshot snapshot) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Practice', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('Connect your MIDI keyboard to start.', style: theme.textTheme.bodyLarge),
        const SizedBox(height: 4),
        _HandLabel(instruction: widget.instruction),
        if (snapshot.errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            snapshot.errorMessage!,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        FutureBuilder<List<MidiSourceInfo>>(
          future: _sources,
          builder: (context, futureSnapshot) {
            if (futureSnapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final sources = futureSnapshot.data ?? const <MidiSourceInfo>[];
            if (sources.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('No MIDI sources detected.'),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _refresh,
                    child: const Text('Refresh'),
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final source in sources)
                  Card(
                    child: ListTile(
                      title: Text(source.name.isEmpty
                          ? MidiSourceInfo.unnamed
                          : source.name),
                      subtitle: Text(source.manufacturer),
                      trailing: FilledButton(
                        onPressed: () => _connect(source),
                        child: const Text('Connect'),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildPracticePanel(BuildContext context, PracticeSessionSnapshot snapshot) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        KeyedSubtree(
          key: const ValueKey('practice-target'),
          child: Text(
            snapshot.lessonTitle,
            style: theme.textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: 4),
        Text('Practice · ${snapshot.sourceName}', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 12),
        _HandModeChips(instruction: widget.instruction),
        const SizedBox(height: 12),
        Text(
          widget.instruction.modeInstruction,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        _FingeringSummary(instruction: widget.instruction),
        const SizedBox(height: 16),
        PianoKeyboardView(
          instruction: widget.instruction,
          pressedNotes: snapshot.pressedNotes,
        ),
        const SizedBox(height: 8),
        Text(
          _liveStatus(snapshot),
          key: const ValueKey('live-status'),
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        if (snapshot.errorMessage != null) ...[
          Text(snapshot.errorMessage!, style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: 12),
        ],
        if (!snapshot.attemptInProgress) ...[
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start Attempt'),
            onPressed: () => widget.controller.startAttempt(),
          ),
          const SizedBox(height: 8),
        ],
        FilledButton.icon(
          icon: const Icon(Icons.check),
          label: const Text('Finish Practice'),
          onPressed: snapshot.attemptInProgress ? _finish : null,
        ),
        const SizedBox(height: 8),
        Text(
          'Finishing evaluates this practice and shows your result.',
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Hand chips (right/left colors retained from Slice 2.1) plus the mode chip,
/// mirroring the Teach screen so hand + mode identity stay consistent.
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
    );
  }
}

/// At-a-glance recommended fingering: note letter above the finger(s) that
/// canonically play it, in target note order. Derived only from the canonical
/// [LessonInstruction]; never inferred from MIDI.
class _FingeringSummary extends StatelessWidget {
  const _FingeringSummary({required this.instruction});

  final LessonInstruction instruction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final (i, key) in instruction.keys.indexed) ...[
          if (i > 0) const SizedBox(width: 32),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                key.letterName,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                _fingerText(key),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ],
    );
  }

  static String _fingerText(LessonKeyVisual key) {
    if (key.fingers.length == 2) {
      final byHand = <TargetHand, int>{
        for (final finger in key.fingers) finger.hand: finger.finger,
      };
      return '${byHand[TargetHand.right]}/${byHand[TargetHand.left]}';
    }
    return '${key.fingers.single.finger}';
  }
}

class _HandLabel extends StatelessWidget {
  const _HandLabel({required this.instruction});

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
    return Row(
      children: [
        for (final hand in hands) ...[
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: hand.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            hand.label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(width: 16),
        ],
      ],
    );
  }
}