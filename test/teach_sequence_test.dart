import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/practice/application/fingering_data.dart';
import 'package:miditutor/practice/application/learning_catalog.dart';
import 'package:miditutor/practice/application/lesson_instruction.dart';
import 'package:miditutor/practice/application/teach_sequence.dart';
import 'package:miditutor/practice/application/teach_step.dart';
import 'package:miditutor/practice/domain/learning_lesson.dart';

void main() {
  const catalog = LearningCatalog();
  const factory = LessonInstructionFactory();
  const fingerings = FingeringCatalog();
  const sequence = TeachSequence();

  LessonInstruction instructionFor(LearningLesson lesson) =>
      factory.build(
        target: catalog.buildTarget(lesson),
        fingerings: fingerings.fingeringsFor(lesson.targetId),
      );

  List<TeachStep> stepsFor(LearningLesson lesson) =>
      sequence.build(lesson: lesson, instruction: instructionFor(lesson));

  const cMajorTitles = <String>[
    'What is a chord?',
    'What is a Major chord?',
    'How is a Major chord built?',
    'What is C, the root?',
    'C Major = C, E, G',
    'Where are C, E and G on the keyboard?',
    'Right-hand fingering',
    'Hear C Major',
    'Your first goal',
    'Ready to practice',
  ];

  test('lesson 1 returns the verbatim §13 C Major sequence, in order', () {
    final lesson = LearningCatalog.allLessons.first;
    final steps = stepsFor(lesson);

    expect(steps, hasLength(10));
    expect(steps.map((s) => s.id).toList(), <String>[
      'teach-major-c-rh-block-1',
      'teach-major-c-rh-block-2',
      'teach-major-c-rh-block-3',
      'teach-major-c-rh-block-4',
      'teach-major-c-rh-block-5',
      'teach-major-c-rh-block-6',
      'teach-major-c-rh-block-7',
      'teach-major-c-rh-block-8',
      'teach-major-c-rh-block-9',
      'teach-major-c-rh-block-10',
    ]);
    expect(steps.map((s) => s.order).toList(), <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    expect(steps.map((s) => s.title).toList(), cMajorTitles);
    expect(steps, TeachSequence.cMajorVerbatim);
  });

  test('lesson 1 steps 6 and 7 are the passive keyboard demonstrations', () {
    final steps = stepsFor(LearningCatalog.allLessons.first);

    for (var i = 0; i < steps.length; i++) {
      expect(steps[i].showsKeyboard, i == 5 || i == 6,
          reason: 'step ${i + 1} keyboard flag');
    }
  });

  test('verbatim lesson 1 content is pinned exactly', () {
    final steps = stepsFor(LearningCatalog.allLessons.first);

    expect(steps[4].content, 'Starting on C, the 1st, 3rd and 5th notes are C, E and G.');
    expect(steps[5].content,
        'C is the white key left of the two black keys; E and G are the next white keys to its right.');
    expect(steps[6].content,
        'Put thumb (1) on C, middle finger (3) on E, pinky (5) on G. Play all three together.');
    expect(steps[8].content,
        'You will play C, E and G together, as a block, with your right hand.');
    expect(steps[9].learnerAction, 'Continue \u2192 Practice');
  });

  test('every lesson yields ten deterministic, ordered, arc steps', () {
    for (final lesson in LearningCatalog.allLessons) {
      final first = stepsFor(lesson);
      final second = stepsFor(lesson);

      expect(first, hasLength(10), reason: lesson.id);
      expect(first, second, reason: '$lesson.id must be deterministic');
      expect(first.map((s) => s.order).toList(), <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      // Ids are pinned to the lesson's canonical target id.
      for (final step in first) {
        expect(step.id, startsWith('teach-${lesson.targetId}-'));
      }
      // Steps 6 + 7 are the keyboard demonstrations for every lesson.
      expect(first[5].showsKeyboard, isTrue, reason: lesson.id);
      expect(first[6].showsKeyboard, isTrue, reason: lesson.id);
      // The documented arc: concept -> Major -> rule -> root -> notes -> keys
      // -> fingering -> sound -> goal -> readiness.
      expect(first[0].title, 'What is a chord?');
      expect(first[2].title, 'How is a Major chord built?');
      expect(first[9].title, 'Ready to practice');
    }
  });

  test('arpeggio lessons instantiate the arc with their real notes', () {
    final lesson = LearningCatalog.allLessons[1]; // right-hand arpeggio.
    final steps = stepsFor(lesson);

    expect(steps[4].title, 'C Major = C, E, G, C');
    expect(steps[4].content,
        'Starting on C, the 1st, 3rd and 5th notes are C, E and G; the top C completes the chord.');
    expect(steps[5].title, 'Where are C, E, G, C on the keyboard?');
    expect(steps[6].title, 'Right Hand fingering');
    expect(steps[8].content,
        'You will play C, E, G, and C one at a time, as an arpeggio, with your right hand.');
  });

  test('fingering phrase derives from the canonical per-hand fingerings', () {
    final rhArpeggio = stepsFor(LearningCatalog.allLessons[1])[6];
    expect(rhArpeggio.content,
        'Right Hand: put thumb (1) on C, index finger (2) on E, middle finger (3) on G, and pinky (5) on C. Play the notes in order.');

    final lhBlock = stepsFor(LearningCatalog.allLessons[2])[6];
    expect(lhBlock.title, 'Left Hand fingering');
    expect(lhBlock.content,
        'Left Hand: put pinky (5) on C, middle finger (3) on E, and thumb (1) on G. Play all notes together.');

    final bothUnison = stepsFor(LearningCatalog.allLessons[4])[6];
    expect(bothUnison.content,
        'Right Hand: put thumb (1) on C, middle finger (3) on E, and pinky (5) on G. '
        'Left Hand: put pinky (5) on C, middle finger (3) on E, and thumb (1) on G. '
        'Play all notes together.');
  });

  test('both-hands lessons carry both hand names in the fingering title', () {
    for (final index in <int>[4, 5]) {
      final lesson = LearningCatalog.allLessons[index];
      expect(stepsFor(lesson)[6].title, 'Both Hands fingering',
          reason: lesson.id);
    }
  });
}