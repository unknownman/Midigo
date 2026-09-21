import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/midi/application/expected_musical_target_factory.dart';
import 'package:miditutor/midi/application/midi_normalizer.dart';
import 'package:miditutor/midi/application/musical_event_interpreter.dart';
import 'package:miditutor/midi/application/structural_aligner.dart';
import 'package:miditutor/midi/domain/expected_musical_target.dart';
import 'package:miditutor/midi/domain/expected_note_event.dart';
import 'package:miditutor/midi/domain/musical_event.dart';
import 'package:miditutor/midi/domain/normalized_midi_event.dart';
import 'package:miditutor/midi/domain/raw_midi_event.dart';
import 'package:miditutor/midi/domain/structural_alignment.dart';

const _session = 'h26-session';
const _otherSession = 'h26-other-session';

String _project(StructuralAlignment alignment) => jsonEncode(alignment.toMap());

const _forbiddenEvalWords = <String>[
  'score',
  'correct',
  'pass',
  'fail',
  'tolerance',
  'threshold',
  'error',
  'vector',
  'mastery',
  'evidence',
  'scheduler',
  'grade',
  'qualified',
  'attempt',
  'skill',
  'exercise',
];

Set<String> _collectKeys(Object? value, Set<String> into) {
  if (value is Map) {
    for (final entry in value.entries) {
      into.add(entry.key.toString().toLowerCase());
      _collectKeys(entry.value, into);
    }
  } else if (value is List) {
    for (final item in value) {
      _collectKeys(item, into);
    }
  }
  return into;
}

NormalizedMidiEvent _norm(int seq, int ts, int? note,
        {String session = _session, String kind = 'on'}) =>
    NormalizedMidiEvent(
      source: RawMidiEvent(
        sessionId: session,
        deviceId: 'dev',
        connectionType: 'USB',
        seq: seq,
        appMonotonicTsMs: ts,
        messageType: switch (kind) {
          'off' => RawMidiMessageType.noteOff,
          'other' => RawMidiMessageType.other,
          _ => RawMidiMessageType.noteOn,
        },
        channel: 0,
        note: note,
        velocity: 90,
        rawBytes: <int>[0x90, note ?? 0, 90],
      ),
      type: switch (kind) {
        'off' => NormalizedMidiMessageType.noteOff,
        'other' => NormalizedMidiMessageType.other,
        _ => NormalizedMidiMessageType.noteOn,
      },
      normalizationRule: 'verbatim',
    );

MusicalEvent _lifecycle(int idx, int ts, int pitch,
        {String session = _session}) =>
    MusicalEvent(
      eventIndex: idx,
      sessionId: session,
      type: MusicalSemanticType.noteLifecycle,
      startTimestampMs: ts,
      endTimestampMs: ts + 100,
      channel: 0,
      pitch: pitch,
      velocity: 90,
      durationMs: 100,
      sources: <NormalizedMidiEvent>[
        _norm(idx, ts, pitch, session: session),
        _norm(idx, ts + 100, pitch, session: session, kind: 'off'),
      ],
    );

MusicalEvent _attack(int idx, int ts, int pitch, {String session = _session}) =>
    MusicalEvent(
      eventIndex: idx,
      sessionId: session,
      type: MusicalSemanticType.noteAttack,
      startTimestampMs: ts,
      channel: 0,
      pitch: pitch,
      velocity: 90,
      sources: <NormalizedMidiEvent>[_norm(idx, ts, pitch, session: session)],
    );

MusicalEvent _release(int idx, int ts, int pitch, {String session = _session}) =>
    MusicalEvent(
      eventIndex: idx,
      sessionId: session,
      type: MusicalSemanticType.noteRelease,
      startTimestampMs: ts,
      channel: 0,
      pitch: pitch,
      sources: <NormalizedMidiEvent>[
        _norm(idx, ts, pitch, session: session, kind: 'off'),
      ],
    );

MusicalEvent _nonNote(int idx, int ts, {String session = _session}) =>
    MusicalEvent(
      eventIndex: idx,
      sessionId: session,
      type: MusicalSemanticType.nonNote,
      startTimestampMs: ts,
      sources: <NormalizedMidiEvent>[
        _norm(idx, ts, null, session: session, kind: 'other'),
      ],
    );

