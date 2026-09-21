import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/midi/application/midi_normalizer.dart';
import 'package:miditutor/midi/domain/normalized_midi_event.dart';
import 'package:miditutor/midi/domain/raw_midi_event.dart';
import 'package:miditutor/midi/diagnostics/note_pairing_analyzer.dart';

RawMidiEvent raw({
  String sessionId = 'abc',
  int seq = 1,
  int ts = 1000,
  String messageType = 'note_on',
  int? channel = 0,
  int? note,
  int? velocity,
  List<int>? rawBytes,
}) {
  return RawMidiEvent(
    sessionId: sessionId,
    deviceId: '123456',
    connectionType: 'USB',
    seq: seq,
    appMonotonicTsMs: ts,
    messageType: switch (messageType) {
      'note_on' => RawMidiMessageType.noteOn,
      'note_off' => RawMidiMessageType.noteOff,
      _ => RawMidiMessageType.other,
    },
    channel: channel,
    note: note,
    velocity: velocity,
    rawBytes: rawBytes ??
        switch (messageType) {
          'note_off' => <int>[0x80, note ?? 60, velocity ?? 0],
          _ => <int>[0x90, note ?? 60, velocity ?? 100],
        },
  );
}

void main() {
  const normalizer = MidiNormalizer();
  const analyzer = NotePairingAnalyzer();

  List<NormalizedMidiEvent> norm(List<RawMidiEvent> raw) =>
      normalizer.normalizeAll(raw);

  group('NotePairingAnalyzer', () {
    test('N6: repeated same pitch with separate Note-On/Note-Off cycles', () {
      final report = analyzer.analyze(norm(<RawMidiEvent>[
        raw(seq: 0, note: 60), raw(seq: 1, messageType: 'note_off', note: 60),
        raw(seq: 2, note: 60), raw(seq: 3, messageType: 'note_off', note: 60),
      ]));

      expect(report.matchedPairCount, 2);
      expect(report.unmatchedNoteOffCount, 0);
      expect(report.activeNoteOnCount, 0);
      expect(report.matchedPairsPerIdentity[('abc', 0, 60)], 2);
    });

    test('N7: overlapping same pitch/channel Note-Ons are multiple active instances', () {
      final report = analyzer.analyze(norm(<RawMidiEvent>[
        raw(seq: 0, note: 60),
        raw(seq: 1, note: 60),
        raw(seq: 2, messageType: 'note_off', note: 60),
        raw(seq: 3, messageType: 'note_off', note: 60),
      ]));

      expect(report.matchedPairCount, 2);
      expect(report.activeNoteOnCount, 0);
      expect(report.maxActivePerIdentity[('abc', 0, 60)], 2);
    });

    test('N8: unmatched Note-On is reported as a still-active instance', () {
      final report = analyzer.analyze(norm(<RawMidiEvent>[
        raw(seq: 0, note: 60),
        raw(seq: 1, note: 64),
        raw(seq: 2, messageType: 'note_off', note: 64),
      ]));

      expect(report.activeNoteOnCount, 1);
      expect(report.activeNoteOns.single.pitch, 60);
      expect(report.matchedPairCount, 1);
      expect(report.maxActivePerIdentity[('abc', 0, 60)], 1);
    });

    test('N9: unmatched Note-Off is reported', () {
      final report = analyzer.analyze(norm(<RawMidiEvent>[
        raw(seq: 0, messageType: 'note_off', note: 60),
        raw(seq: 1, messageType: 'note_off', note: 64),
      ]));

      expect(report.unmatchedNoteOffCount, 2);
      expect(report.matchedPairCount, 0);
      final pitches = report.unmatchedNoteOffs.map((e) => e.pitch).toList()..sort();
      expect(pitches, <int?>[60, 64]);
    });

    test('N10: session boundary prevents cross-session pairing', () {
      final report = analyzer.analyze(norm(<RawMidiEvent>[
        raw(sessionId: 'session_a', seq: 0, note: 60),
        raw(sessionId: 'session_a', seq: 1, note: 64),
        raw(sessionId: 'session_b', seq: 0, messageType: 'note_off', note: 60),
      ]));

      expect(report.matchedPairCount, 0);
      expect(report.activeNoteOnCount, 2);
      expect(report.unmatchedNoteOffCount, 1);
      expect(report.unmatchedNoteOffs.single.sessionId, 'session_b');
    });

    test('non-note channel events are ignored for pairing', () {
      final report = analyzer.analyze(norm(<RawMidiEvent>[
        raw(seq: 0, messageType: 'other', channel: 0, note: null, velocity: null, rawBytes: <int>[0xB0, 48, 1]),
        raw(seq: 1, note: 60),
        raw(seq: 2, messageType: 'note_off', note: 60),
      ]));

      expect(report.matchedPairCount, 1);
      expect(report.unmatchedNoteOffCount, 0);
      expect(report.activeNoteOnCount, 0);
    });
  });

  group('Note pairs (durations)', () {
    test('pair exposes the exact paired events and a 500 ms duration', () {
      final report = analyzer.analyze(norm(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 1500, messageType: 'note_off', note: 60),
      ]));

      expect(report.pairs, hasLength(1));
      expect(report.pairs.single.noteOn.sourceSeq, 0);
      expect(report.pairs.single.noteOff.sourceSeq, 1);
      expect(report.pairs.single.durationMs, 500);
    });

    test('a 0 ms duration pair is reported exactly', () {
      final report = analyzer.analyze(norm(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 1000, messageType: 'note_off', note: 60),
      ]));

      expect(report.pairs.single.durationMs, 0);
    });

    test('overlapping same-pitch instances pair FIFO with correct durations', () {
      final report = analyzer.analyze(norm(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60), // on A
        raw(seq: 1, ts: 1100, note: 60), // on B
        raw(seq: 2, ts: 1200, messageType: 'note_off', note: 60), // off -> A
        raw(seq: 3, ts: 1300, messageType: 'note_off', note: 60), // off -> B
      ]));

      expect(report.pairs, hasLength(2));
      expect(report.pairs[0].noteOn.sourceSeq, 0);
      expect(report.pairs[0].noteOff.sourceSeq, 2);
      expect(report.pairs[0].durationMs, 200);
      expect(report.pairs[1].noteOn.sourceSeq, 1);
      expect(report.pairs[1].noteOff.sourceSeq, 3);
      expect(report.pairs[1].durationMs, 200);
    });

    test('negative duration is preserved, not clamped', () {
      final report = analyzer.analyze(norm(<RawMidiEvent>[
        raw(seq: 0, ts: 2000, note: 60),
        raw(seq: 1, ts: 1000, messageType: 'note_off', note: 60),
      ]));

      expect(report.pairs.single.durationMs, -1000);
    });
  });
}