import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/midi/application/midi_normalizer.dart';
import 'package:miditutor/midi/domain/normalized_midi_event.dart';
import 'package:miditutor/midi/domain/raw_midi_event.dart';
import 'package:miditutor/midi/diagnostics/duplicate_candidate_detector.dart';
import 'package:miditutor/midi/diagnostics/monotonicity_analyzer.dart';

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
    rawBytes: rawBytes ?? <int>[0x90, note ?? 60, velocity ?? 100],
  );
}

void main() {
  const normalizer = MidiNormalizer();

  List<NormalizedMidiEvent> norm(List<RawMidiEvent> raw) =>
      normalizer.normalizeAll(raw);

  group('DuplicateCandidateDetector', () {
    test('N11: same pitch + same channel + delta <5 ms is a candidate', () {
      const detector = DuplicateCandidateDetector(thresholdMs: 5);
      final candidates = detector.detect(norm(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 1003, note: 60),
      ]));

      expect(candidates, hasLength(1));
      expect(candidates.single.first.sourceSeq, 0);
      expect(candidates.single.second.sourceSeq, 1);
      expect(candidates.single.deltaMs, 3);
    });

    test('N11: candidate events are preserved, never deleted or merged', () {
      const detector = DuplicateCandidateDetector(thresholdMs: 5);
      final input = <RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 1002, note: 60),
      ];
      final events = norm(input);
      final candidates = detector.detect(events);

      expect(candidates, hasLength(1));
      expect(events, hasLength(2));
      expect(events[0].sourceSeq, 0);
      expect(events[1].sourceSeq, 1);
    });

    test('delta exactly at threshold is NOT a candidate', () {
      const detector = DuplicateCandidateDetector(thresholdMs: 5);
      final candidates = detector.detect(norm(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 1005, note: 60),
      ]));

      expect(candidates, isEmpty);
    });

    test('different pitches are not duplicates', () {
      const detector = DuplicateCandidateDetector(thresholdMs: 5);
      final candidates = detector.detect(norm(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 1001, note: 64),
      ]));

      expect(candidates, isEmpty);
    });

    test('different channels are not duplicates', () {
      const detector = DuplicateCandidateDetector(thresholdMs: 5);
      final candidates = detector.detect(norm(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, channel: 0, note: 60),
        raw(seq: 1, ts: 1001, channel: 1, note: 60),
      ]));

      expect(candidates, isEmpty);
    });

    test('a legitimate fast Note-On/Note-Off of the same pitch is not a candidate', () {
      const detector = DuplicateCandidateDetector(thresholdMs: 5);
      final candidates = detector.detect(norm(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 1001, messageType: 'note_off', note: 60, rawBytes: <int>[0x80, 60, 0]),
      ]));

      expect(candidates, isEmpty);
    });
  });

  group('MonotonicityAnalyzer', () {
    test('N13: sequence regression is reported, not repaired', () {
      const analyzer = MonotonicityAnalyzer();
      final report = analyzer.analyze(norm(<RawMidiEvent>[
        raw(seq: 5, ts: 1000, note: 60),
        raw(seq: 3, ts: 1005, note: 64),
        raw(seq: 4, ts: 1010, note: 67),
      ]));

      expect(report.sequenceRegressionCount, 1);
      expect(report.sequenceRegressions.single.sourceSeq, 3);
      expect(report.duplicateSequenceIds, isEmpty);
    });

    test('N12: timestamp regression is reported, not repaired', () {
      const analyzer = MonotonicityAnalyzer();
      final report = analyzer.analyze(norm(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 999, note: 64),
      ]));

      expect(report.timestampRegressionCount, 1);
      expect(report.timestampRegressions.single.sourceSeq, 1);
    });

    test('duplicate sequence ids are reported', () {
      const analyzer = MonotonicityAnalyzer();
      final report = analyzer.analyze(norm(<RawMidiEvent>[
        raw(seq: 2, ts: 1000, note: 60),
        raw(seq: 2, ts: 1005, note: 64),
        raw(seq: 3, ts: 1010, note: 67),
      ]));

      expect(report.duplicateSequenceIds, <int>{2});
      expect(report.sequenceRegressionCount, 0);
    });

    test('clean monotonic input has no anomalies', () {
      const analyzer = MonotonicityAnalyzer();
      final report = analyzer.analyze(norm(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 1050, note: 64),
        raw(seq: 2, ts: 1100, note: 67),
      ]));

      expect(report.sequenceRegressionCount, 0);
      expect(report.timestampRegressionCount, 0);
      expect(report.duplicateSequenceIds, isEmpty);
    });
  });
}