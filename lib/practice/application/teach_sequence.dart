import '../../midi/domain/expected_musical_target.dart';
import '../domain/learning_lesson.dart';
import 'learning_catalog.dart';
import 'lesson_instruction.dart';
import 'teach_step.dart';

/// Authored Teach content builder for the Learning Path lessons.
///
/// Lesson 1 (C Major, right-hand block, `lesson-major-c-rh-block`) returns the
/// C Major Teach sequence of the Learning Curriculum & Lesson Architecture
/// v1.0 §13 VERBATIM: ten ordered, deterministic steps that arc concept →
/// Major → construction → root → notes → keyboard → fingering → sound → goal →
/// readiness. The other five lessons realize the same documented arc
/// deterministically from their own frozen target/fingering data (same steps,
/// lesson-specific notes and fingerings), so every Lesson opens into a full
/// Teach stage and no step is a placeholder.
///
/// This is authored product-contract-domain content: it evaluates nothing, is
/// not mastery, and touches no locked contract.
final class TeachSequence {
  const TeachSequence();

  /// §13 verbatim, ten ordered steps for the primary C Major lesson.
  static const List<TeachStep> cMajorVerbatim = <TeachStep>[
    TeachStep(
      id: 'teach-major-c-rh-block-1',
      order: 1,
      title: 'What is a chord?',
      content: "A chord is three or more notes heard together. It is one "
          "'harmony sound'.",
      learnerAction: 'Read; Continue',
    ),
    TeachStep(
      id: 'teach-major-c-rh-block-2',
      order: 2,
      title: 'What is a Major chord?',
      content: 'A Major chord is a bright, stable chord type, built from three '
          'specific notes.',
      learnerAction: 'Read; Continue',
    ),
    TeachStep(
      id: 'teach-major-c-rh-block-3',
      order: 3,
      title: 'How is a Major chord built?',
      content: 'A Major chord uses the 1st, 3rd and 5th notes of its scale.',
      learnerAction: 'Read; Continue',
    ),
    TeachStep(
      id: 'teach-major-c-rh-block-4',
      order: 4,
      title: 'What is C, the root?',
      content: 'C is the bottom note of our chord. Names come from the bottom '
          'note (the root).',
      learnerAction: 'Read; Continue',
    ),
    TeachStep(
      id: 'teach-major-c-rh-block-5',
      order: 5,
      title: 'C Major = C, E, G',
      content: 'Starting on C, the 1st, 3rd and 5th notes are C, E and G.',
      learnerAction: 'Read; Continue',
    ),
    TeachStep(
      id: 'teach-major-c-rh-block-6',
      order: 6,
      title: 'Where are C, E and G on the keyboard?',
      content: 'C is the white key left of the two black keys; E and G are the '
          'next white keys to its right.',
      learnerAction: 'See the highlighted keys (PianoKeyboardView)',
      showsKeyboard: true,
    ),
    TeachStep(
      id: 'teach-major-c-rh-block-7',
      order: 7,
      title: 'Right-hand fingering',
      content: 'Put thumb (1) on C, middle finger (3) on E, pinky (5) on G. '
          'Play all three together.',
      learnerAction: 'See fingering labels; place hand',
      showsKeyboard: true,
    ),
    TeachStep(
      id: 'teach-major-c-rh-block-8',
      order: 8,
      title: 'Hear C Major',
      content: 'C Major sounds bright and complete when all three notes ring '
          'together. (Audio playback is a future media step.)',
      learnerAction: 'Listen if audio present; else read',
    ),
    TeachStep(
      id: 'teach-major-c-rh-block-9',
      order: 9,
      title: 'Your first goal',
      content: 'You will play C, E and G together, as a block, with your '
          'right hand.',
      learnerAction: 'Read; Continue',
    ),
    TeachStep(
      id: 'teach-major-c-rh-block-10',
      order: 10,
      title: 'Ready to practice',
      content: 'Tap Continue to move from Teach to Practice.',
      learnerAction: 'Continue \u2192 Practice',
    ),
  ];

  /// Builds the ordered Teach steps for [lesson], presenting [instruction].
  ///
  /// Deterministic: the same lesson always yields the same steps. The primary
  /// lesson (the canonical first lesson of [LearningCatalog], identified
  /// through the catalog rather than a local constant) returns the verbatim
  /// §13 sequence; every other lesson gets the same documented arc
  /// instantiated from its own frozen target/fingering.
  List<TeachStep> build({
    required LearningLesson lesson,
    required LessonInstruction instruction,
  }) {
    final steps =
        lesson.id == LearningCatalog.allLessons.first.id
        ? cMajorVerbatim
        : _adapted(instruction);
    if (steps.isEmpty) {
      throw StateError(
          'TeachSequence: no Teach steps for lesson "${lesson.id}".');
    }
    return steps;
  }

