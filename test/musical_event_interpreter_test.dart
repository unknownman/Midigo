import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/midi/application/midi_normalizer.dart';
import 'package:miditutor/midi/application/musical_event_interpreter.dart';
import 'package:miditutor/midi/application/raw_midi_jsonl_reader.dart';
import 'package:miditutor/midi/domain/musical_event.dart';
import 'package:miditutor/midi/domain/normalized_midi_event.dart';
import 'package:miditutor/midi/domain/raw_midi_event.dart';

RawMidiEvent rawOn({
  required String sessionId,
  required int seq,
  required int ts,
  required int pitch,
  required int velocity,
  int channel = 0,
}) {
  final status = 0x90 | channel;
  return RawMidiEvent(
    sessionId: sessionId,
    deviceId: 'device',
    connectionType: 'USB',
    seq: seq,
    appMonotonicTsMs: ts,
    messageType: RawMidiMessageType.noteOn,
    channel: channel,
    note: pitch,
    velocity: velocity,
    rawBytes: <int>[status, pitch, velocity],
  );
}

RawMidiEvent rawOff({
  required String sessionId,
  required int seq,
  required int ts,
  required int pitch,
  int channel = 0,
}) {
  final status = 0x80 | channel;
  return RawMidiEvent(
    sessionId: sessionId,
    deviceId: 'device',
    connectionType: 'USB',
    seq: seq,
    appMonotonicTsMs: ts,
    messageType: RawMidiMessageType.noteOff,
    channel: channel,
    note: pitch,
    velocity: 0,
    rawBytes: <int>[status, pitch, 0],
  );
}

RawMidiEvent rawCc({required String sessionId, required int seq, required int ts}) {
  return RawMidiEvent(
    sessionId: sessionId,
    deviceId: 'device',
    connectionType: 'USB',
    seq: seq,
    appMonotonicTsMs: ts,
    messageType: RawMidiMessageType.other,
    channel: 0,
    rawBytes: const <int>[0xB0, 64, 127],
  );
}

String fixture(String name) => File('test/fixtures/$name.jsonl').readAsStringSync();

