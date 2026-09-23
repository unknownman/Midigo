import '../../midi/domain/expected_musical_target.dart';
import 'fingering_instruction.dart';

/// Canonical, deterministic beginner fingering for the six C Major Learning
/// Path lessons, keyed by the pinned lesson/target id.
///
/// This is the single source of truth for fingerings. It only ever references
/// the exact MIDI pitches the frozen targets already use (block:
/// C4/E4/G4 = 60/64/67; arpeggio: C4/E4/G4/C5 = 60/64/67/72, for all six
/// lessons). A [`bothUnison`] target is one note list played by both hands, so
/// its data records a full left-hand AND a full right-hand fingering set over
/// those same pitches - no second target is invented.
final class FingeringCatalog {
  const FingeringCatalog();

  // Right hand.
  static const List<FingeringInstruction> _rightHandBlock = <FingeringInstruction>[
    FingeringInstruction(midiNote: 60, finger: 1, hand: TargetHand.right),
    FingeringInstruction(midiNote: 64, finger: 3, hand: TargetHand.right),
    FingeringInstruction(midiNote: 67, finger: 5, hand: TargetHand.right),
  ];

  static const List<FingeringInstruction> _rightHandArpeggio = <FingeringInstruction>[
    FingeringInstruction(midiNote: 60, finger: 1, hand: TargetHand.right),
    FingeringInstruction(midiNote: 64, finger: 2, hand: TargetHand.right),
    FingeringInstruction(midiNote: 67, finger: 3, hand: TargetHand.right),
    FingeringInstruction(midiNote: 72, finger: 5, hand: TargetHand.right),
  ];

  // Left hand.
  static const List<FingeringInstruction> _leftHandBlock = <FingeringInstruction>[
    FingeringInstruction(midiNote: 60, finger: 5, hand: TargetHand.left),
    FingeringInstruction(midiNote: 64, finger: 3, hand: TargetHand.left),
    FingeringInstruction(midiNote: 67, finger: 1, hand: TargetHand.left),
  ];

  /// The arpeggio is the pinned ascending C4/E4/G4/C5 (60/64/67/72); the
  /// task's 5-3-1-2 left-hand pattern applies in sequence order to those exact
  /// MIDI pitches. The target pitch register is never changed.
  static const List<FingeringInstruction> _leftHandArpeggio = <FingeringInstruction>[
    FingeringInstruction(midiNote: 60, finger: 5, hand: TargetHand.left),
    FingeringInstruction(midiNote: 64, finger: 3, hand: TargetHand.left),
    FingeringInstruction(midiNote: 67, finger: 1, hand: TargetHand.left),
    FingeringInstruction(midiNote: 72, finger: 2, hand: TargetHand.left),
  ];

  static const Map<String, List<FingeringInstruction>> _byTargetId = <String, List<FingeringInstruction>>{
    'major-c-rh-block': _rightHandBlock,
    'major-c-rh-arpeggio': _rightHandArpeggio,
    'major-c-lh-block': _leftHandBlock,
    'major-c-lh-arpeggio': _leftHandArpeggio,
    'major-c-bothUnison-block': <FingeringInstruction>[
      ..._leftHandBlock,
      ..._rightHandBlock,
    ],
    'major-c-bothUnison-arpeggio': <FingeringInstruction>[
      ..._leftHandArpeggio,
      ..._rightHandArpeggio,
    ],
  };

  /// The canonical fingering for [targetId].
  ///
  /// Deterministic and nullable-free for the six pinned lessons; unknown target
  /// ids fail loudly instead of silently producing empty fingerings.
  List<FingeringInstruction> fingeringsFor(String targetId) {
    final fingerings = _byTargetId[targetId];
    if (fingerings == null) {
      throw ArgumentError.value(targetId, 'targetId',
          'FingeringCatalog: no canonical fingering for this target.');
    }
    return fingerings;
  }
}