MusicalEvent _anomaly(int idx, int ts, String category,
        {String session = _session}) =>
    MusicalEvent(
      eventIndex: idx,
      sessionId: session,
      type: MusicalSemanticType.integrityAnomaly,
      startTimestampMs: ts,
      channel: 0,
      pitch: 60,
      anomalyCategory: category,
      sources: <NormalizedMidiEvent>[_norm(idx, ts, 60, session: session)],
    );

ExpectedMusicalTarget _blockTarget(List<int> pitches,
        {String targetId = 't-block'}) =>
    ExpectedMusicalTarget(
      targetId: targetId,
      quality: TargetQuality.major,
      root: TargetRoot.c,
      hand: TargetHand.right,
      mode: TargetMode.block,
      notes: <ExpectedNoteEvent>[
        for (var i = 0; i < pitches.length; i++)
          ExpectedNoteEvent(index: i, pitch: pitches[i]),
      ],
      onsetGroups: <ExpectedOnsetGroup>[
        ExpectedOnsetGroup(
          index: 0,
          memberEventIndices: <int>[for (var i = 0; i < pitches.length; i++) i],
          expectedOnsetOffsetMs: 0,
        ),
      ],
    );

void main() {
  const factory = ExpectedMusicalTargetFactory();
  const aligner = StructuralAligner();

  group('T1 - exact block match', () {
    test('three associations, no unmatched, provenance preserved', () {
      final target = factory.build(
        quality: TargetQuality.major,
        root: TargetRoot.c,
        hand: TargetHand.right,
        mode: TargetMode.block,
      );
      final observed = List<MusicalEvent>.of(<MusicalEvent>[
        _lifecycle(0, 1000, 60),
        _lifecycle(1, 1002, 64),
        _lifecycle(2, 1004, 67),
      ]);

      final result = aligner.align(
          target: target, sessionId: _session, observed: observed);

      expect(result.matches, hasLength(3));
      expect(result.matches.map((m) => m.expectedNoteIndex), <int>[0, 1, 2]);
      expect(result.matches.map((m) => m.expectedPitch), <int>[60, 64, 67]);
      expect(result.matches.map((m) => m.observedEventIndex), <int>[0, 1, 2]);
      expect(result.matches.map((m) => m.observedPitch), <int>[60, 64, 67]);
      expect(result.matches.map((m) => m.observedOnsetTimestampMs),
          <int>[1000, 1002, 1004]);
      expect(
          result.matches.every(
              (m) => m.expectedGroupIndex == 0 && m.expectedOnsetOffsetMs == 0),
          isTrue);
      expect(
          result.matches.every(
              (m) => m.observedType == MusicalSemanticType.noteLifecycle),
          isTrue);
      expect(result.unmatchedExpected, isEmpty);
      expect(result.unmatchedObserved, isEmpty);
      expect(result.targetId, target.targetId);
      expect(result.sessionId, _session);
      expect(result.mode, TargetMode.block);
      expect(result.algorithmVersion, StructuralAligner.algorithmVersion);
    });
  });

  group('T2 - missing expected pitch', () {
    test('expected E4 remains unmatched', () {
      final target = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.block);
      final result = aligner.align(
        target: target,
        sessionId: _session,
        observed: <MusicalEvent>[_lifecycle(0, 1000, 60), _lifecycle(1, 1002, 67)],
      );

      expect(result.matches, hasLength(2));
      expect(result.matches.map((m) => m.expectedNoteIndex), <int>[0, 2]);
      expect(result.unmatchedExpected, hasLength(1));
      expect(result.unmatchedExpected.single.expectedNoteIndex, 1);
      expect(result.unmatchedExpected.single.expectedPitch, 64);
      expect(result.unmatchedExpected.single.expectedGroupIndex, 0);
      expect(result.unmatchedObserved, isEmpty);
    });
  });

  group('T3 - extra observed pitch', () {
    test('observed D4 remains unmatched', () {
      final target = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.block);
      final result = aligner.align(
        target: target,
        sessionId: _session,
        observed: <MusicalEvent>[
          _lifecycle(0, 1000, 60),
          _lifecycle(1, 1002, 62),
          _lifecycle(2, 1004, 64),
          _lifecycle(3, 1006, 67),
        ],
      );

      expect(result.matches, hasLength(3));
      expect(result.matches.map((m) => m.expectedNoteIndex), <int>[0, 1, 2]);
      expect(result.unmatchedExpected, isEmpty);
      expect(result.unmatchedObserved, hasLength(1));
      expect(result.unmatchedObserved.single.observedEventIndex, 1);
      expect(result.unmatchedObserved.single.observedPitch, 62);
      expect(result.unmatchedObserved.single.observedOnsetTimestampMs, 1002);
    });
  });

  group('T4 - different pitch only', () {
    test('E4 expected unmatched, F4 observed unmatched, no verdict issued', () {
      final target = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.block);
      final result = aligner.align(
        target: target,
        sessionId: _session,
        observed: <MusicalEvent>[
          _lifecycle(0, 1000, 60),
          _lifecycle(1, 1002, 65),
          _lifecycle(2, 1004, 67),
        ],
      );

      expect(result.matches.map((m) => m.expectedNoteIndex), <int>[0, 2]);
      expect(result.matches.map((m) => m.observedEventIndex), <int>[0, 2]);
      expect(result.unmatchedExpected.single.expectedPitch, 64);
      expect(result.unmatchedObserved.single.observedPitch, 65);
    });
  });

  group('T5 - exact arpeggio match', () {
    test('one-to-one deterministic associations in expected order', () {
      final target = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.arpeggio);
      final result = aligner.align(
        target: target,
        sessionId: _session,
        observed: <MusicalEvent>[
          _lifecycle(0, 1000, 60),
          _lifecycle(1, 1240, 64),
          _lifecycle(2, 1500, 67),
          _lifecycle(3, 1780, 72),
        ],
      );

      expect(result.matches, hasLength(4));
      expect(result.matches.map((m) => m.expectedNoteIndex), <int>[0, 1, 2, 3]);
      expect(result.matches.map((m) => m.observedEventIndex), <int>[0, 1, 2, 3]);
      expect(result.matches.map((m) => m.expectedGroupIndex), <int>[0, 1, 2, 3]);
      expect(result.matches.map((m) => m.expectedOnsetOffsetMs),
          <int>[0, 250, 500, 750]);
      expect(result.unmatchedExpected, isEmpty);
      expect(result.unmatchedObserved, isEmpty);
    });
  });

  group('T6 - arpeggio reordered', () {
    test('associations and observed indices stay visible; no order verdict', () {
      final target = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.arpeggio);
      final result = aligner.align(
        target: target,
        sessionId: _session,
        observed: <MusicalEvent>[
          _lifecycle(0, 1000, 60),
          _lifecycle(1, 1002, 67),
          _lifecycle(2, 1004, 64),
          _lifecycle(3, 1006, 72),
        ],
      );

      expect(result.matches, hasLength(4));
      // Expected order preserved; observed order exposed, never judged.
      expect(result.matches.map((m) => m.expectedNoteIndex), <int>[0, 1, 2, 3]);
      expect(result.matches.map((m) => m.observedEventIndex), <int>[0, 2, 1, 3]);
      expect(result.matches.map((m) => m.observedPitch), <int>[60, 64, 67, 72]);
      expect(result.unmatchedExpected, isEmpty);
      expect(result.unmatchedObserved, isEmpty);
    });
  });

  group('T7 - duplicate observed pitch', () {
    test('one observed C4 consumed, second unmatched, deterministic', () {
      final target = _blockTarget(<int>[60]);
      final result = aligner.align(
        target: target,
        sessionId: _session,
        observed: <MusicalEvent>[_lifecycle(0, 1000, 60), _lifecycle(1, 1002, 60)],
      );

      expect(result.matches, hasLength(1));
      expect(result.matches.single.observedEventIndex, 0);
      expect(result.unmatchedExpected, isEmpty);
      expect(result.unmatchedObserved, hasLength(1));
      expect(result.unmatchedObserved.single.observedEventIndex, 1);
    });
  });

  group('T8 - duplicate expected pitch', () {
    test('one-to-one deterministic consumption for two expected C4s', () {
      // Target validation permits duplicate *pitches* (only indices must be
      // unique); duplicate-pitch targets are therefore constructible.
      final target = _blockTarget(<int>[60, 60]);
      final result = aligner.align(
        target: target,
        sessionId: _session,
        observed: <MusicalEvent>[_lifecycle(0, 1000, 60), _lifecycle(1, 1002, 60)],
      );

      expect(result.matches, hasLength(2));
      expect(result.matches.map((m) => m.expectedNoteIndex), <int>[0, 1]);
      expect(result.matches.map((m) => m.observedEventIndex), <int>[0, 1]);
      expect(result.unmatchedExpected, isEmpty);
      expect(result.unmatchedObserved, isEmpty);
    });

    test('earliest expected consumes earliest candidate', () {
      final target = _blockTarget(<int>[60, 60]);
      final result = aligner.align(
        target: target,
        sessionId: _session,
        observed: <MusicalEvent>[_lifecycle(0, 1000, 60), _lifecycle(1, 1002, 60)],
      );
      expect(result.matches[0].expectedNoteIndex, 0);
      expect(result.matches[0].observedEventIndex, 0);
      // No observed event was consumed twice.
      expect(result.matches.map((m) => m.observedEventIndex).toSet(),
          hasLength(2));
    });
  });

  group('T9 - unmatched note-on', () {
    test('attack with no release participates in structural association', () {
      final target = _blockTarget(<int>[60]);
      final result = aligner.align(
        target: target,
        sessionId: _session,
        observed: <MusicalEvent>[_attack(0, 1000, 60)],
      );

      expect(result.matches, hasLength(1));
      final match = result.matches.single;
      expect(match.observedEventIndex, 0);
      expect(match.observedPitch, 60);
      expect(match.observedEndTimestampMs, isNull);
      expect(match.observedType, MusicalSemanticType.noteAttack);
      expect(result.unmatchedExpected, isEmpty);
      expect(result.unmatchedObserved, isEmpty);
    });
  });

  group('T10 - unmatched note-off', () {
    test('release alone creates no expected-note association', () {
      final target = _blockTarget(<int>[60]);
      final result = aligner.align(
        target: target,
        sessionId: _session,
        observed: <MusicalEvent>[_release(0, 1000, 60)],
      );

      expect(result.matches, isEmpty);
      expect(result.unmatchedExpected.single.expectedPitch, 60);
      expect(result.unmatchedObserved, isEmpty);
      expect(result.ignoredNonNoteEventRefs, isEmpty);
      expect(result.ignoredIntegrityAnomalyEventRefs, isEmpty);
    });
  });

  group('T11 - non-note events', () {
    test('note associations unaffected by interleaved control changes', () {
      final target = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.block);
      final result = aligner.align(
        target: target,
        sessionId: _session,
        observed: <MusicalEvent>[
          _lifecycle(0, 1000, 60),
          _nonNote(1, 1005),
          _lifecycle(2, 1010, 64),
          _nonNote(3, 1015),
          _lifecycle(4, 1020, 67),
        ],
      );

      expect(result.matches, hasLength(3));
      expect(result.matches.map((m) => m.observedEventIndex), <int>[0, 2, 4]);
      expect(result.ignoredNonNoteEventRefs, <int>[1, 3]);
      expect(result.unmatchedExpected, isEmpty);
      expect(result.unmatchedObserved, isEmpty);
    });
  });

  group('T12 - integrity anomaly', () {
    test('anomalies surfaced as ignored refs, never repaired or matched', () {
      final target = _blockTarget(<int>[60]);
      final result = aligner.align(
        target: target,
        sessionId: _session,
        observed: <MusicalEvent>[
          _anomaly(0, 990, 'duplicate_sequence'),
          _lifecycle(1, 1000, 60),
          _anomaly(2, 1010, 'timestamp_regression'),
        ],
      );

      expect(result.matches, hasLength(1));
      expect(result.matches.single.observedEventIndex, 1);
      expect(result.ignoredIntegrityAnomalyEventRefs, <int>[0, 2]);
      // Anomaly events did not join the candidate pool at all.
      expect(result.unmatchedObserved, isEmpty);
      expect(result.unmatchedExpected, isEmpty);
    });
  });

  group('T13 - multiple sessions', () {
    test('alignment isolated to selected session', () {
      final target = _blockTarget(<int>[60]);
      final observed = <MusicalEvent>[
        _lifecycle(0, 1000, 60, session: _session),
        _lifecycle(1, 1000, 60, session: _otherSession),
      ];

      final a = aligner.align(target: target, sessionId: _session, observed: observed);
      expect(a.sessionId, _session);
      expect(a.matches.single.observedEventIndex, 0);
      expect(a.ignoredOtherSessionEventRefs, <int>[1]);

      final b = aligner.align(target: target, sessionId: _otherSession, observed: observed);
      expect(b.sessionId, _otherSession);
      expect(b.matches.single.observedEventIndex, 1);
      expect(b.ignoredOtherSessionEventRefs, <int>[0]);
    });
  });

  group('T14 - determinism', () {
    test('identical input produces identical projection, not identity', () {
      final target = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.block);
      final observed = List<MusicalEvent>.of(<MusicalEvent>[
        _lifecycle(0, 1000, 60),
        _lifecycle(1, 1002, 67),
      ]);

      final first = aligner.align(target: target, sessionId: _session, observed: observed);
      final second = aligner.align(target: target, sessionId: _session, observed: observed);

      expect(identical(first, second), isFalse);
      expect(_project(second), _project(first));
      expect(second, equals(first));
      expect(second.hashCode, first.hashCode);
    });
  });

  group('T15 - immutability', () {
    test('target and observed stream not mutated; output immutable', () {
      final target = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.block);
      final observed = List<MusicalEvent>.of(<MusicalEvent>[
        _lifecycle(0, 1000, 60),
        _nonNote(1, 1002),
        _lifecycle(2, 1004, 67),
        _lifecycle(3, 1006, 62),
      ]);
      final before = observed.map((e) => e.eventIndex).toList(growable: false);

      final result = aligner.align(target: target, sessionId: _session, observed: observed);

      expect(observed.map((e) => e.eventIndex).toList(), before);
      expect(target.notes, hasLength(3));
      expect(result.unmatchedExpected, hasLength(1));
      expect(result.unmatchedObserved, hasLength(1));
      expect(() => result.matches.add(result.matches.first), throwsUnsupportedError);
      expect(() => result.unmatchedExpected.add(result.unmatchedExpected.first),
          throwsUnsupportedError);
      expect(() => result.unmatchedObserved.add(result.unmatchedObserved.first),
          throwsUnsupportedError);
      expect(() => result.ignoredNonNoteEventRefs.add(0), throwsUnsupportedError);
    });
  });

  group('T16 - H2.5 / H2.4 coexistence', () {
    test('target, observed stream, and alignment stay independent models', () {
      final target = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.block);

      final raw = <RawMidiEvent>[
        _rawOn(0, 1000, 60),
        _rawOn(1, 1003, 64),
        _rawOn(2, 1007, 67),
        _rawOff(3, 1100, 60),
        _rawOff(4, 1103, 64),
        _rawOff(5, 1107, 67),
      ];
      final observed = const MusicalEventInterpreter()
          .interpret(const MidiNormalizer().normalizeAll(raw));

      final result = aligner.align(target: target, sessionId: _session, observed: observed);

      expect(observed.map((e) => e.pitch), <int?>[60, 64, 67]);
      expect(result.targetId, target.targetId);
      expect(result.matches, hasLength(3));
      expect(result.matches.map((m) => m.expectedNoteIndex), <int>[0, 1, 2]);
      expect(result.matches.map((m) => m.observedEventIndex), <int>[0, 1, 2]);

      expect(result is ExpectedMusicalTarget, isFalse);
      expect(result.matches.every((m) => m is MusicalEvent), isFalse);
      expect(result.matches.every((m) => m is ExpectedNoteEvent), isFalse);
    });
  });

  group('T17 - no evaluation leakage', () {
    test('alignment maps contain no evaluation concepts', () {
      final target = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.block);
      final result = aligner.align(
        target: target,
        sessionId: _session,
        observed: <MusicalEvent>[
          _anomaly(0, 990, 'duplicate_sequence'),
          _lifecycle(1, 1000, 60),
          _nonNote(2, 1002),
          _lifecycle(3, 1004, 67),
          _release(4, 1100, 70),
        ],
      );

      final keys = _collectKeys(result.toMap(), <String>{});
      for (final key in keys) {
        for (final word in _forbiddenEvalWords) {
          expect(key.contains(word), isFalse,
              reason: 'key "$key" must not leak evaluation concept "$word"');
        }
      }
    });
  });
}

RawMidiEvent _rawOn(int seq, int ts, int pitch) => RawMidiEvent(
      sessionId: _session,
      deviceId: 'device',
      connectionType: 'USB',
      seq: seq,
      appMonotonicTsMs: ts,
      messageType: RawMidiMessageType.noteOn,
      channel: 0,
      note: pitch,
      velocity: 90,
      rawBytes: <int>[0x90, pitch, 90],
    );

RawMidiEvent _rawOff(int seq, int ts, int pitch) => RawMidiEvent(
      sessionId: _session,
      deviceId: 'device',
      connectionType: 'USB',
      seq: seq,
      appMonotonicTsMs: ts,
      messageType: RawMidiMessageType.noteOff,
      channel: 0,
      note: pitch,
      velocity: 0,
      rawBytes: <int>[0x80, pitch, 0],
    );