void main() {
  const normalizer = MidiNormalizer();
  const interpreter = MusicalEventInterpreter();

  List<NormalizedMidiEvent> norm(List<RawMidiEvent> raw) =>
      normalizer.normalizeAll(raw);

  group('F1 - single valid note lifecycle', () {
    test('C4 on then off observes one semantic lifecycle with duration', () {
      final semantic = interpreter.interpret(norm([
        rawOn(sessionId: 's1', seq: 0, ts: 1000, pitch: 60, velocity: 100),
        rawOff(sessionId: 's1', seq: 1, ts: 1500, pitch: 60),
      ]));

      expect(semantic, hasLength(1));
      final event = semantic.single;
      expect(event.type, MusicalSemanticType.noteLifecycle);
      expect(event.eventIndex, 0);
      expect(event.pitch, 60);
      expect(event.pitchClass, 0);
      expect(event.channel, 0);
      expect(event.startTimestampMs, 1000);
      expect(event.onsetTimestampMs, 1000);
      expect(event.endTimestampMs, 1500);
      expect(event.releaseTimestampMs, 1500);
      expect(event.durationMs, 500);
      expect(event.velocity, 100);
      expect(event.anomalyCategory, isNull);
      expect(event.sources, hasLength(2));
      expect(event.sourceOn!.sourceSeq, 0);
      expect(event.sourceOff!.sourceSeq, 1);
    });
  });

  group('F2 - velocity-zero release', () {
    test('raw v0 Note-On normalizes to the release side of one lifecycle', () {
      final raw = <RawMidiEvent>[
        rawOn(sessionId: 's1', seq: 0, ts: 1000, pitch: 60, velocity: 100),
        rawOn(sessionId: 's1', seq: 1, ts: 1300, pitch: 60, velocity: 0),
      ];
      final normalized = norm(raw);
      final semantic = interpreter.interpret(normalized);

      // Raw second event is untouched: still a Note-On with velocity 0.
      expect(raw[1].messageType, RawMidiMessageType.noteOn);
      expect(raw[1].velocity, 0);
      expect(raw[1].rawBytes, <int>[144, 60, 0]);

      // H2.1 derives a Note-Off from the velocity-zero Note-On.
      expect(normalized[1].type, NormalizedMidiMessageType.noteOff);
      expect(normalized[1].normalizationRule, 'note_on_velocity_zero');
      expect(identical(normalized[1].source, raw[1]), isTrue);

      // The release side was observed; nothing is fabricated.
      expect(semantic, hasLength(1));
      final event = semantic.single;
      expect(event.type, MusicalSemanticType.noteLifecycle);
      expect(event.endTimestampMs, 1300);
      expect(event.releaseTimestampMs, 1300);
      expect(event.durationMs, 300);
      expect(identical(event.sourceOff, normalized[1]), isTrue);
      expect(identical(event.sourceOn, normalized[0]), isTrue);
    });
  });

  group('F3 - three-note burst', () {
    test('three observed note attacks, order preserved, no chord label', () {
      final semantic = interpreter.interpret(norm([
        rawOn(sessionId: 's1', seq: 0, ts: 1000, pitch: 60, velocity: 80),
        rawOn(sessionId: 's1', seq: 1, ts: 1040, pitch: 64, velocity: 80),
        rawOn(sessionId: 's1', seq: 2, ts: 1059, pitch: 67, velocity: 80),
      ]));

      expect(semantic, hasLength(3));
      expect(semantic.map((e) => e.type).toSet(),
          <MusicalSemanticType>{MusicalSemanticType.noteAttack});
      expect(semantic.map((e) => e.pitch), <int>[60, 64, 67]);
      expect(semantic.map((e) => e.sourceOn!.sourceSeq), <int>[0, 1, 2]);
      expect(semantic.map((e) => e.startTimestampMs), <int>[1000, 1040, 1059]);
      // The semantic event type set has no chord/arpeggio member by design.
      expect(semantic.any((e) => e.type == MusicalSemanticType.noteLifecycle),
          isFalse);
    });
  });

  group('F4 - arpeggio', () {
    test('four ordered attacks with timestamps preserved, no judgment', () {
      final semantic = interpreter.interpret(norm([
        rawOn(sessionId: 's1', seq: 0, ts: 1000, pitch: 60, velocity: 70),
        rawOn(sessionId: 's1', seq: 1, ts: 1300, pitch: 64, velocity: 70),
        rawOn(sessionId: 's1', seq: 2, ts: 1600, pitch: 67, velocity: 70),
        rawOn(sessionId: 's1', seq: 3, ts: 1900, pitch: 71, velocity: 70),
      ]));

      expect(semantic, hasLength(4));
      expect(semantic.map((e) => e.pitch), <int>[60, 64, 67, 71]);
      expect(semantic.map((e) => e.startTimestampMs), <int>[1000, 1300, 1600, 1900]);
      expect(semantic.map((e) => e.eventIndex), <int>[0, 1, 2, 3]);
      expect(semantic.every((e) => e.endTimestampMs == null), isTrue);
    });
  });

  group('F5 - unmatched Note-On', () {
    test('lifecycle-less attack with null release and duration', () {
      final semantic = interpreter.interpret(norm([
        rawOn(sessionId: 's1', seq: 0, ts: 1000, pitch: 60, velocity: 90),
      ]));

      expect(semantic, hasLength(1));
      final event = semantic.single;
      expect(event.type, MusicalSemanticType.noteAttack);
      expect(event.pitch, 60);
      expect(event.endTimestampMs, isNull);
      expect(event.releaseTimestampMs, isNull);
      expect(event.durationMs, isNull);
      expect(event.velocity, 90);
      expect(event.sourceOn!.sourceSeq, 0);
      expect(event.sourceOff, isNull);
    });
  });

  group('F6 - unmatched Note-Off', () {
    test('explicit unmatched release, source preserved, never discarded', () {
      final semantic = interpreter.interpret(norm([
        rawOff(sessionId: 's1', seq: 0, ts: 1000, pitch: 60),
      ]));

      expect(semantic, hasLength(1));
      final event = semantic.single;
      expect(event.type, MusicalSemanticType.noteRelease);
      expect(event.pitch, 60);
      expect(event.startTimestampMs, 1000);
      expect(event.sourceOff, isNull); // no Note-On, so no lifecycle
      expect(identical(event.sourceOn, event.sources.single), isTrue);
      expect(event.sources.single.type, NormalizedMidiMessageType.noteOff);
    });
  });

  group('F7 - multiple sessions', () {
    test('independent semantic streams, no cross-session lifecycle', () {
      final semantic = interpreter.interpret(norm([
        rawOn(sessionId: 'a', seq: 0, ts: 1000, pitch: 60, velocity: 90),
        rawOn(sessionId: 'b', seq: 0, ts: 100, pitch: 62, velocity: 90),
        rawOff(sessionId: 'a', seq: 1, ts: 2000, pitch: 60),
        rawOff(sessionId: 'b', seq: 1, ts: 200, pitch: 62),
      ]));

      // Sessions emitted in first-seen order (a then b), each internally
      // in capture order.
      expect(semantic.map((e) => e.sessionId), <String>['a', 'b']);

      final lifecycleA = semantic[0];
      expect(lifecycleA.type, MusicalSemanticType.noteLifecycle);
      expect(lifecycleA.startTimestampMs, 1000);
      expect(lifecycleA.endTimestampMs, 2000);
      expect(lifecycleA.durationMs, 1000);

      final lifecycleB = semantic[1];
      expect(lifecycleB.type, MusicalSemanticType.noteLifecycle);
      expect(lifecycleB.startTimestampMs, 100);
      expect(lifecycleB.endTimestampMs, 200);
      expect(lifecycleB.durationMs, 100);
    });
  });

  group('F8 - non-note CC', () {
    test('semantic nonNote with provenance preserved', () {
      final normalized = norm([
        rawCc(sessionId: 's1', seq: 0, ts: 1000),
      ]);
      final semantic = interpreter.interpret(normalized);

      expect(semantic, hasLength(1));
      final event = semantic.single;
      expect(event.type, MusicalSemanticType.nonNote);
      expect(event.startTimestampMs, 1000);
      expect(event.channel, 0);
      expect(event.pitch, isNull);
      expect(event.statusByte, 0xB0);
      expect(identical(event.sourceOn, normalized.single), isTrue);
      expect(normalized.single.normalizationRule, 'other');
    });
  });

  group('F9 - duplicate candidate', () {
    test('both source events remain; no deletion or repair', () {
      final semantic = interpreter.interpret(norm([
        rawOn(sessionId: 's1', seq: 0, ts: 1000, pitch: 60, velocity: 90),
        rawOn(sessionId: 's1', seq: 1, ts: 1003, pitch: 60, velocity: 90),
      ]));

      expect(semantic, hasLength(2));
      expect(semantic.map((e) => e.type).toSet(),
          <MusicalSemanticType>{MusicalSemanticType.noteAttack});
      expect(semantic.map((e) => e.sourceOn!.sourceSeq), <int>[0, 1]);
      expect(semantic.map((e) => e.startTimestampMs), <int>[1000, 1003]);
      expect(semantic.map((e) => e.pitch), <int>[60, 60]);
    });
  });

  group('F10 - timestamp regression / duplicate sequence', () {
    test('no repair; anomaly remains observable; deterministic', () {
      final semantic = interpreter.interpret(norm([
        rawOn(sessionId: 's1', seq: 5, ts: 1000, pitch: 60, velocity: 90),
        rawOn(sessionId: 's1', seq: 3, ts: 999, pitch: 64, velocity: 90),
        rawOn(sessionId: 's1', seq: 3, ts: 1005, pitch: 67, velocity: 90),
      ]));

      final types = semantic.map((e) => e.type).toList();
      expect(types.where((t) => t == MusicalSemanticType.integrityAnomaly),
          hasLength(3));
      expect(types.where((t) => t == MusicalSemanticType.noteAttack), hasLength(3));

      final categories = semantic
          .where((e) => e.type == MusicalSemanticType.integrityAnomaly)
          .map((e) => e.anomalyCategory)
          .toList();
      expect(categories, <String>[
        'sequence_regression',
        'timestamp_regression',
        'duplicate_sequence',
      ]);

      // Attacks keep their original (anomalous) ordering and timestamps.
      final attacks =
          semantic.where((e) => e.type == MusicalSemanticType.noteAttack).toList();
      expect(attacks.map((e) => e.sourceOn!.sourceSeq), <int>[5, 3, 3]);
      expect(attacks.map((e) => e.startTimestampMs), <int>[1000, 999, 1005]);

      // Anomaly events keep provenance to the offending source.
      final anomaly = semantic
          .firstWhere((e) => e.anomalyCategory == 'duplicate_sequence');
      expect(anomaly.sourceOn!.sourceSeq, 3);
    });
  });

  group('F11 - multiple active same-pitch notes', () {
    test('preserves established H2.1 FIFO pairing (no new policy)', () {
      final semantic = interpreter.interpret(norm([
        rawOn(sessionId: 's1', seq: 0, ts: 1000, pitch: 60, velocity: 90),
        rawOn(sessionId: 's1', seq: 1, ts: 1100, pitch: 60, velocity: 90),
        rawOff(sessionId: 's1', seq: 2, ts: 2000, pitch: 60),
        rawOff(sessionId: 's1', seq: 3, ts: 2100, pitch: 60),
      ]));

      // The frozen H2.1 NotePairingAnalyzer is FIFO: the earliest active
      // Note-On consumes the first matching Note-Off. No new pairing policy
      // is invented here, so the established FIFO mapping is preserved.
      expect(semantic, hasLength(2));
      final first = semantic[0];
      final second = semantic[1];
      expect(first.type, MusicalSemanticType.noteLifecycle);
      expect(second.type, MusicalSemanticType.noteLifecycle);
      expect(first.sourceOn!.sourceSeq, 0);
      expect(first.sourceOff!.sourceSeq, 2);
      expect(first.durationMs, 1000);
      expect(second.sourceOn!.sourceSeq, 1);
      expect(second.sourceOff!.sourceSeq, 3);
      expect(second.durationMs, 1000);
      expect(semantic.map((e) => e.startTimestampMs), <int>[1000, 1100]);
    });
  });

  group('F12 - mixed note and non-note stream', () {
    test('deterministic semantic ordering across note/CC/note/CC', () {
      final semantic = interpreter.interpret(norm([
        rawOn(sessionId: 's1', seq: 0, ts: 1000, pitch: 60, velocity: 90),
        rawCc(sessionId: 's1', seq: 1, ts: 1500),
        rawOff(sessionId: 's1', seq: 2, ts: 2000, pitch: 60),
        rawCc(sessionId: 's1', seq: 3, ts: 2500),
      ]));

      expect(semantic, hasLength(3));
      expect(semantic.map((e) => e.type), <MusicalSemanticType>[
        MusicalSemanticType.noteLifecycle,
        MusicalSemanticType.nonNote,
        MusicalSemanticType.nonNote,
      ]);
      expect(semantic[0].sourceOn!.sourceSeq, 0);
      expect(semantic[0].sourceOff!.sourceSeq, 2);
      expect(identical(semantic[1].sourceOn, semantic[1].sources.single), isTrue);
      expect(semantic[1].statusByte, 0xB0);
      expect(semantic[2].sourceOn!.sourceSeq, 3);
      expect(semantic[1].startTimestampMs, 1500);
      expect(semantic[2].startTimestampMs, 2500);
    });
  });

  group('identical timestamps preserve source sequence order', () {
    test('two onset attacks at the same millisecond keep source order', () {
      final semantic = interpreter.interpret(norm([
        rawOn(sessionId: 's1', seq: 4, ts: 1000, pitch: 64, velocity: 90),
        rawOn(sessionId: 's1', seq: 2, ts: 1000, pitch: 60, velocity: 90),
        rawOn(sessionId: 's1', seq: 3, ts: 1000, pitch: 67, velocity: 90),
      ]));

      final attacks = semantic
          .where((e) => e.type == MusicalSemanticType.noteAttack)
          .toList();
      expect(attacks.map((e) => e.sourceOn!.sourceSeq), <int>[4, 2, 3]);
      expect(attacks.map((e) => e.pitch), <int>[64, 60, 67]);
      // The regressing onset also surfaces as an anomaly; nothing is reordered.
      expect(
          semantic
              .where((e) => e.anomalyCategory == 'sequence_regression')
              .single
              .sourceOn!
              .sourceSeq,
          2);
    });
  });

  group('negative durations are retained verbatim', () {
    test('release before onset is unmatched, no fabricated lifecycle', () {
      // FIFO pairing requires a Note-On before the Note-Off; a release that
      // arrives without any active Note-On is an unmatched release.
      final semantic = interpreter.interpret(norm([
        rawOff(sessionId: 's1', seq: 0, ts: 1000, pitch: 60),
        rawOn(sessionId: 's1', seq: 1, ts: 1500, pitch: 60, velocity: 90),
      ]));

      expect(semantic.map((e) => e.type), <MusicalSemanticType>[
        MusicalSemanticType.noteRelease,
        MusicalSemanticType.noteAttack,
      ]);
      expect(semantic[0].sources.single.sourceSeq, 0);
      expect(semantic[1].sources.single.sourceSeq, 1);
    });

    test('onsets after release keep a negative lifecycle duration verbatim', () {
      // Note-On (seq 0) then Note-Off (seq 1), but the Note-Off timestamp
      // regresses below the onset: FIFO still pairs, duration stays negative.
      final semantic = interpreter.interpret(norm([
        rawOn(sessionId: 's1', seq: 0, ts: 1500, pitch: 60, velocity: 90),
        rawOff(sessionId: 's1', seq: 1, ts: 1000, pitch: 60),
      ]));

      expect(semantic[0].type, MusicalSemanticType.noteLifecycle);
      expect(semantic[0].startTimestampMs, 1500);
      expect(semantic[0].endTimestampMs, 1000);
      expect(semantic[0].durationMs, -500);
      // The timestamp regression stays observable too.
      expect(semantic[1].type, MusicalSemanticType.integrityAnomaly);
      expect(semantic[1].anomalyCategory, 'timestamp_regression');
    });
  });

  group('immutability', () {
    test('interpretation never mutates raw or normalized events', () {
      final raw = <RawMidiEvent>[
        rawOn(sessionId: 's1', seq: 0, ts: 1000, pitch: 60, velocity: 100),
        rawOn(sessionId: 's1', seq: 1, ts: 1300, pitch: 60, velocity: 0),
        rawCc(sessionId: 's1', seq: 2, ts: 1500),
      ];
      final normalized = norm(raw);

      final beforeRaw = <(String, int, int, RawMidiMessageType, int?)>[
        for (final e in raw)
          (e.sessionId, e.seq, e.appMonotonicTsMs, e.messageType, e.velocity),
      ];
      final beforeNorm = <(NormalizedMidiMessageType, String)>[
        for (final e in normalized) (e.type, e.normalizationRule),
      ];
      final rawBytes = List<List<int>>.from(raw.map((e) => List<int>.from(e.rawBytes)));

      interpreter.interpret(normalized);

      for (var i = 0; i < raw.length; i++) {
        expect((raw[i].sessionId, raw[i].seq, raw[i].appMonotonicTsMs,
                raw[i].messageType, raw[i].velocity),
            equals(beforeRaw[i]));
        expect(raw[i].rawBytes, rawBytes[i]);
        expect((normalized[i].type, normalized[i].normalizationRule),
            beforeNorm[i]);
      }
      expect(identical(normalized[1].source, raw[1]), isTrue);
    });

    test('semantic sources are the exact caller-provided object instances', () {
      final normalized = norm([
        rawOn(sessionId: 's1', seq: 0, ts: 1000, pitch: 60, velocity: 90),
        rawOff(sessionId: 's1', seq: 1, ts: 2000, pitch: 60),
      ]);
      final semantic = interpreter.interpret(normalized);

      expect(identical(semantic.single.sourceOn!, normalized[0]), isTrue);
      expect(identical(semantic.single.sourceOff!, normalized[1]), isTrue);
    });

    test('semantic source lists are unmodifiable', () {
      final semantic = interpreter.interpret(norm([
        rawOn(sessionId: 's1', seq: 0, ts: 1000, pitch: 60, velocity: 90),
      ]));

      expect(() => semantic.single.sources.add(semantic.single.sources.first),
          throwsUnsupportedError);
      expect(() => semantic.single.sources.clear(), throwsUnsupportedError);
    });
  });

  group('determinism', () {
    test('same input interpreted twice yields an identical projection', () {
      final normalized = norm([
        rawOn(sessionId: 's1', seq: 0, ts: 1000, pitch: 60, velocity: 90),
        rawCc(sessionId: 's1', seq: 1, ts: 1234),
        rawOff(sessionId: 's1', seq: 2, ts: 2000, pitch: 60),
        rawOn(sessionId: 's2', seq: 0, ts: 50, pitch: 71, velocity: 80),
      ]);
      final normalized2 = norm([
        rawOn(sessionId: 's1', seq: 0, ts: 1000, pitch: 60, velocity: 90),
        rawCc(sessionId: 's1', seq: 1, ts: 1234),
        rawOff(sessionId: 's1', seq: 2, ts: 2000, pitch: 60),
        rawOn(sessionId: 's2', seq: 0, ts: 50, pitch: 71, velocity: 80),
      ]);

      // Two runs on the SAME objects and two runs on FRESH equal objects must
      // both project identically. Object identity is never relied upon.
      expect(_project(interpreter.interpret(normalized)),
          _project(interpreter.interpret(normalized)));
      expect(_project(interpreter.interpret(normalized)),
          _project(interpreter.interpret(normalized2)));
    });

    test('MusicalEvent value equality is stable across fresh instances', () {
      final a = interpreter.interpret(norm([
        rawOn(sessionId: 's1', seq: 0, ts: 1000, pitch: 60, velocity: 90),
        rawOff(sessionId: 's1', seq: 1, ts: 2000, pitch: 60),
      ])).single;
      final b = interpreter.interpret(norm([
        rawOn(sessionId: 's1', seq: 0, ts: 1000, pitch: 60, velocity: 90),
        rawOff(sessionId: 's1', seq: 1, ts: 2000, pitch: 60),
      ])).single;

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });

  group('reuse H2.3 JSONL fixtures end-to-end', () {
    test('f1 simple note replays to one lifecycle', () {
      const reader = JsonlRawMidiEventReader();
      final replay = reader.read(fixture('f1_simple_note'));
      final semantic = interpreter.interpret(normalizer.normalizeAll(replay.events));

      expect(semantic, hasLength(1));
      final event = semantic.single;
      expect(event.type, MusicalSemanticType.noteLifecycle);
      expect(event.pitch, 60);
      expect(event.durationMs, 500);
      expect(event.sourceOn!.source.appMonotonicTsMs, 1000);
      expect(event.sourceOff!.source.appMonotonicTsMs, 1500);
    });

    test('f2 velocity-zero replays the release side of one lifecycle', () {
      const reader = JsonlRawMidiEventReader();
      final replay = reader.read(fixture('f2_velocity_zero'));
      final normalized = normalizer.normalizeAll(replay.events);
      final semantic = interpreter.interpret(normalized);

      expect(replay.events[1].messageType, RawMidiMessageType.noteOn);
      expect(replay.events[1].velocity, 0);
      expect(normalized[1].type, NormalizedMidiMessageType.noteOff);
      expect(semantic, hasLength(1));
      expect(semantic.single.type, MusicalSemanticType.noteLifecycle);
      expect(semantic.single.endTimestampMs, 1300);
      expect(semantic.single.durationMs, 300);
      expect(identical(semantic.single.sourceOff, normalized[1]), isTrue);
    });

    test('f3 burst, f4 arpeggio, f5/f6 unmatched: attacks/releases only', () {
      const reader = JsonlRawMidiEventReader();
      for (final name in <String>['f3_three_note_burst', 'f4_arpeggiated']) {
        final semantic = interpreter
            .interpret(normalizer.normalizeAll(reader.read(fixture(name)).events));
        expect(semantic.map((e) => e.type).toSet(),
            <MusicalSemanticType>{MusicalSemanticType.noteAttack});
      }
      final f5 = reader.read(fixture('f5_unmatched_note_on'));
      expect(
          interpreter
              .interpret(normalizer.normalizeAll(f5.events))
              .single
              .type,
          MusicalSemanticType.noteAttack);
      final f6 = reader.read(fixture('f6_unmatched_note_off'));
      expect(
          interpreter
              .interpret(normalizer.normalizeAll(f6.events))
              .single
              .type,
          MusicalSemanticType.noteRelease);
    });

    test('f7/f8/f9/f10 replay semantics match the pure-interpretation rules', () {
      const reader = JsonlRawMidiEventReader();
      String project(String name) => _project(interpreter.interpret(
          normalizer.normalizeAll(reader.read(fixture(name)).events)));

      // Stable cross-run determinism on replayed fixtures too.
      expect(project('f7_multiple_sessions'), project('f7_multiple_sessions'));
      expect(project('f10_integrity_anomaly'), project('f10_integrity_anomaly'));

      final f8 = interpreter.interpret(
          normalizer.normalizeAll(reader.read(fixture('f8_non_note_midi')).events));
      expect(f8.map((e) => e.type), <MusicalSemanticType>[
        MusicalSemanticType.nonNote,
        MusicalSemanticType.noteLifecycle,
      ]);

      final f9 = interpreter.interpret(
          normalizer.normalizeAll(reader.read(fixture('f9_duplicate_candidate')).events));
      expect(f9.map((e) => e.type), <MusicalSemanticType>[
        MusicalSemanticType.noteAttack,
        MusicalSemanticType.noteAttack,
      ]);

      final f10 = interpreter.interpret(
          normalizer.normalizeAll(reader.read(fixture('f10_integrity_anomaly')).events));
      final f10Anomalies = f10
          .where((e) => e.type == MusicalSemanticType.integrityAnomaly)
          .toList();
      expect(f10Anomalies, hasLength(3));
      expect(f10Anomalies.map((e) => e.anomalyCategory), <String>[
        'sequence_regression',
        'timestamp_regression',
        'duplicate_sequence',
      ]);
    });
  });
}

/// Stable scalar projection of a semantic stream for determinism checks.
///
/// Compares only observed scalar fields plus stable source identifiers
/// (session, sequence, raw status, normalization rule) - never object identity.
String _project(List<MusicalEvent> events) {
  final b = StringBuffer();
  for (final e in events) {
    final sources = e.sources
        .map((s) =>
            '${s.sessionId}/${s.sourceSeq}/${s.rawStatus}/'
            '${s.normalizationRule}/${s.type.name}')
        .join('|');
    b.writeln(
        'idx=${e.eventIndex} type=${e.type.name} sess=${e.sessionId} '
        'start=${e.startTimestampMs} end=${e.endTimestampMs} '
        'ch=${e.channel} pitch=${e.pitch} vel=${e.velocity} '
        'dur=${e.durationMs} anomaly=${e.anomalyCategory} sources=[$sources]');
  }
  return b.toString();
}