  /// Instantiates the documented §13 arc from the lesson's own frozen
  /// [LessonInstruction] (actual notes, hand, mode, and fingering data).
  static List<TeachStep> _adapted(LessonInstruction instruction) {
    final targetId = instruction.target.targetId;
    final letterNames =
        <String>[for (final key in instruction.keys) key.letterName];
    final commaJoined = letterNames.join(', ');
    final proseJoined = _andJoin(letterNames);
    return <TeachStep>[
      TeachStep(
        id: 'teach-$targetId-1',
        order: 1,
        title: 'What is a chord?',
        content: "A chord is three or more notes heard together. It is one "
            "'harmony sound'.",
        learnerAction: 'Read; Continue',
      ),
      TeachStep(
        id: 'teach-$targetId-2',
        order: 2,
        title: 'What is a Major chord?',
        content: 'A Major chord is a bright, stable chord type, built from '
            'three specific notes.',
        learnerAction: 'Read; Continue',
      ),
      TeachStep(
        id: 'teach-$targetId-3',
        order: 3,
        title: 'How is a Major chord built?',
        content: 'A Major chord uses the 1st, 3rd and 5th notes of its scale.',
        learnerAction: 'Read; Continue',
      ),
      TeachStep(
        id: 'teach-$targetId-4',
        order: 4,
        title: 'What is C, the root?',
        content: 'C is the bottom note of our chord. Names come from the '
            'bottom note (the root).',
        learnerAction: 'Read; Continue',
      ),
      TeachStep(
        id: 'teach-$targetId-5',
        order: 5,
        title: 'C Major = $commaJoined',
        content: instruction.isArpeggio
            ? 'Starting on C, the 1st, 3rd and 5th notes are C, E and G; the '
                'top C completes the chord.'
            : 'Starting on C, the 1st, 3rd and 5th notes are $proseJoined.',
        learnerAction: 'Read; Continue',
      ),
      TeachStep(
        id: 'teach-$targetId-6',
        order: 6,
        title: 'Where are $commaJoined on the keyboard?',
        content: 'C is the white key left of the two black keys; the other '
            'target notes are the next white keys to its right.',
        learnerAction: 'See the highlighted keys (PianoKeyboardView)',
        showsKeyboard: true,
      ),
      TeachStep(
        id: 'teach-$targetId-7',
        order: 7,
        title: '${instruction.handLabel} fingering',
        content: _fingeringPhrase(instruction),
        learnerAction: 'See fingering labels; place hand',
        showsKeyboard: true,
      ),
      TeachStep(
        id: 'teach-$targetId-8',
        order: 8,
        title: 'Hear C Major',
        content: 'C Major sounds bright and complete when the notes ring '
            'together. (Audio playback is a future media step.)',
        learnerAction: 'Listen if audio present; else read',
      ),
      TeachStep(
        id: 'teach-$targetId-9',
        order: 9,
        title: 'Your first goal',
        content: _goalPhrase(instruction, proseJoined),
        learnerAction: 'Read; Continue',
      ),
      TeachStep(
        id: 'teach-$targetId-10',
        order: 10,
        title: 'Ready to practice',
        content: 'Tap Continue to move from Teach to Practice.',
        learnerAction: 'Continue \u2192 Practice',
      ),
    ];
  }

  /// "You will play C, E and G together, as a block, with your right hand."
  static String _goalPhrase(LessonInstruction instruction, String letters) {
    final hand = switch (instruction.hand) {
      TargetHand.right => 'your right hand',
      TargetHand.left => 'your left hand',
      TargetHand.bothUnison => 'both hands',
    };
    final manner =
        instruction.isArpeggio
        ? 'one at a time, as an arpeggio'
        : 'together, as a block';
    return 'You will play $letters $manner, with $hand.';
  }

  /// "Right Hand: put thumb (1) on C, middle finger (3) on E, pinky (5) on G.
  /// Play all notes together." Derived only from the canonical [LessonInstruction]
  /// fingering data; never hardcoded per lesson.
  static String _fingeringPhrase(LessonInstruction instruction) {
    final byHand = <TargetHand, List<(String, int)>>{};
    for (final key in instruction.keys) {
      for (final finger in key.fingers) {
        byHand
            .putIfAbsent(finger.hand, () => <(String, int)>[])
            .add((key.letterName, finger.finger));
      }
    }
    final clauses = <String>[];
    for (final hand in const <TargetHand>[
      TargetHand.right,
      TargetHand.left,
    ]) {
      final entries = byHand[hand];
      if (entries == null || entries.isEmpty) {
        continue;
      }
      final puts = <String>[
        for (final (letter, finger) in entries)
          '${_fingerName(finger)} ($finger) on $letter',
      ];
      clauses.add('${_handName(hand)}: put ${_andJoin(puts)}.');
    }
    return '${clauses.join(' ')} ${instruction.modeInstruction}';
  }

  static String _handName(TargetHand hand) => switch (hand) {
        TargetHand.right => 'Right Hand',
        TargetHand.left => 'Left Hand',
        TargetHand.bothUnison => 'Both Hands',
      };

  static String _fingerName(int finger) => switch (finger) {
        1 => 'thumb',
        2 => 'index finger',
        3 => 'middle finger',
        4 => 'ring finger',
        5 => 'pinky',
        _ => throw StateError('TeachSequence: unknown finger $finger.'),
      };

  static String _andJoin(List<String> items) {
    if (items.length == 1) {
      return items.single;
    }
    final leading = items.sublist(0, items.length - 1).join(', ');
    return '$leading, and ${items.last}';
  }
}