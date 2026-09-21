import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/midi/application/expected_musical_target_factory.dart';
import 'package:miditutor/midi/application/midi_normalizer.dart';
import 'package:miditutor/midi/application/musical_event_interpreter.dart';
import 'package:miditutor/midi/domain/expected_musical_target.dart';
import 'package:miditutor/midi/domain/expected_note_event.dart';
import 'package:miditutor/midi/domain/musical_event.dart';
import 'package:miditutor/midi/domain/raw_midi_event.dart';

/// Deterministic scalar projection (stable JSON string of the full target).
String _project(ExpectedMusicalTarget target) => jsonEncode(target.toMap());

const _forbiddenEvalKeys = <String>[
  'correct',
  'incorrect',
  'score',
  'tolerance',
  'threshold',
  'mastery',
  'evidence',
  'priority',
  'scheduler',
  'interval',
  'error_vector',
  'qualified',
  'attempt',
  'late',
  'early',
  'simultaneous',
  'in_order',
  'out_of_order',
  'evaluation',
  'skill',
  'exercise',
];

Iterable<String> _forbiddenEvaluationKeys(Iterable<String> keys) => keys
    .where((key) =>
        _forbiddenEvalKeys.any((word) => key.toLowerCase().contains(word)));

void main() {
  const factory = ExpectedMusicalTargetFactory();

  group('T1 - Major C RH Block', () {
    test('identity, mode, hand, pitches, one group, deterministic order', () {
      final target = factory.build(
        quality: TargetQuality.major,
        root: TargetRoot.c,
        hand: TargetHand.right,
        mode: TargetMode.block,
      );

      expect(target.targetId, 'major-c-right-block');
      expect(target.quality, TargetQuality.major);
      expect(target.root, TargetRoot.c);
      expect(target.root.label, 'C');
      expect(target.hand, TargetHand.right);
      expect(target.mode, TargetMode.block);
      expect(target.modelVersion, '1');

      expect(target.notes.map((n) => n.pitch), <int>[60, 64, 67]);
      expect(target.notes.map((n) => n.pitchClass), <int>[0, 4, 7]);
      expect(target.notes.map((n) => n.index), <int>[0, 1, 2]);
      expect(target.notes.every((n) => n.channel == null), isTrue);

      expect(target.onsetGroups, hasLength(1));
      final group = target.onsetGroups.single;
      expect(group.index, 0);
      expect(group.memberEventIndices, <int>[0, 1, 2]);
      expect(group.expectedOnsetOffsetMs, 0);
    });
  });

  group('T2 - Major C RH Arpeggio', () {
    test('four ordered notes, four groups, offsets, no simultaneity grouping',
        () {
      final target = factory.build(
        quality: TargetQuality.major,
        root: TargetRoot.c,
        hand: TargetHand.right,
        mode: TargetMode.arpeggio,
      );

      expect(target.mode, TargetMode.arpeggio);
      expect(target.notes, hasLength(4));
      expect(target.notes.map((n) => n.pitch), <int>[60, 64, 67, 72]);
      expect(target.notes.map((n) => n.index), <int>[0, 1, 2, 3]);

      expect(target.onsetGroups, hasLength(4));
      expect(target.onsetGroups.map((g) => g.index), <int>[0, 1, 2, 3]);
      expect(target.onsetGroups.map((g) => g.memberEventIndices),
          <List<int>>[
        <int>[0],
        <int>[1],
        <int>[2],
        <int>[3],
      ]);
      expect(target.onsetGroups.map((g) => g.expectedOnsetOffsetMs),
          <int>[0, 250, 500, 750]);
      expect(
          target.onsetGroups.every((g) => g.memberEventIndices.length == 1),
          isTrue);
    });
  });

  group('T3 - Minor C LH Block', () {
    test('minor quality realizes C Eb G for left hand', () {
      final target = factory.build(
        quality: TargetQuality.minor,
        root: TargetRoot.c,
        hand: TargetHand.left,
        mode: TargetMode.block,
      );

      expect(target.targetId, 'minor-c-left-block');
      expect(target.quality, TargetQuality.minor);
      expect(target.hand, TargetHand.left);
      expect(target.notes.map((n) => n.pitch), <int>[60, 63, 67]);
      expect(target.notes.map((n) => n.pitchClass), <int>[0, 3, 7]);
    });
  });

  group('T4 - Major F# RH Block', () {
    test('identity retains F#, pitches numeric, no F#/Gb MIDI distinction', () {
      final target = factory.build(
        quality: TargetQuality.major,
        root: TargetRoot.fSharp,
        hand: TargetHand.right,
        mode: TargetMode.block,
      );

      // Identity metadata preserves the requested spelling.
      expect(target.root, TargetRoot.fSharp);
      expect(target.root.label, 'F#');
      expect(target.targetId, 'major-fSharp-right-block');

      // Concrete expected pitches are plain MIDI numbers.
      expect(target.notes.map((n) => n.pitch), <int>[66, 70, 73]);
      expect(target.notes.map((n) => n.pitchClass), <int>[6, 10, 1]);

      // No artificial F#/Gb distinction at the MIDI level: one pitch value
      // (66) represents the root regardless of spelling.
      expect(TargetRoot.fSharp.midiPitch, 66);
      expect(target.notes.map((n) => n.pitch).where((p) => p == 66),
          hasLength(1));
    });
  });

  group('T5 - Major Bb Both-Unison Block', () {
    test('both-unison realizes one pitch set with explicit hand metadata', () {
      final target = factory.build(
        quality: TargetQuality.major,
        root: TargetRoot.bFlat,
        hand: TargetHand.bothUnison,
        mode: TargetMode.block,
      );

      expect(target.targetId, 'major-bFlat-bothUnison-block');
      expect(target.root.label, 'Bb');
      expect(target.hand, TargetHand.bothUnison);
      expect(target.hand.label, 'Both-Unison');

      // One semantic note set - not duplicated per hand.
      expect(target.notes, hasLength(3));
      expect(target.notes.map((n) => n.pitch), <int>[70, 74, 77]);
      expect(target.notes.map((n) => n.index), <int>[0, 1, 2]);
      expect(target.onsetGroups.single.memberEventIndices, <int>[0, 1, 2]);
    });
  });

  group('T6 - immutability', () {
    test('target collections cannot be mutated by callers', () {
      final target = factory.build(
        quality: TargetQuality.major,
        root: TargetRoot.c,
        hand: TargetHand.right,
        mode: TargetMode.block,
      );

      expect(() => target.notes.add(target.notes.first), throwsUnsupportedError);
      expect(() => target.notes.clear(), throwsUnsupportedError);
      expect(() => target.onsetGroups.add(target.onsetGroups.first),
          throwsUnsupportedError);
      expect(() => target.onsetGroups.clear(), throwsUnsupportedError);
      expect(() => target.onsetGroups.single.memberEventIndices.add(4),
          throwsUnsupportedError);
      expect(() => target.onsetGroups.single.memberEventIndices.remove(0),
          throwsUnsupportedError);

      // Internal state remains unchanged regardless of the failed attempts.
      expect(target.notes, hasLength(3));
      expect(target.onsetGroups, hasLength(1));
      expect(target.onsetGroups.single.memberEventIndices, <int>[0, 1, 2]);
    });
  });

  group('T7 - determinism', () {
    test('identical definitions build equivalent targets (no identity check)',
        () {
      ExpectedMusicalTarget build() => factory.build(
            quality: TargetQuality.minor,
            root: TargetRoot.bFlat,
            hand: TargetHand.left,
            mode: TargetMode.block,
          );

      final first = build();
      final second = build();

      expect(second, equals(first));
      expect(second.hashCode, first.hashCode);
      expect(_project(second), _project(first));
    });

    test('builder call order and repeated calls never change the projection',
        () {
      const otherFactory = ExpectedMusicalTargetFactory();
      final a = factory.build(
        quality: TargetQuality.major,
        root: TargetRoot.fSharp,
        hand: TargetHand.right,
        mode: TargetMode.arpeggio,
      );
      final b = otherFactory.build(
        quality: TargetQuality.major,
        root: TargetRoot.fSharp,
        hand: TargetHand.right,
        mode: TargetMode.arpeggio,
      );

      expect(_project(b), _project(a));
      expect(a.targetId, b.targetId);
    });
  });

  group('T8 - timing representation', () {
    test('expected offsets are preserved exactly; no tolerance stored', () {
      final block = factory.build(
        quality: TargetQuality.major,
        root: TargetRoot.c,
        hand: TargetHand.right,
        mode: TargetMode.block,
      );
      final arpeggio = factory.build(
        quality: TargetQuality.major,
        root: TargetRoot.c,
        hand: TargetHand.right,
        mode: TargetMode.arpeggio,
      );

      expect(block.onsetGroups.single.expectedOnsetOffsetMs, 0);
      expect(arpeggio.onsetGroups.map((g) => g.expectedOnsetOffsetMs),
          <int>[0, 250, 500, 750]);

      final keys = arpeggio.toMap().keys.toSet();
      expect(keys.any((k) => k.contains('tolerance')), isFalse);
      expect(keys.any((k) => k.contains('threshold')), isFalse);
      expect(keys.any((k) => k.contains('acceptable')), isFalse);
    });
  });

  group('T9 - block vs arpeggio structural difference', () {
    test('block groups many notes; arpeggio orders its groups', () {
      final block = factory.build(
        quality: TargetQuality.major,
        root: TargetRoot.c,
        hand: TargetHand.right,
        mode: TargetMode.block,
      );
      final arpeggio = factory.build(
        quality: TargetQuality.major,
        root: TargetRoot.c,
        hand: TargetHand.right,
        mode: TargetMode.arpeggio,
      );

      expect(block.onsetGroups, hasLength(1));
      expect(block.onsetGroups.single.memberEventIndices, hasLength(3));

      expect(arpeggio.onsetGroups, hasLength(4));
      for (var i = 0; i < arpeggio.onsetGroups.length; i++) {
        expect(arpeggio.onsetGroups[i].memberEventIndices, <int>[i]);
      }

      // Neither representation carries any evaluation artifact.
      for (final target in <ExpectedMusicalTarget>[block, arpeggio]) {
        expect(_forbiddenEvaluationKeys(target.toMap().keys), isEmpty);
      }
    });
  });

  group('T10 - target/event ordering', () {
    test('event and group indices are deterministic and ascending', () {
      for (final mode in TargetMode.values) {
        final target = factory.build(
          quality: TargetQuality.minor,
          root: TargetRoot.bFlat,
          hand: TargetHand.bothUnison,
          mode: mode,
        );
        final noteIndices = target.notes.map((n) => n.index).toList();
        expect(noteIndices, List<int>.generate(noteIndices.length, (i) => i));

        final groupIndices = target.onsetGroups.map((g) => g.index).toList();
        expect(groupIndices, List<int>.generate(groupIndices.length, (i) => i));
      }
    });
  });

  group('T11 - invalid target input', () {
    test('empty expected note set is rejected', () {
      expect(
          () => ExpectedMusicalTarget(
            targetId: 'x',
            quality: TargetQuality.major,
            root: TargetRoot.c,
            hand: TargetHand.right,
            mode: TargetMode.block,
            notes: <ExpectedNoteEvent>[],
            onsetGroups: <ExpectedOnsetGroup>[],
          ),
          throwsFormatException);
    });

    test('duplicate or out-of-order note indices are rejected', () {
      ExpectedMusicalTarget buildWith(List<ExpectedNoteEvent> notes,
              List<ExpectedOnsetGroup> groups) =>
          ExpectedMusicalTarget(
            targetId: 'x',
            quality: TargetQuality.major,
            root: TargetRoot.c,
            hand: TargetHand.right,
            mode: TargetMode.block,
            notes: notes,
            onsetGroups: groups,
          );

      final ok = <ExpectedNoteEvent>[
        ExpectedNoteEvent(index: 0, pitch: 60),
        ExpectedNoteEvent(index: 1, pitch: 64),
        ExpectedNoteEvent(index: 2, pitch: 67),
      ];
      expect(
          () => buildWith(
                <ExpectedNoteEvent>[
                  ExpectedNoteEvent(index: 0, pitch: 60),
                  ExpectedNoteEvent(index: 0, pitch: 64),
                  ExpectedNoteEvent(index: 2, pitch: 67),
                ],
                <ExpectedOnsetGroup>[
                  ExpectedOnsetGroup(
                      index: 0, memberEventIndices: <int>[0, 1, 2]),
                ],
              ),
          throwsFormatException);
      expect(
          () => buildWith(
                <ExpectedNoteEvent>[
                  ExpectedNoteEvent(index: 2, pitch: 67),
                  ExpectedNoteEvent(index: 1, pitch: 64),
                  ExpectedNoteEvent(index: 0, pitch: 60),
                ],
                <ExpectedOnsetGroup>[
                  ExpectedOnsetGroup(
                      index: 0, memberEventIndices: <int>[0, 1, 2]),
                ],
              ),
          throwsFormatException);
      expect(() => buildWith(ok, <ExpectedOnsetGroup>[]), returnsNormally);
    });

    test('invalid MIDI pitch is rejected', () {
      expect(() => ExpectedNoteEvent(index: 0, pitch: 128), throwsFormatException);
      expect(() => ExpectedNoteEvent(index: 0, pitch: -1), throwsFormatException);
      expect(() => ExpectedNoteEvent(index: -1, pitch: 60), throwsFormatException);
    });

    test('invalid onset group input is rejected', () {
      expect(
          () => ExpectedOnsetGroup(
              index: 0, memberEventIndices: <int>[], expectedOnsetOffsetMs: 0),
          throwsFormatException);
      expect(
          () => ExpectedOnsetGroup(
              index: 0,
              memberEventIndices: <int>[0, 0],
              expectedOnsetOffsetMs: 0),
          throwsFormatException);
      expect(
          () => ExpectedOnsetGroup(
              index: 0,
              memberEventIndices: <int>[0],
              expectedOnsetOffsetMs: -5),
          throwsFormatException);
    });

    test('group member referencing a missing note is rejected', () {
      expect(
          () => ExpectedMusicalTarget(
            targetId: 'x',
            quality: TargetQuality.major,
            root: TargetRoot.c,
            hand: TargetHand.right,
            mode: TargetMode.block,
            notes: <ExpectedNoteEvent>[
              ExpectedNoteEvent(index: 0, pitch: 60),
              ExpectedNoteEvent(index: 1, pitch: 64),
              ExpectedNoteEvent(index: 2, pitch: 67),
            ],
            onsetGroups: <ExpectedOnsetGroup>[
              ExpectedOnsetGroup(index: 0, memberEventIndices: <int>[0, 1, 3]),
            ],
          ),
          throwsFormatException);
    });

    test('malformed serialization fails deterministically', () {
      final target = factory.build(
        quality: TargetQuality.major,
        root: TargetRoot.c,
        hand: TargetHand.right,
        mode: TargetMode.block,
      );
      final map = target.toMap()..remove('notes');
      expect(() => ExpectedMusicalTarget.fromMap(map), throwsFormatException);

      final badRoot = target.toMap()..['root'] = 'gSharp';
      expect(() => ExpectedMusicalTarget.fromMap(badRoot), throwsFormatException);

      expect(
          () => ExpectedMusicalTarget.fromMap(<String, Object?>{
            ...target.toMap(),
            'notes': <Object?>['not-a-map'],
          }),
          throwsFormatException);
    });
  });

  group('T12 - no evaluation leakage', () {
    test('target, note, and group maps contain no evaluation concepts', () {
      final target = factory.build(
        quality: TargetQuality.major,
        root: TargetRoot.bFlat,
        hand: TargetHand.bothUnison,
        mode: TargetMode.arpeggio,
      );

      final allKeys = <String>{
        ...target.toMap().keys,
        ...target.notes.expand((n) => n.toMap().keys),
        ...target.onsetGroups.expand((g) => g.toMap().keys),
      };
      for (final key in allKeys) {
        for (final word in _forbiddenEvalKeys) {
          expect(key.toLowerCase().contains(word), isFalse,
              reason: 'key "$key" must not leak evaluation concept "$word"');
        }
      }
    });
  });

  group('serialization round-trip', () {
    test('toMap/fromMap preserve all fields, ordering, and nullability', () {
      for (final form in <(TargetQuality, TargetRoot, TargetHand, TargetMode)>[
        (TargetQuality.major, TargetRoot.c, TargetHand.right, TargetMode.block),
        (TargetQuality.major, TargetRoot.c, TargetHand.right,
            TargetMode.arpeggio),
        (TargetQuality.minor, TargetRoot.c, TargetHand.left, TargetMode.block),
        (TargetQuality.major, TargetRoot.fSharp, TargetHand.right,
            TargetMode.block),
        (TargetQuality.major, TargetRoot.bFlat, TargetHand.bothUnison,
            TargetMode.block),
      ]) {
        final original = factory.build(
          quality: form.$1,
          root: form.$2,
          hand: form.$3,
          mode: form.$4,
        );
        final restored = ExpectedMusicalTarget.fromMap(original.toMap());

        expect(_project(restored), _project(original), reason: form.toString());
        expect(restored, equals(original));
        expect(restored.notes[0].channel, isNull); // nullability preserved
        expect(restored.modelVersion, original.modelVersion);
      }
    });
  });

  group('H2.4 coexistence - ExpectedMusicalTarget + MusicalEvent', () {
    test('target and observed stream coexist as independent structures', () {
      // Build the target side.
      final expected = factory.build(
        quality: TargetQuality.major,
        root: TargetRoot.c,
        hand: TargetHand.right,
        mode: TargetMode.block,
      );

      // Build the observed side through the frozen H2.4 pipeline.
      const normalizer = MidiNormalizer();
      const interpreter = MusicalEventInterpreter();
      final raw = <RawMidiEvent>[
        _rawOn(0, 1000, 60),
        _rawOn(1, 1003, 64),
        _rawOn(2, 1007, 67),
      ];
      final observed = interpreter.interpret(normalizer.normalizeAll(raw));

      // Both structures exist and carry the same pitch observation, yet remain
      // two independent models. No Expected <-> Actual matcher is implemented.
      expect(expected.notes.map((n) => n.pitch), <int>[60, 64, 67]);
      expect(observed.map((e) => e.pitch), <int>[60, 64, 67]);

      // Independence is structural: types do not overlap and nothing here
      // produces a correctness verdict.
      expect(observed.whereType<ExpectedNoteEvent>(), isEmpty);
      expect(expected.notes.whereType<MusicalEvent>(), isEmpty);
    });
  });
}

RawMidiEvent _rawOn(int seq, int ts, int pitch) => RawMidiEvent(
      sessionId: 'practice-1',
      deviceId: 'device',
      connectionType: 'USB',
      seq: seq,
      appMonotonicTsMs: ts,
      messageType: RawMidiMessageType.noteOn,
      channel: 0,
      note: pitch,
      velocity: 100,
      rawBytes: <int>[0x90, pitch, 100],
    );