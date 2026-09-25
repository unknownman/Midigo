import '../../midi/domain/expected_musical_target.dart';
import 'fingering_instruction.dart';
import 'target_prompt.dart';

/// One finger assignment for a single key in its target-bearing hand.
///
/// Pure value type - no CoreMIDI, no transport, no UI widgets. A key may carry
/// two fingers when the target is played by both hands at once (one per hand).
final class LessonKeyFinger {
  final int finger;
  final TargetHand hand;

  const LessonKeyFinger({
    required this.finger,
    required this.hand,
  })  : assert(finger >= 1 && finger <= 5),
        assert(hand == TargetHand.right || hand == TargetHand.left,
            'A key finger always belongs to exactly one hand.');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LessonKeyFinger &&
          other.finger == finger &&
          other.hand == hand;

  @override
  int get hashCode => Object.hash(finger, hand);

  @override
  String toString() => 'LessonKeyFinger(finger: $finger, hand: $hand)';
}

/// Learner-facing representation of one target key on the piano keyboard.
///
/// Fields are derived mechanically from the frozen target note list (numeric
/// MIDI pitch) and the canonical fingering data, so the UI never hardcodes a
/// note or finger for a specific lesson.
final class LessonKeyVisual {
  final int midiPitch;

  /// "C4", "E4", ... - named from the numeric MIDI pitch.
  final String noteName;

  /// "C", "E", ... - the pitch-class letter shown in the key label.
  final String letterName;

  /// Whether this key is a black (accidental) piano key.
  final bool isBlack;

  /// 1-based position in the target's play order for arpeggios; 0 for the
  /// block form (played together, no ordering implied).
  final int sequenceStep;

  /// Fingers assigned to this key, one per hand that plays it.
  final List<LessonKeyFinger> fingers;

  LessonKeyVisual({
    required this.midiPitch,
    required this.noteName,
    required this.letterName,
    required this.isBlack,
    required this.sequenceStep,
    required List<LessonKeyFinger> fingers,
  }) : fingers = List<LessonKeyFinger>.unmodifiable(fingers);

  @override
  String toString() =>
      'LessonKeyVisual($noteName step=$sequenceStep $fingers)';
}

/// Instructional presentation of a frozen [ExpectedMusicalTarget].
///
/// This is the single bridge between the canonical target + canonical fingering
/// data on one side and the lesson screens / keyboard visualization on the
/// other. It centralizes hand/mode labels and per-key visuals so the UI does
/// not re-derive musical knowledge. Pure value type - no transport, no
/// evaluation, no CoreMIDI.
final class LessonInstruction {
  /// The frozen canonical target this instruction presents.
  final ExpectedMusicalTarget target;

  /// "Right Hand" / "Left Hand" / "Both Hands" - always textual, never
  /// color-only.
  final String handLabel;

  /// "Block" / "Arpeggio".
  final String modeLabel;

  /// Whether the target must be played as an ordered sequence.
  final bool isArpeggio;

  /// Concise learner instruction for this practice, derived from the frozen
  /// target mode: "Play all notes together." (block) / "Play the notes in
  /// order." (arpeggio). No timing, tempo, or accuracy claims are made.
  String get modeInstruction => switch (target.mode) {
        TargetMode.block => 'Play all notes together.',
        TargetMode.arpeggio => 'Play the notes in order.',
      };

  /// Target keys in the target's note order, with fingers + play-step.
  final List<LessonKeyVisual> keys;

  LessonInstruction({
    required this.target,
    required this.handLabel,
    required this.modeLabel,
    required this.isArpeggio,
    required List<LessonKeyVisual> keys,
  }) : keys = List<LessonKeyVisual>.unmodifiable(keys);

  TargetHand get hand => target.hand;

  @override
  String toString() =>
      'LessonInstruction(${target.targetId}: $handLabel · $modeLabel)';
}

/// Builds a [LessonInstruction] from the canonical target and its canonical
/// fingering data.
///
/// Deterministic and fail-loud: an instruction can never be built with a target
/// note missing a fingering or a fingering on a non-target pitch.
final class LessonInstructionFactory {
  const LessonInstructionFactory();

  LessonInstruction build({
    required ExpectedMusicalTarget target,
    required List<FingeringInstruction> fingerings,
  }) {
    final fingeringsByPitch = <int, List<FingeringInstruction>>{};
    for (final fingering in fingerings) {
      fingeringsByPitch
          .putIfAbsent(fingering.midiNote, () => <FingeringInstruction>[])
          .add(fingering);
    }

    final targetPitches = <int>{
      for (final note in target.notes) note.pitch,
    };
    for (final pitch in fingeringsByPitch.keys) {
      if (!targetPitches.contains(pitch)) {
        throw StateError(
            'LessonInstructionFactory: fingering references MIDI pitch $pitch '
            'which is not in the target note list.');
      }
    }
    for (final note in target.notes) {
      if (!fingeringsByPitch.containsKey(note.pitch)) {
        throw StateError(
            'LessonInstructionFactory: no canonical fingering for target note '
            'pitch ${note.pitch}.');
      }
    }

    final isArpeggio = target.mode == TargetMode.arpeggio;
    final keys = <LessonKeyVisual>[];
    for (var i = 0; i < target.notes.length; i++) {
      final note = target.notes[i];
      final noteFingerings = fingeringsByPitch[note.pitch]!;
      keys.add(LessonKeyVisual(
        midiPitch: note.pitch,
        noteName: TargetPrompt.pitchName(note.pitch),
        letterName: TargetPrompt.letterName(note.pitch),
        isBlack: TargetPrompt.isBlack(note.pitch),
        sequenceStep: isArpeggio ? i + 1 : 0,
        fingers: <LessonKeyFinger>[
          for (final fingering in noteFingerings)
            LessonKeyFinger(finger: fingering.finger, hand: fingering.hand),
        ],
      ));
    }

    return LessonInstruction(
      target: target,
      handLabel: _handLabel(target.hand),
      modeLabel: _modeLabel(target.mode),
      isArpeggio: isArpeggio,
      keys: keys,
    );
  }

  static String _handLabel(TargetHand hand) => switch (hand) {
        TargetHand.right => 'Right Hand',
        TargetHand.left => 'Left Hand',
        TargetHand.bothUnison => 'Both Hands',
      };

  static String _modeLabel(TargetMode mode) => switch (mode) {
        TargetMode.block => 'Block',
        TargetMode.arpeggio => 'Arpeggio',
      };
}