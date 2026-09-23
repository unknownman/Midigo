import '../../midi/domain/expected_musical_target.dart';

/// One canonical fingering assignment: play [midiNote] with [finger] of
/// [hand].
///
/// Immutable and deterministic. A [FingeringInstruction] never alters the
/// target: it is derived metadata attached to the exact MIDI pitch the target
/// already uses, so the expected note list stays the single source of truth for
/// pitches. It is a pure value type - no CoreMIDI, no transport, no UI widgets.
final class FingeringInstruction {
  final int midiNote;
  final int finger;
  final TargetHand hand;

  const FingeringInstruction({
    required this.midiNote,
    required this.finger,
    required this.hand,
  })  : assert(midiNote >= 0 && midiNote <= 127),
        assert(finger >= 1 && finger <= 5),
        assert(hand != TargetHand.bothUnison,
            'A single fingering belongs to one hand, not both.');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FingeringInstruction &&
          other.midiNote == midiNote &&
          other.finger == finger &&
          other.hand == hand;

  @override
  int get hashCode => Object.hash(midiNote, finger, hand);

  @override
  String toString() =>
      'FingeringInstruction(midiNote: $midiNote, finger: $finger, hand: $hand)';
}