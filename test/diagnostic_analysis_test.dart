import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/midi/application/midi_normalizer.dart';
import 'package:miditutor/midi/domain/normalized_midi_event.dart';
import 'package:miditutor/midi/domain/raw_midi_event.dart';
import 'package:miditutor/midi/diagnostics/diagnostic_analysis.dart';

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
    velocity: velocity ?? (messageType == 'note_off' ? 0 : 100),
    rawBytes: rawBytes ??
        switch (messageType) {
          'note_off' => <int>[0x80, note ?? 60, velocity ?? 0],
          _ => <int>[0x90, note ?? 60, velocity ?? 100],
        },
  );
}

void main() {
  const normalizer = MidiNormalizer();
  const analyzer = DiagnosticAnalyzer();
  const config = DiagnosticConfig();

  List<NormalizedMidiEvent> norm(List<RawMidiEvent> raw) =>
      normalizer.normalizeAll(raw);

  DiagnosticAnalysisReport analyze(
      List<RawMidiEvent> input, [DiagnosticConfig? cfg]) {
    return analyzer.analyze(norm(input), cfg ?? config);
  }

  group('Note-On / Note-Off timelines', () {
    test('note-on timeline preserves capture order with ordinals', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 1100, note: 64),
        raw(seq: 2, ts: 1500, messageType: 'note_off', note: 60),
        raw(seq: 3, ts: 1600, messageType: 'note_off', note: 64),
      ]);

      expect(report.noteOnTimeline, hasLength(2));
      final first = report.noteOnTimeline[0];
      expect(first.sourceSeq, 0);
      expect(first.timestampMs, 1000);
      expect(first.sessionId, 'abc');
      expect(first.channel, 0);
      expect(first.pitch, 60);
      expect(first.velocity, 100);
      expect(first.ordinal, 0);
      expect(report.noteOnTimeline[1].sourceSeq, 1);
      expect(report.noteOnTimeline[1].ordinal, 1);
    });

    test('note-off timeline preserves capture order with ordinals', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 1500, messageType: 'note_off', note: 60),
        raw(seq: 2, ts: 1510, messageType: 'note_off', note: 64),
      ]);

      expect(report.noteOffTimeline, hasLength(2));
      expect(report.noteOffTimeline[0].sourceSeq, 1);
      expect(report.noteOffTimeline[0].ordinal, 0);
      expect(report.noteOffTimeline[1].sourceSeq, 2);
      expect(report.noteOffTimeline[1].ordinal, 1);
      expect(report.noteOffTimeline[1].pitch, 64);
    });

    test('velocity-zero Note-On is derived to Note-Off by H2.1 and lands in '
        'the note-off timeline only', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, messageType: 'note_on', note: 60, velocity: 0),
      ]);

      expect(report.noteOnTimeline, isEmpty);
      expect(report.noteOffTimeline, hasLength(1));
      expect(report.noteOffTimeline.single.pitch, 60);
      expect(report.noteOffTimeline.single.velocity, 0);
      expect(report.noteOffTimeline.single.ordinal, 0);
    });
  });

  group('Note duration diagnostics', () {
    test('a 500 ms pair is reported with exact stats', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 1500, messageType: 'note_off', note: 60),
      ]);

      expect(report.noteDurations.count, 1);
      expect(report.noteDurations.minMs, 500);
      expect(report.noteDurations.maxMs, 500);
      expect(report.noteDurations.meanMs, 500);
      expect(report.noteDurations.medianMs, 500);
      expect(report.noteDurations.p95Ms, 500);
      expect(report.integrity.negativeDurationCount, 0);
    });

    test('a 0 ms pair is reported exactly', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 1000, messageType: 'note_off', note: 60),
      ]);

      expect(report.noteDurations.count, 1);
      expect(report.noteDurations.minMs, 0);
      expect(report.noteDurations.maxMs, 0);
    });

    test('multi-pair median and p95 are computed over sorted durations', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 1500, messageType: 'note_off', note: 60),
        raw(seq: 2, ts: 2000, note: 64),
        raw(seq: 3, ts: 2300, messageType: 'note_off', note: 64),
        raw(seq: 4, ts: 2600, note: 67),
        raw(seq: 5, ts: 3000, messageType: 'note_off', note: 67),
        raw(seq: 6, ts: 3100, note: 72),
        raw(seq: 7, ts: 3400, messageType: 'note_off', note: 72),
      ]);

      // durations: 500, 300, 400, 300
      expect(report.noteDurations.count, 4);
      expect(report.noteDurations.minMs, 300);
      expect(report.noteDurations.maxMs, 500);
      expect(report.noteDurations.meanMs, 375);
      expect(report.noteDurations.medianMs, 350);
    });

    test('unmatched Note-On has no fabricated duration', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
      ]);

      expect(report.noteDurations.count, 0);
      expect(report.noteDurations.minMs, isNull);
      expect(report.integrity.unmatchedNoteOnCount, 1);
    });

    test('unmatched Note-Off has no fabricated duration', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, messageType: 'note_off', note: 60),
      ]);

      expect(report.noteDurations.count, 0);
      expect(report.integrity.unmatchedNoteOffCount, 1);
    });

    test('negative duration is preserved and reported as an integrity anomaly', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 2000, note: 60),
        raw(seq: 1, ts: 1000, messageType: 'note_off', note: 60),
      ]);

      expect(report.noteDurations.count, 1);
      expect(report.noteDurations.minMs, -1000);
      expect(report.noteDurations.maxMs, -1000);
      expect(report.integrity.negativeDurationCount, 1);
    });
  });

  group('Inter-onset interval (IOI) diagnostics', () {
    test('normal IOIs are summarized', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 1050, note: 64),
        raw(seq: 2, ts: 1100, note: 67),
      ]);

      expect(report.ioI.count, 2);
      expect(report.ioI.minMs, 50);
      expect(report.ioI.maxMs, 50);
      expect(report.ioI.meanMs, 50);
      expect(report.ioI.medianMs, 50);
      expect(report.ioI.zeroDeltaCount, 0);
    });

    test('zero-delta IOIs are counted', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 1000, note: 64),
      ]);

      expect(report.ioI.count, 1);
      expect(report.ioI.minMs, 0);
      expect(report.ioI.zeroDeltaCount, 1);
    });

    test('IOIs are never computed across session boundaries', () {
      final report = analyze(<RawMidiEvent>[
        raw(sessionId: 'a', seq: 0, ts: 1000, note: 60),
        raw(sessionId: 'b', seq: 0, ts: 100, note: 60),
        raw(sessionId: 'a', seq: 1, ts: 2000, note: 64),
        raw(sessionId: 'b', seq: 1, ts: 200, note: 64),
      ]);

      // a: [1000], b: [100] -> 2 IOIs. A cross-session collapse would give 3.
      expect(report.ioI.count, 2);
      expect(report.ioI.minMs, 100);
      expect(report.ioI.maxMs, 1000);
      expect(report.ioI.meanMs, 550);
    });

    test('timestamp regression is reflected verbatim (negative delta), '
        'not smoothed or repaired', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 900, note: 64),
      ]);

      expect(report.ioI.count, 1);
      expect(report.ioI.minMs, -100);
      expect(report.ioI.maxMs, -100);
      expect(report.integrity.timestampRegressionCount, 1);
    });

    test('a single Note-On yields a valid empty IOI report', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
      ]);

      expect(report.ioI.count, 0);
      expect(report.ioI.minMs, isNull);
      expect(report.ioI.maxMs, isNull);
      expect(report.ioI.zeroDeltaCount, 0);
    });

    test('no Note-On events yields a valid empty IOI report', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, messageType: 'note_off', note: 60),
        raw(seq: 1, ts: 2000, messageType: 'other', note: null, velocity: null, rawBytes: <int>[0xB0, 48, 1]),
      ]);

      expect(report.ioI.count, 0);
      expect(report.ioI.zeroDeltaCount, 0);
    });
  });

  group('Velocity diagnostics', () {
    test('a single Note-On gives a one-value summary', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60, velocity: 90),
      ]);

      expect(report.velocity.count, 1);
      expect(report.velocity.min, 90);
      expect(report.velocity.max, 90);
      expect(report.velocity.mean, 90);
      expect(report.velocity.median, 90);
      expect(report.velocity.stdDev, 0);
    });

    test('velocity 1 and 127 are described, not classified', () {
      final low = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60, velocity: 1),
      ]);
      expect(low.velocity.count, 1);
      expect(low.velocity.min, 1);
      expect(low.velocity.max, 1);

      final high = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60, velocity: 127),
      ]);
      expect(high.velocity.count, 1);
      expect(high.velocity.min, 127);
      expect(high.velocity.max, 127);
    });

    test('multiple velocities produce min/max/mean/median/stdDev', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60, velocity: 50),
        raw(seq: 1, ts: 1100, note: 64, velocity: 60),
        raw(seq: 2, ts: 1200, note: 67, velocity: 100),
      ]);

      // [50, 60, 100]: mean 70; population stdDev sqrt(1400/3).
      expect(report.velocity.count, 3);
      expect(report.velocity.min, 50);
      expect(report.velocity.max, 100);
      expect(report.velocity.mean, 70);
      expect(report.velocity.median, 60);
      expect(report.velocity.stdDev, closeTo(21.602, 0.001));
    });

    test('no Note-On events yields a valid empty velocity report', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, messageType: 'note_off', note: 60),
      ]);

      expect(report.velocity.count, 0);
      expect(report.velocity.min, isNull);
      expect(report.velocity.max, isNull);
    });

    test('velocity-zero Note-On (H2.1-derived Note-Off) is excluded', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, messageType: 'note_on', note: 60, velocity: 0),
        raw(seq: 1, ts: 1100, note: 64, velocity: 100),
      ]);

      expect(report.velocity.count, 1);
      expect(report.velocity.min, 100);
      expect(report.velocity.max, 100);
    });
  });

  group('Temporal bursts', () {
    test('59 ms difference stays in the same burst', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 1059, note: 64),
      ]);

      expect(report.temporalBursts, hasLength(1));
      expect(report.temporalBursts.single.eventCount, 2);
      expect(report.temporalBursts.single.burstId, 1);
      expect(report.temporalBursts.single.spreadMs, 59);
    });

    test('60 ms difference (exactly at threshold) stays in the same burst', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 1060, note: 64),
      ]);

      expect(report.temporalBursts, hasLength(1));
      expect(report.temporalBursts.single.eventCount, 2);
      expect(report.temporalBursts.single.spreadMs, 60);
    });

    test('61 ms difference starts a new burst', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 1061, note: 64),
      ]);

      expect(report.temporalBursts, hasLength(2));
      expect(report.temporalBursts[0].burstId, 1);
      expect(report.temporalBursts[0].eventCount, 1);
      expect(report.temporalBursts[1].burstId, 2);
      expect(report.temporalBursts[1].eventCount, 1);
    });

    test('burst fields expose spread, pitches, channels, source sequences', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 1010, note: 64, channel: 1),
        raw(seq: 2, ts: 1030, note: 67),
      ]);

      final burst = report.temporalBursts.single;
      expect(burst.sessionId, 'abc');
      expect(burst.firstTimestampMs, 1000);
      expect(burst.lastTimestampMs, 1030);
      expect(burst.spreadMs, 30);
      expect(burst.eventCount, 3);
      expect(burst.pitches, <int>[60, 64, 67]);
      expect(burst.channels, <int>[0, 1]);
      expect(burst.sourceSequences, <int>[0, 1, 2]);
    });

    test('bursts never span sessions', () {
      final report = analyze(<RawMidiEvent>[
        raw(sessionId: 'a', seq: 0, ts: 1000, note: 60),
        raw(sessionId: 'a', seq: 1, ts: 1050, note: 64),
        raw(sessionId: 'b', seq: 0, ts: 1000, note: 60),
        raw(sessionId: 'b', seq: 1, ts: 1050, note: 64),
      ]);

      expect(report.temporalBursts, hasLength(2));
      expect(report.temporalBursts.map((b) => b.sessionId).toSet(), {'a', 'b'});
      for (final burst in report.temporalBursts) {
        expect(burst.eventCount, 2);
        expect(burst.sourceSequences, <int>[0, 1]);
      }
    });

    test('no Note-On events yields no bursts', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, messageType: 'note_off', note: 60),
      ]);

      expect(report.temporalBursts, isEmpty);
    });
  });

  group('Gap diagnostics', () {
    test('no threshold supplied means no interval is classified as a gap', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 60000, note: 64),
      ]);

      expect(report.gapDiagnostics, isEmpty);
    });

    test('configured threshold flags only intervals strictly above it', () {
      final cfg = const DiagnosticConfig(gapThresholdMs: 100);
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 1100, note: 64), // 100 ms -> not a gap
        raw(seq: 2, ts: 1201, note: 67), // 101 ms -> gap
      ], cfg);

      expect(report.gapDiagnostics, hasLength(1));
      final gap = report.gapDiagnostics.single;
      expect(gap.previousSourceSeq, 1);
      expect(gap.nextSourceSeq, 2);
      expect(gap.previousTimestampMs, 1100);
      expect(gap.nextTimestampMs, 1201);
      expect(gap.gapMs, 101);
      expect(gap.sessionId, 'abc');
      expect(gap.channelContext, 0);
    });

    test('gaps are computed within sessions only', () {
      const cfg = DiagnosticConfig(gapThresholdMs: 1000);
      final report = analyze(<RawMidiEvent>[
        raw(sessionId: 'a', seq: 0, ts: 1000, note: 60),
        raw(sessionId: 'b', seq: 0, ts: 5000, note: 60),
        raw(sessionId: 'a', seq: 1, ts: 1100, note: 64),
        raw(sessionId: 'b', seq: 1, ts: 9000, note: 64),
      ], cfg);

      // a: single interval 100 ms -> no gap. b: 4000 ms -> 1 gap.
      expect(report.gapDiagnostics, hasLength(1));
      expect(report.gapDiagnostics.single.sessionId, 'b');
      expect(report.gapDiagnostics.single.gapMs, 4000);
    });
  });

  group('Per-pitch diagnostics', () {
    test('counts, pairing and durations per pitch', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 1500, messageType: 'note_off', note: 60),
        raw(seq: 2, ts: 1600, note: 64),
      ]);

      expect(report.pitchSummaries.map((p) => p.pitch), <int>[60, 64]);

      final c4 = report.pitchSummaries.singleWhere((p) => p.pitch == 60);
      expect(c4.noteOnCount, 1);
      expect(c4.noteOffCount, 1);
      expect(c4.pairedCount, 1);
      expect(c4.unmatchedNoteOnCount, 0);
      expect(c4.unmatchedNoteOffCount, 0);
      expect(c4.minDurationMs, 500);
      expect(c4.maxDurationMs, 500);
      expect(c4.meanDurationMs, 500);

      final e4 = report.pitchSummaries.singleWhere((p) => p.pitch == 64);
      expect(e4.noteOnCount, 1);
      expect(e4.noteOffCount, 0);
      expect(e4.pairedCount, 0);
      expect(e4.unmatchedNoteOnCount, 1);
      expect(e4.minDurationMs, isNull);
      expect(e4.maxDurationMs, isNull);
      expect(e4.meanDurationMs, isNull);
    });

    test('pitches are ordered ascending', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 67),
        raw(seq: 1, ts: 1010, note: 60),
        raw(seq: 2, ts: 1020, note: 64),
      ]);

      expect(report.pitchSummaries.map((p) => p.pitch), <int>[60, 64, 67]);
    });
  });

  group('Per-channel diagnostics', () {
    test('totals, note counts, other count and unique pitch count', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, channel: 0, note: 60),
        raw(seq: 1, ts: 1500, channel: 0, messageType: 'note_off', note: 60),
        raw(seq: 2, ts: 1600, channel: 0, messageType: 'other', note: null, velocity: null, rawBytes: <int>[0xB0, 48, 1]),
        raw(seq: 3, ts: 1700, channel: 1, note: 64),
        raw(seq: 4, ts: 1800, channel: null, messageType: 'other', note: null, velocity: null, rawBytes: <int>[0xE0, 0, 32]),
      ]);

      expect(report.channelSummaries.map((c) => c.channel), <int>[0, 1]);

      final ch0 = report.channelSummaries.singleWhere((c) => c.channel == 0);
      expect(ch0.totalEvents, 3);
      expect(ch0.noteOnCount, 1);
      expect(ch0.noteOffCount, 1);
      expect(ch0.otherCount, 1);
      expect(ch0.uniquePitchCount, 1);

      final ch1 = report.channelSummaries.singleWhere((c) => c.channel == 1);
      expect(ch1.totalEvents, 1);
      expect(ch1.noteOnCount, 1);
      expect(ch1.uniquePitchCount, 1);
      expect(ch1.otherCount, 0);
    });
  });

  group('Session summaries', () {
    test('a single session is summarized', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 1010, note: 64),
        raw(seq: 2, ts: 1200, messageType: 'note_off', note: 60),
        raw(seq: 3, ts: 1210, messageType: 'note_off', note: 64),
        raw(seq: 4, ts: 1300, messageType: 'other', note: null, velocity: null, rawBytes: <int>[0xB0, 48, 1]),
      ]);

      expect(report.sessionSummaries, hasLength(1));
      final s = report.sessionSummaries.single;
      expect(s.sessionId, 'abc');
      expect(s.firstTimestampMs, 1000);
      expect(s.lastTimestampMs, 1300);
      expect(s.sessionSpanMs, 300);
      expect(s.totalEvents, 5);
      expect(s.noteOnCount, 2);
      expect(s.noteOffCount, 2);
      expect(s.otherCount, 1);
      expect(s.uniqueChannels, <int>[0]);
      expect(s.uniquePitches, <int>[60, 64]);
      expect(s.largestIoiMs, 10);
      expect(s.largestBurstSpreadMs, 10);
      expect(s.integrityAnomalyCount, 0);
    });

    test('sessions are ordered by first appearance', () {
      final report = analyze(<RawMidiEvent>[
        raw(sessionId: 'a', seq: 0, ts: 1000, note: 60),
        raw(sessionId: 'b', seq: 0, ts: 2000, note: 60),
        raw(sessionId: 'a', seq: 1, ts: 1200, note: 64),
      ]);

      expect(report.sessionSummaries.map((s) => s.sessionId), <String>['a', 'b']);
    });

    test('empty input produces a valid empty report', () {
      final report = analyze(<RawMidiEvent>[]);

      expect(report.sessionSummaries, isEmpty);
      expect(report.noteOnTimeline, isEmpty);
      expect(report.noteOffTimeline, isEmpty);
      expect(report.temporalBursts, isEmpty);
      expect(report.gapDiagnostics, isEmpty);
      expect(report.duplicateCandidates, isEmpty);
      expect(report.pitchSummaries, isEmpty);
      expect(report.channelSummaries, isEmpty);
      expect(report.noteDurations.count, 0);
      expect(report.ioI.count, 0);
      expect(report.velocity.count, 0);
      expect(report.integrity.sequenceRegressionCount, 0);
      expect(report.integrity.crossSessionPairingCount, 0);
    });

    test('same pitch across sessions is kept per-session, never paired or '
        'timed across sessions', () {
      final report = analyze(<RawMidiEvent>[
        raw(sessionId: 'a', seq: 0, ts: 1000, note: 60),
        raw(sessionId: 'a', seq: 1, ts: 1500, messageType: 'note_off', note: 60),
        raw(sessionId: 'b', seq: 0, ts: 100, note: 60),
        raw(sessionId: 'b', seq: 1, ts: 600, messageType: 'note_off', note: 60),
      ]);

      expect(report.noteDurations.count, 2);
      expect(report.noteDurations.minMs, 500);
      expect(report.noteDurations.maxMs, 500);
      expect(report.ioI.count, 0);
      expect(report.integrity.crossSessionPairingCount, 0);
      final c4 = report.pitchSummaries.singleWhere((p) => p.pitch == 60);
      expect(c4.pairedCount, 2);
    });

    test('timestamps resetting between sessions produce no cross-session '
        'temporal calculation', () {
      final report = analyze(<RawMidiEvent>[
        raw(sessionId: 'a', seq: 0, ts: 100, note: 60),
        raw(sessionId: 'b', seq: 0, ts: 5000, note: 60),
        raw(sessionId: 'a', seq: 1, ts: 140, note: 64),
      ]);

      expect(report.ioI.count, 1);
      expect(report.ioI.minMs, 40);
      expect(report.ioI.maxMs, 40);
    });
  });

  group('Integrity summary', () {
    test('clean normal sequence reports zeros and no cross-session pairing', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 1500, messageType: 'note_off', note: 60),
      ]);

      expect(report.integrity.sequenceRegressionCount, 0);
      expect(report.integrity.duplicateSequenceCount, 0);
      expect(report.integrity.timestampRegressionCount, 0);
      expect(report.integrity.unsupportedCount, 0);
      expect(report.integrity.unmatchedNoteOnCount, 0);
      expect(report.integrity.unmatchedNoteOffCount, 0);
      expect(report.integrity.negativeDurationCount, 0);
      expect(report.integrity.crossSessionPairingCount, 0);
    });

    test('sequence regression is counted, not repaired', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 5, ts: 1000, note: 60),
        raw(seq: 3, ts: 1005, note: 64),
      ]);

      expect(report.integrity.sequenceRegressionCount, 1);
      expect(report.noteOnTimeline, hasLength(2));
      expect(report.noteOnTimeline[0].sourceSeq, 5);
      expect(report.noteOnTimeline[1].sourceSeq, 3);
    });

    test('duplicate sequences are counted', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 2, ts: 1000, note: 60),
        raw(seq: 2, ts: 1005, note: 64),
      ]);

      expect(report.integrity.duplicateSequenceCount, 1);
    });

    test('timestamp regression is counted', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 999, note: 64),
      ]);

      expect(report.integrity.timestampRegressionCount, 1);
    });

    test('unmatched Note-On and unmatched Note-Off are counted', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 1500, messageType: 'note_off', note: 64),
      ]);

      expect(report.integrity.unmatchedNoteOnCount, 1);
      expect(report.integrity.unmatchedNoteOffCount, 1);
    });

    test('negative duration is counted as an integrity anomaly', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 2000, note: 60),
        raw(seq: 1, ts: 1000, messageType: 'note_off', note: 60),
      ]);

      expect(report.integrity.negativeDurationCount, 1);
      expect(report.noteDurations.minMs, -1000);
    });

    test('cross-session note boundaries produce unmatched events, never a '
        'cross-session pair', () {
      final report = analyze(<RawMidiEvent>[
        raw(sessionId: 'a', seq: 0, ts: 1000, note: 60),
        raw(sessionId: 'b', seq: 0, ts: 1500, messageType: 'note_off', note: 60),
      ]);

      expect(report.integrity.crossSessionPairingCount, 0);
      expect(report.integrity.unmatchedNoteOnCount, 1);
      expect(report.integrity.unmatchedNoteOffCount, 1);
      expect(report.noteDurations.count, 0);

      final sessionA =
          report.sessionSummaries.singleWhere((s) => s.sessionId == 'a');
      final sessionB =
          report.sessionSummaries.singleWhere((s) => s.sessionId == 'b');
      expect(sessionA.integrityAnomalyCount, 1);
      expect(sessionB.integrityAnomalyCount, 1);
    });

    test('unsupported events are counted, raw capture unchanged', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, messageType: 'other', note: null, velocity: null, rawBytes: <int>[0xB0, 48, 1]),
        raw(seq: 1, ts: 1005, note: 60),
      ]);

      expect(report.integrity.unsupportedCount, 1);
      expect(report.integrity.crossSessionPairingCount, 0);
    });
  });

  group('Duplicate candidates', () {
    test('reuses the H2.1 detector with the configured threshold and retains '
        'the threshold', () {
      const cfg = DiagnosticConfig(duplicateThresholdMs: 5);
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 1003, note: 60),
      ], cfg);

      expect(report.duplicateCandidates, hasLength(1));
      final candidate = report.duplicateCandidates.single;
      expect(candidate.first.sourceSeq, 0);
      expect(candidate.second.sourceSeq, 1);
      expect(candidate.deltaMs, 3);
      expect(candidate.thresholdMs, 5);
      // Retained, never removed.
      expect(report.noteOnTimeline, hasLength(2));
    });

    test('candidates respect the configured threshold', () {
      const cfg = DiagnosticConfig(duplicateThresholdMs: 5);
      final below = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 1004, note: 60),
      ], cfg);
      expect(below.duplicateCandidates, hasLength(1));

      final atThreshold = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 1005, note: 60),
      ], cfg);
      expect(atThreshold.duplicateCandidates, isEmpty);
    });
  });

  group('Determinism and immutability', () {
    test('running diagnostics twice yields an identical report', () {
      final input = <RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 1003, note: 60),
        raw(seq: 2, ts: 1500, messageType: 'note_off', note: 60),
        raw(sessionId: 'b', seq: 0, ts: 500, note: 64),
        raw(seq: 3, ts: 1600, messageType: 'other', note: null, velocity: null, rawBytes: <int>[0xB0, 48, 1]),
      ];
      final normalized = norm(input);
      const cfg = DiagnosticConfig(gapThresholdMs: 100);

      final first = analyzer.analyze(normalized, cfg);
      final second = analyzer.analyze(normalized, cfg);

      expect(second, first);
    });

    test('normalized events, source raw events and raw bytes are unchanged', () {
      final input = <RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 1003, messageType: 'note_off', note: 60),
        raw(seq: 2, ts: 2000, note: 64, velocity: 77),
      ];
      final byteSnapshots = input.map((e) => List<int>.from(e.rawBytes)).toList();
      final normalized = norm(input);

      analyzer.analyze(normalized, config);

      expect(normalized, hasLength(3));
      for (var i = 0; i < normalized.length; i++) {
        expect(identical(normalized[i].source, input[i]), isTrue);
        expect(normalized[i].source.rawBytes, byteSnapshots[i]);
      }
    });

    test('the report is deeply immutable', () {
      final report = analyze(<RawMidiEvent>[
        raw(seq: 0, ts: 1000, note: 60),
        raw(seq: 1, ts: 1003, note: 60),
        raw(seq: 2, ts: 1500, messageType: 'note_off', note: 60),
        raw(seq: 3, ts: 2500, note: 64),
      ], const DiagnosticConfig(gapThresholdMs: 100));

      expect(() => report.sessionSummaries.add(report.sessionSummaries.first),
          throwsUnsupportedError);
      expect(() => report.noteOnTimeline.add(report.noteOnTimeline.first),
          throwsUnsupportedError);
      expect(() => report.noteOffTimeline.add(report.noteOffTimeline.first),
          throwsUnsupportedError);
      expect(() => report.pitchSummaries.add(report.pitchSummaries.first),
          throwsUnsupportedError);
      expect(() => report.channelSummaries.add(report.channelSummaries.first),
          throwsUnsupportedError);
      expect(() => report.temporalBursts.add(report.temporalBursts.first),
          throwsUnsupportedError);
      expect(() => report.gapDiagnostics.add(report.gapDiagnostics.first),
          throwsUnsupportedError);
      expect(() => report.duplicateCandidates.add(report.duplicateCandidates.first),
          throwsUnsupportedError);
    });
  });
}