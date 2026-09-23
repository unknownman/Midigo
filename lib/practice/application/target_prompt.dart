import '../../midi/domain/expected_musical_target.dart';

/// Deterministic learner-facing presentation of a frozen [ExpectedMusicalTarget].
///
/// Pure functions - no transport, no evaluation, no CoreMIDI. Note names are
/// derived from numeric MIDI pitch (60 = C4). These strings are UI copy, but
/// they are derived mechanically from the pinned target definition so the UI
/// never hardcodes notes for a specific lesson.
final class TargetPrompt {
  const TargetPrompt._();

  static const List<String> _pitchClassNames = <String>[
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
  ];

  /// "C4", "E4", ... from a numeric MIDI pitch.
  static String pitchName(int pitch) {
    final octave = (pitch ~/ 12) - 1;
    return '${_pitchClassNames[pitch % 12]}$octave';
  }

  /// "C", "E", "G", ... - the pitch-class letter (with accidental for black
  /// notes) used on the keyboard visualization's key labels.
  static String letterName(int pitch) => _pitchClassNames[pitch % 12];

  /// Whether [pitch] is a black (accidental) piano key.
  static bool isBlack(int pitch) {
    final pitchClass = pitch % 12;
    return pitchClass == 1 ||
        pitchClass == 3 ||
        pitchClass == 6 ||
        pitchClass == 8 ||
        pitchClass == 10;
  }

  /// "C4, E4, G4" / "C4, E4, G4, C5" for the target's expected note list.
  static String noteNames(ExpectedMusicalTarget target) =>
      target.notes.map((note) => pitchName(note.pitch)).join(', ');

  /// "Play C4, E4, and G4 together." (block) or
  /// "Play C4, E4, G4, and C5 one at a time." (arpeggio).
  static String playInstruction(ExpectedMusicalTarget target) {
    final names = target.notes.map((note) => pitchName(note.pitch)).toList();
    final joined = _andJoin(names);
    return switch (target.mode) {
      TargetMode.block => 'Play $joined together.',
      TargetMode.arpeggio => 'Play $joined one at a time.',
    };
  }

  /// "Press C, E, and G together on the right side of the keyboard."
  static String pressInstruction(ExpectedMusicalTarget target) {
    final letters = target.notes
        .map((note) => _pitchClassNames[note.pitch % 12])
        .toList();
    final joined = _andJoin(letters);
    final side = switch (target.hand) {
      TargetHand.right => 'right',
      TargetHand.left => 'left',
      TargetHand.bothUnison => 'both',
    };
    final together = switch (target.mode) {
      TargetMode.block => 'together',
      TargetMode.arpeggio => 'one at a time',
    };
    return 'Press $joined $together on the $side side of the keyboard.';
  }

  /// "C4, E4, and G4" - Oxford comma list for prose sentences.
  static String _andJoin(List<String> items) {
    if (items.length == 1) {
      return items.single;
    }
    final leading = items.sublist(0, items.length - 1).join(', ');
    return '$leading, and ${items.last}';
  }
}