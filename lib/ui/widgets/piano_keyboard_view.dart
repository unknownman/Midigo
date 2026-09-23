import 'package:flutter/material.dart';

import '../../midi/domain/expected_musical_target.dart';
import '../../practice/application/lesson_instruction.dart';
import '../../practice/application/target_prompt.dart';
import 'hand_visual_style.dart';

/// Compact, static, reusable piano keyboard driven entirely by a
/// [LessonInstruction].
///
/// * Range spans the target's lowest to highest MIDI pitch, so it always
///   contains every target key (plus the white keys between them).
/// * White keys carry letter labels (C D E F G A B); black keys are unlabeled.
/// * Target keys are highlighted in the semantic hand color and show the finger
///   number. A both-hands target key renders one half per hand.
/// * Arpeggios show a small step badge (1 → 2 → ...) per target key; blocks
///   show no badges - simultaneously highlighted, "play together".
///
/// The widget is static: it visualizes the target, it never listens to live
/// MIDI. No third-party package, no layout overflow risk (Expanded white-key
/// lanes + fixed key height).
class PianoKeyboardView extends StatelessWidget {
  const PianoKeyboardView({
    super.key,
    required this.instruction,
    this.height = 136,
    this.showLegend = true,
  });

  /// The instructional presentation driving the keyboard.
  final LessonInstruction instruction;

  /// Fixed key-height of the keyboard body (white + black keys).
  final double height;

  /// Whether to draw the color↔hand legend under the keys.
  final bool showLegend;

  static const double _letterStripHeight = 20;
  static const Color _blackKeyColor = Colors.black87;

  @override
  Widget build(BuildContext context) {
    final keys = instruction.keys;
    var lowest = keys.first.midiPitch;
    var highest = keys.first.midiPitch;
    for (final key in keys) {
      if (key.midiPitch < lowest) {
        lowest = key.midiPitch;
      }
      if (key.midiPitch > highest) {
        highest = key.midiPitch;
      }
    }

    final targetByPitch = <int, LessonKeyVisual>{
      for (final key in keys) key.midiPitch: key,
    };
    final whitePitches = <int>[];
    final blackPitches = <int>[];
    for (var pitch = lowest; pitch <= highest; pitch++) {
      if (TargetPrompt.isBlack(pitch)) {
        blackPitches.add(pitch);
      } else {
        whitePitches.add(pitch);
      }
    }

    final hands = <HandVisualStyle>[
      if (instruction.hand == TargetHand.right ||
          instruction.hand == TargetHand.bothUnison)
        HandVisualStyle.right,
      if (instruction.hand == TargetHand.left ||
          instruction.hand == TargetHand.bothUnison)
        HandVisualStyle.left,
    ];

    return Semantics(
      label: 'Piano keyboard: ${instruction.handLabel}, '
          '${instruction.modeLabel}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showLegend) ...[
            _Legend(hands: hands),
            const SizedBox(height: 6),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final numWhite = whitePitches.length;
              final whiteWidth = constraints.maxWidth / numWhite;
              final blackWidth = whiteWidth * 0.6;
              final blackHeight = height * 0.62;
              return SizedBox(
                height: height,
                child: Stack(
                  children: [
                    Row(
                      children: [
                        for (final pitch in whitePitches)
                          Expanded(
                            child: _WhiteKey(
                              pitch: pitch,
                              visual: targetByPitch[pitch],
                            ),
                          ),
                      ],
                    ),
                    for (final pitch in blackPitches)
                      Positioned(
                        left: (whitePitches.indexOf(pitch - 1) + 1) *
                                whiteWidth -
                            blackWidth / 2,
                        top: 0,
                        child: SizedBox(
                          width: blackWidth,
                          height: blackHeight,
                          child: Container(
                            key: ValueKey<String>('black-$pitch'),
                            decoration: const BoxDecoration(
                              color: _blackKeyColor,
                              borderRadius:
                                  BorderRadius.vertical(bottom: Radius.circular(2)),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.hands});

  final List<HandVisualStyle> hands;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodySmall;
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        for (final hand in hands)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: hand.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(hand.label, style: textStyle),
            ],
          ),
      ],
    );
  }
}

class _WhiteKey extends StatelessWidget {
  const _WhiteKey({required this.pitch, required this.visual});

  final int pitch;
  final LessonKeyVisual? visual;

  @override
  Widget build(BuildContext context) {
    final letter = TargetPrompt.letterName(pitch);
    final isTarget = visual != null;
    final isArpeggioStep = visual != null && visual!.sequenceStep > 0;

    return Container(
      key: ValueKey<String>('key-$pitch'),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: Colors.black26),
      ),
      child: Stack(
        children: [
          if (isTarget) _targetArea(visual!),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: PianoKeyboardView._letterStripHeight,
            child: Container(
              decoration: const BoxDecoration(color: Colors.white),
              alignment: Alignment.center,
              child: Text(
                letter,
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          if (isArpeggioStep)
            Positioned(
              top: 2,
              right: 3,
              child: Container(
                key: ValueKey<String>('step-${visual!.sequenceStep}'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: PianoKeyboardView._blackKeyColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${visual!.sequenceStep}',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _targetArea(LessonKeyVisual visual) {
    final fingers = visual.fingers;
    if (fingers.length == 1) {
      final finger = fingers.single;
      return ColoredBox(
        color: HandVisualStyle.of(finger.hand).color,
        child: Center(
          child: Text(
            '${finger.finger}',
            style: _fingerStyle,
          ),
        ),
      );
    }
    return Row(
      children: [
        for (final finger in fingers)
          Expanded(
            child: ColoredBox(
              key: ValueKey<String>('half-$pitch-${finger.hand.name}'),
              color: HandVisualStyle.of(finger.hand).color,
              child: Center(
                child: Text(
                  '${finger.finger}',
                  style: _fingerStyle,
                ),
              ),
            ),
          ),
      ],
    );
  }

  static const TextStyle _fingerStyle = TextStyle(
    color: Colors.white,
    fontSize: 20,
    fontWeight: FontWeight.bold,
  );
}