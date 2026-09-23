import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/midi/application/expected_musical_target_factory.dart';
import 'package:miditutor/midi/domain/expected_musical_target.dart';
import 'package:miditutor/practice/application/fingering_data.dart';
import 'package:miditutor/practice/application/fingering_instruction.dart';
import 'package:miditutor/practice/application/lesson_instruction.dart';

void main() {
  const catalog = FingeringCatalog();
  const factory = ExpectedMusicalTargetFactory();

  List<int> fingerSequence(List<FingeringInstruction> fingerings) =>
      <int>[for (final f in fingerings) f.finger];

  int keyFinger(LessonKeyVisual key, TargetHand hand) =>
      key.fingers.firstWhere((f) => f.hand == hand).finger;

  group('FingeringCatalog', () {
    test('right hand block is 1 3 5 over C4/E4/G4', () {
      final fingerings = catalog.fingeringsFor('major-c-rh-block');
      expect(fingerSequence(fingerings), <int>[1, 3, 5]);
      expect(
        <int>[for (final f in fingerings) f.midiNote],
        <int>[60, 64, 67],
      );
      expect(fingerings.every((f) => f.hand == TargetHand.right), isTrue);
    });

    test('left hand block is 5 3 1 over C4/E4/G4', () {
      final fingerings = catalog.fingeringsFor('major-c-lh-block');
      expect(fingerSequence(fingerings), <int>[5, 3, 1]);
      expect(fingerings.every((f) => f.hand == TargetHand.left), isTrue);
    });

    test('right hand arpeggio is 1 2 3 5 over C4/E4/G4/C5', () {
      final fingerings = catalog.fingeringsFor('major-c-rh-arpeggio');
      expect(fingerSequence(fingerings), <int>[1, 2, 3, 5]);
      expect(
        <int>[for (final f in fingerings) f.midiNote],
        <int>[60, 64, 67, 72],
      );
      expect(fingerings.every((f) => f.hand == TargetHand.right), isTrue);
    });

    test('left hand arpeggio is 5 3 1 2 over C4/E4/G4/C5', () {
      final fingerings = catalog.fingeringsFor('major-c-lh-arpeggio');
      expect(fingerSequence(fingerings), <int>[5, 3, 1, 2]);
      expect(fingerings.every((f) => f.hand == TargetHand.left), isTrue);
    });

    test('bothUnison block assigns both hands to every block pitch', () {
      final fingerings = catalog.fingeringsFor('major-c-bothUnison-block');
      final byPitch = <int, List<FingeringInstruction>>{};
      for (final f in fingerings) {
        byPitch.putIfAbsent(f.midiNote, () => <FingeringInstruction>[]).add(f);
      }
      expect(byPitch.keys.toSet(), <int>{60, 64, 67});
      for (final entry in byPitch.entries) {
        expect(
          <TargetHand>{for (final f in entry.value) f.hand},
          <TargetHand>{TargetHand.left, TargetHand.right},
        );
      }
      expect(
        <int>{
          for (final f in byPitch[60]!) f.finger,
        },
        <int>{1, 5},
      );
    });

    test('bothUnison arpeggio assigns both hands to every arpeggio pitch',
        () {
      final fingerings = catalog.fingeringsFor('major-c-bothUnison-arpeggio');
      final byPitch = <int, List<FingeringInstruction>>{};
      for (final f in fingerings) {
        byPitch.putIfAbsent(f.midiNote, () => <FingeringInstruction>[]).add(f);
      }
      expect(byPitch.keys.toSet(), <int>{60, 64, 67, 72});
      for (final entry in byPitch.entries) {
        expect(
          <TargetHand>{for (final f in entry.value) f.hand},
          <TargetHand>{TargetHand.left, TargetHand.right},
        );
      }
      expect(
        <int>{for (final f in byPitch[60]!) f.finger},
        <int>{1, 5},
      );
    });

    test('unknown target id fails loudly', () {
      expect(
        () => catalog.fingeringsFor('unknown-target'),
        throwsArgumentError,
      );
    });
  });

  group('LessonInstruction', () {
    String handCode(TargetHand hand) => switch (hand) {
          TargetHand.right => 'rh',
          TargetHand.left => 'lh',
          TargetHand.bothUnison => 'bothUnison',
        };

    LessonInstruction build(TargetHand hand, TargetMode mode) {
      final target = factory.build(
        quality: TargetQuality.major,
        root: TargetRoot.c,
        hand: hand,
        mode: mode,
        targetId: 'major-c-${handCode(hand)}-${mode.name}',
      );
      return LessonInstructionFactory().build(
        target: target,
        fingerings: catalog.fingeringsFor(target.targetId),
      );
    }

    test('right hand block presents labels, keys, and play-together steps', () {
      final instruction = build(TargetHand.right, TargetMode.block);
      expect(instruction.target.targetId, 'major-c-rh-block');
      expect(instruction.handLabel, 'Right Hand');
      expect(instruction.modeLabel, 'Block');
      expect(instruction.isArpeggio, isFalse);
      expect(instruction.hand, TargetHand.right);
      expect(
        <String>[for (final k in instruction.keys) k.noteName],
        <String>['C4', 'E4', 'G4'],
      );
      expect(
        <int>[for (final k in instruction.keys) k.sequenceStep],
        <int>[0, 0, 0],
      );
      expect(
        <int>[
          for (final k in instruction.keys) k.fingers.single.finger,
        ],
        <int>[1, 3, 5],
      );
    });

    test('left hand block presents mirrored 5 3 1 fingers', () {
      final instruction = build(TargetHand.left, TargetMode.block);
      expect(instruction.handLabel, 'Left Hand');
      expect(
        <int>[
          for (final k in instruction.keys) k.fingers.single.finger,
        ],
        <int>[5, 3, 1],
      );
      expect(
        instruction.keys.every(
            (k) => k.fingers.single.hand == TargetHand.left),
        isTrue,
      );
    });

    test('right hand arpeggio sequences steps and fingers', () {
      final instruction = build(TargetHand.right, TargetMode.arpeggio);
      expect(instruction.handLabel, 'Right Hand');
      expect(instruction.modeLabel, 'Arpeggio');
      expect(instruction.isArpeggio, isTrue);
      expect(
        <String>[for (final k in instruction.keys) k.noteName],
        <String>['C4', 'E4', 'G4', 'C5'],
      );
      expect(
        <int>[for (final k in instruction.keys) k.sequenceStep],
        <int>[1, 2, 3, 4],
      );
      expect(
        <int>[
          for (final k in instruction.keys) k.fingers.single.finger,
        ],
        <int>[1, 2, 3, 5],
      );
    });

    test('left hand arpeggio sequences steps with 5 3 1 2 fingers', () {
      final instruction = build(TargetHand.left, TargetMode.arpeggio);
      expect(instruction.handLabel, 'Left Hand');
      expect(
        <int>[
          for (final k in instruction.keys) k.fingers.single.finger,
        ],
        <int>[5, 3, 1, 2],
      );
      expect(
        <int>[for (final k in instruction.keys) k.sequenceStep],
        <int>[1, 2, 3, 4],
      );
    });

    test('bothUnison block keys carry one finger per hand', () {
      final instruction = build(TargetHand.bothUnison, TargetMode.block);
      expect(instruction.handLabel, 'Both Hands');
      expect(instruction.isArpeggio, isFalse);
      expect(instruction.keys.length, 3);
      expect(instruction.keys.every((k) => k.fingers.length == 2), isTrue);
      final c = instruction.keys.first;
      expect(keyFinger(c, TargetHand.right), 1);
      expect(keyFinger(c, TargetHand.left), 5);
    });

    test('bothUnison arpeggio sequences steps for both hands', () {
      final instruction = build(TargetHand.bothUnison, TargetMode.arpeggio);
      expect(instruction.handLabel, 'Both Hands');
      expect(instruction.isArpeggio, isTrue);
      expect(instruction.keys.length, 4);
      expect(
        <int>[for (final k in instruction.keys) k.sequenceStep],
        <int>[1, 2, 3, 4],
      );
      expect(instruction.keys.every((k) => k.fingers.length == 2), isTrue);
      final e = instruction.keys[1];
      expect(keyFinger(e, TargetHand.right), 2);
      expect(keyFinger(e, TargetHand.left), 3);
    });

    test('target note without a fingering fails loudly', () {
      final target = factory.build(
        quality: TargetQuality.major,
        root: TargetRoot.c,
        hand: TargetHand.right,
        mode: TargetMode.block,
        targetId: 'major-c-rh-block',
      );
      final incomplete = catalog.fingeringsFor('major-c-rh-block').sublist(0, 2);
      expect(
        () => LessonInstructionFactory().build(
          target: target,
          fingerings: incomplete,
        ),
        throwsStateError,
      );
    });

    test('fingering on a pitch outside the target fails loudly', () {
      final target = factory.build(
        quality: TargetQuality.major,
        root: TargetRoot.c,
        hand: TargetHand.right,
        mode: TargetMode.block,
        targetId: 'major-c-rh-block',
      );
      final withExtra = <FingeringInstruction>[
        ...catalog.fingeringsFor('major-c-rh-block'),
        const FingeringInstruction(midiNote: 55, finger: 1, hand: TargetHand.right),
      ];
      expect(
        () => LessonInstructionFactory().build(
          target: target,
          fingerings: withExtra,
        ),
        throwsStateError,
      );
    });
  });
}