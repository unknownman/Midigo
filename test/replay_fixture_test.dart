import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/midi/application/midi_normalizer.dart';
import 'package:miditutor/midi/application/raw_midi_jsonl_reader.dart';
import 'package:miditutor/midi/domain/normalized_midi_event.dart';
import 'package:miditutor/midi/domain/raw_midi_event.dart';
import 'package:miditutor/midi/diagnostics/diagnostic_analysis.dart';

/// Deterministic fixture path helper. Fixtures are committed under
/// test/fixtures/ and are read as-is; they are never modified by replay.
String fixture(String name) =>
    File('test/fixtures/$name.jsonl').readAsStringSync();

class PipelineResult {
  final JsonlReplayResult replay;
  final List<NormalizedMidiEvent> normalized;
  final DiagnosticAnalysisReport report;

  const PipelineResult({
    required this.replay,
    required this.normalized,
    required this.report,
  });
}

class GoldenRows {
  final String fixture;
  final int raw;
  final int noteOn;
  final int noteOff;
  final int other;
  final int paired;
  final int unmatchedOn;
  final int unmatchedOff;
  final int ioiCount;
  final int bursts;
  final int duplicates;
  final int sequenceRegression;
  final int timestampRegression;
  final int duplicateSequences;

  const GoldenRows({
    required this.fixture,
    required this.raw,
    required this.noteOn,
    required this.noteOff,
    required this.other,
    required this.paired,
    required this.unmatchedOn,
    required this.unmatchedOff,
    required this.ioiCount,
    required this.bursts,
    required this.duplicates,
    required this.sequenceRegression,
    required this.timestampRegression,
    required this.duplicateSequences,
  });
}

void main() {
  const reader = JsonlRawMidiEventReader();
  const normalizer = MidiNormalizer();
  const analyzer = DiagnosticAnalyzer();
  const config = DiagnosticConfig();

  PipelineResult pipeline(String name) {
    final replay = reader.read(fixture(name));
    expect(replay.status, JsonlReplayStatus.success, reason: name);
    expect(replay.issues, isEmpty, reason: name);
    final normalized = normalizer.normalizeAll(replay.events);
    final report = analyzer.analyze(normalized, config);
    return PipelineResult(
      replay: replay,
      normalized: List<NormalizedMidiEvent>.unmodifiable(normalized),
      report: report,
    );
  }

  group('H2.3 golden results (regression protection)', () {
    const goldens = <GoldenRows>[
      GoldenRows(
          fixture: 'f1_simple_note', raw: 2, noteOn: 1, noteOff: 1, other: 0,
          paired: 1, unmatchedOn: 0, unmatchedOff: 0, ioiCount: 0, bursts: 1,
          duplicates: 0, sequenceRegression: 0, timestampRegression: 0,
          duplicateSequences: 0),
      GoldenRows(
          fixture: 'f2_velocity_zero', raw: 2, noteOn: 1, noteOff: 1, other: 0,
          paired: 1, unmatchedOn: 0, unmatchedOff: 0, ioiCount: 0, bursts: 1,
          duplicates: 0, sequenceRegression: 0, timestampRegression: 0,
          duplicateSequences: 0),
      GoldenRows(
          fixture: 'f3_three_note_burst', raw: 3, noteOn: 3, noteOff: 0,
          other: 0, paired: 0, unmatchedOn: 3, unmatchedOff: 0, ioiCount: 2,
          bursts: 1, duplicates: 0, sequenceRegression: 0,
          timestampRegression: 0, duplicateSequences: 0),
      GoldenRows(
          fixture: 'f4_arpeggiated', raw: 4, noteOn: 4, noteOff: 0, other: 0,
          paired: 0, unmatchedOn: 4, unmatchedOff: 0, ioiCount: 3, bursts: 4,
          duplicates: 0, sequenceRegression: 0, timestampRegression: 0,
          duplicateSequences: 0),
      GoldenRows(
          fixture: 'f5_unmatched_note_on', raw: 1, noteOn: 1, noteOff: 0,
          other: 0, paired: 0, unmatchedOn: 1, unmatchedOff: 0, ioiCount: 0,
          bursts: 1, duplicates: 0, sequenceRegression: 0,
          timestampRegression: 0, duplicateSequences: 0),
      GoldenRows(
          fixture: 'f6_unmatched_note_off', raw: 1, noteOn: 0, noteOff: 1,
          other: 0, paired: 0, unmatchedOn: 0, unmatchedOff: 1, ioiCount: 0,
          bursts: 0, duplicates: 0, sequenceRegression: 0,
          timestampRegression: 0, duplicateSequences: 0),
      GoldenRows(
          fixture: 'f7_multiple_sessions', raw: 4, noteOn: 4, noteOff: 0,
          other: 0, paired: 0, unmatchedOn: 4, unmatchedOff: 0, ioiCount: 2,
          bursts: 4, duplicates: 0, sequenceRegression: 0,
          timestampRegression: 0, duplicateSequences: 0),
      GoldenRows(
          fixture: 'f8_non_note_midi', raw: 3, noteOn: 1, noteOff: 1, other: 1,
          paired: 1, unmatchedOn: 0, unmatchedOff: 0, ioiCount: 0, bursts: 1,
          duplicates: 0, sequenceRegression: 0, timestampRegression: 0,
          duplicateSequences: 0),
      GoldenRows(
          fixture: 'f9_duplicate_candidate', raw: 2, noteOn: 2, noteOff: 0,
          other: 0, paired: 0, unmatchedOn: 2, unmatchedOff: 0, ioiCount: 1,
          bursts: 1, duplicates: 1, sequenceRegression: 0,
          timestampRegression: 0, duplicateSequences: 0),
      GoldenRows(
          fixture: 'f10_integrity_anomaly', raw: 3, noteOn: 3, noteOff: 0,
          other: 0, paired: 0, unmatchedOn: 3, unmatchedOff: 0, ioiCount: 2,
          bursts: 1, duplicates: 0, sequenceRegression: 1,
          timestampRegression: 1, duplicateSequences: 1),
    ];

    for (final g in goldens) {
      test('${g.fixture} reproduces every golden count deterministically',
          () {
        final first = pipeline(g.fixture);
        final second = pipeline(g.fixture);

        // Report `==` is cross-instance-unstable for duplicate candidates
        // (RawMidiEvent identity), so determinism is asserted via the
        // canonical projection over stable scalar fields.
        expect(_canonical(second.report), _canonical(first.report),
            reason: g.fixture);
        expect(first.replay.events, hasLength(g.raw), reason: g.fixture);
        expect(first.report.integrity.unsupportedCount, g.other,
            reason: g.fixture);
        expect(_noteOnCount(first.report), g.noteOn, reason: g.fixture);
        expect(_noteOffCount(first.report), g.noteOff, reason: g.fixture);
        expect(first.report.noteDurations.count, g.paired, reason: g.fixture);
        expect(first.report.integrity.unmatchedNoteOnCount, g.unmatchedOn,
            reason: g.fixture);
        expect(first.report.integrity.unmatchedNoteOffCount, g.unmatchedOff,
            reason: g.fixture);
        expect(first.report.ioI.count, g.ioiCount, reason: g.fixture);
        expect(first.report.temporalBursts.length, g.bursts, reason: g.fixture);
        expect(first.report.duplicateCandidates.length, g.duplicates,
            reason: g.fixture);
        expect(first.report.integrity.sequenceRegressionCount,
            g.sequenceRegression, reason: g.fixture);
        expect(first.report.integrity.timestampRegressionCount,
            g.timestampRegression, reason: g.fixture);
        expect(first.report.integrity.duplicateSequenceCount, g.duplicateSequences,
            reason: g.fixture);
      });
    }
  });

  group('F1 - simple note', () {
    test('two raw events normalize to Note-On + Note-Off and pair', () {
      final p = pipeline('f1_simple_note');

      expect(p.replay.events, hasLength(2));
      expect(p.normalized.map((e) => e.type),
          <NormalizedMidiMessageType>[
        NormalizedMidiMessageType.noteOn,
        NormalizedMidiMessageType.noteOff,
      ]);
      expect(p.normalized[0].normalizationRule, 'note_on');
      expect(p.normalized[1].normalizationRule, 'note_off');
      expect(p.report.noteDurations.count, 1);
      expect(p.report.noteDurations.minMs, 500);
      expect(p.report.noteDurations.maxMs, 500);
      expect(p.report.noteOnTimeline.single.ordinal, 0);
      expect(p.report.noteOffTimeline.single.ordinal, 0);
    });
  });

  group('F2 - velocity-zero Note-Off', () {
    test('raw second event stays Note-On while H2.1 derives Note-Off', () {
      final p = pipeline('f2_velocity_zero');

      final rawSecond = p.replay.events[1];
      expect(rawSecond.messageType, RawMidiMessageType.noteOn);
      expect(rawSecond.velocity, 0);
      expect(rawSecond.rawBytes, <int>[144, 60, 0]);

      expect(p.normalized[1].type, NormalizedMidiMessageType.noteOff);
      expect(p.normalized[1].normalizationRule, 'note_on_velocity_zero');

      expect(p.report.noteDurations.count, 1);
      expect(p.report.noteDurations.minMs, 300);
      expect(p.report.noteDurations.maxMs, 300);
      expect(p.report.noteOffTimeline, hasLength(1));
      expect(p.report.noteOnTimeline, hasLength(1));
    });

    test('raw fields of the velocity-zero event are never mutated', () {
      final first = reader.read(fixture('f2_velocity_zero'));
      final second = reader.read(fixture('f2_velocity_zero'));

      final event = second.events[1];
      expect(event.messageType, first.events[1].messageType);
      expect(event.rawBytes.first, first.events[1].rawBytes.first);
      expect(event.rawBytes, first.events[1].rawBytes);
      expect(event.seq, first.events[1].seq);
      expect(event.appMonotonicTsMs, first.events[1].appMonotonicTsMs);
      expect(event.sessionId, first.events[1].sessionId);
    });
  });

  group('F3 - three-note burst', () {
    test('three Note-Ons form one temporal burst within the 60 ms window', () {
      final p = pipeline('f3_three_note_burst');

      expect(p.report.noteOnTimeline, hasLength(3));
      expect(p.report.temporalBursts, hasLength(1));
      final burst = p.report.temporalBursts.single;
      expect(burst.eventCount, 3);
      expect(burst.firstTimestampMs, 1000);
      expect(burst.lastTimestampMs, 1059);
      expect(burst.spreadMs, 59);
      expect(burst.pitches, <int>[60, 64, 67]);
      expect(burst.sourceSequences, <int>[0, 1, 2]);

      // No musical chord classification exists in the H2.2 report model.
      expect(p.report.integrity.negativeDurationCount, 0);
    });
  });

  group('F4 - arpeggiated sequence', () {
    test('four Note-Ons preserve order and produce correct IOIs', () {
      final p = pipeline('f4_arpeggiated');

      expect(p.report.noteOnTimeline.map((e) => e.sourceSeq), <int>[0, 1, 2, 3]);
      expect(p.report.noteOnTimeline.map((e) => e.pitch), <int>[60, 64, 67, 71]);
      expect(p.report.ioI.count, 3);
      expect(p.report.ioI.minMs, 300);
      expect(p.report.ioI.maxMs, 300);
      expect(p.report.ioI.meanMs, 300);
      expect(p.report.ioI.medianMs, 300);
      expect(p.report.ioI.zeroDeltaCount, 0);
      // Events spaced beyond the 60 ms burst window split into one burst each.
      expect(p.report.temporalBursts, hasLength(4));
    });
  });

  group('F5 - unmatched Note-On', () {
    test('raw and normalized Note-On are preserved, no Note-Off invented', () {
      final p = pipeline('f5_unmatched_note_on');

      expect(p.replay.events.single.messageType, RawMidiMessageType.noteOn);
      expect(p.normalized.single.type, NormalizedMidiMessageType.noteOn);
      expect(p.normalized.single.normalizationRule, 'note_on');
      expect(p.report.integrity.unmatchedNoteOnCount, 1);
      expect(p.report.integrity.unmatchedNoteOffCount, 0);
      expect(p.report.noteDurations.count, 0);
      expect(p.report.noteOffTimeline, isEmpty);
    });
  });

  group('F6 - unmatched Note-Off', () {
    test('raw Note-Off is preserved, no Note-On invented', () {
      final p = pipeline('f6_unmatched_note_off');

      expect(p.replay.events.single.messageType, RawMidiMessageType.noteOff);
      expect(p.normalized.single.type, NormalizedMidiMessageType.noteOff);
      expect(p.report.integrity.unmatchedNoteOffCount, 1);
      expect(p.report.integrity.unmatchedNoteOnCount, 0);
      expect(p.report.noteDurations.count, 0);
      expect(p.report.noteOnTimeline, isEmpty);
    });
  });

  group('F7 - multiple sessions', () {
    test('sessions stay isolated with no cross-session IOI, pairing, or burst',
        () {
      final p = pipeline('f7_multiple_sessions');

      expect(p.report.sessionSummaries.map((s) => s.sessionId),
          <String>['session-f7a', 'session-f7b']);

      final a = p.report.sessionSummaries[0];
      expect(a.firstTimestampMs, 1000);
      expect(a.lastTimestampMs, 2000);
      expect(a.sessionSpanMs, 1000);
      expect(a.largestIoiMs, 1000);
      expect(a.uniquePitches, <int>[60, 64]);

      final b = p.report.sessionSummaries[1];
      expect(b.firstTimestampMs, 100);
      expect(b.lastTimestampMs, 200);
      expect(b.sessionSpanMs, 100);
      expect(b.largestIoiMs, 100);

      // a:[1000], b:[100] -> 2 IOIs; a cross-session collapse would give 3.
      expect(p.report.ioI.count, 2);
      expect(p.report.ioI.minMs, 100);
      expect(p.report.ioI.maxMs, 1000);
      expect(p.report.noteDurations.count, 0);
      expect(p.report.integrity.crossSessionPairingCount, 0);

      for (final burst in p.report.temporalBursts) {
        expect(burst.eventCount, 1, reason: 'cross-session burst gap');
      }
    });
  });

  group('F8 - non-note MIDI', () {
    test('CC event normalizes to Other and is never treated as a note', () {
      final p = pipeline('f8_non_note_midi');

      expect(p.normalized.map((e) => e.type),
          <NormalizedMidiMessageType>[
        NormalizedMidiMessageType.other,
        NormalizedMidiMessageType.noteOn,
        NormalizedMidiMessageType.noteOff,
      ]);
      expect(p.report.integrity.unsupportedCount, 1);
      expect(p.report.noteOnTimeline, hasLength(1));
      expect(p.report.noteDurations.count, 1);
      expect(p.report.noteDurations.minMs, 800);

      final ch0 = p.report.channelSummaries.single;
      expect(ch0.channel, 0);
      expect(ch0.totalEvents, 3);
      expect(ch0.noteOnCount, 1);
      expect(ch0.noteOffCount, 1);
      expect(ch0.otherCount, 1);
      expect(ch0.uniquePitchCount, 1);

      final other = p.report.noteOffTimeline;
      expect(other, hasLength(1));
    });
  });

  group('F9 - duplicate candidate', () {
    test('candidate reported within threshold, both events retained', () {
      final p = pipeline('f9_duplicate_candidate');

      expect(p.report.duplicateCandidates, hasLength(1));
      final candidate = p.report.duplicateCandidates.single;
      expect(candidate.deltaMs, 3);
      expect(candidate.thresholdMs, 5);
      expect(candidate.first.sourceSeq, 0);
      expect(candidate.second.sourceSeq, 1);
      expect(p.report.noteOnTimeline, hasLength(2));
      expect(p.report.integrity.unmatchedNoteOnCount, 2);
    });
  });

  group('F10 - integrity anomaly', () {
    test('anomalies are reported without reordering or repairing input', () {
      final p = pipeline('f10_integrity_anomaly');

      expect(p.report.integrity.sequenceRegressionCount, 1);
      expect(p.report.integrity.duplicateSequenceCount, 1);
      expect(p.report.integrity.timestampRegressionCount, 1);
      expect(p.report.integrity.crossSessionPairingCount, 0);

      // Order preserved exactly as stored.
      expect(p.report.noteOnTimeline.map((e) => e.sourceSeq), <int>[5, 3, 3]);
      expect(p.report.noteOnTimeline.map((e) => e.timestampMs), <int>[1000, 999, 1005]);

      // Raw deltas are reported verbatim (negative IOI included).
      expect(p.report.ioI.count, 2);
      expect(p.report.ioI.minMs, -1);
      expect(p.report.ioI.maxMs, 6);
    });
  });

  group('determinism and immutability across fixtures', () {
    const allFixtures = <String>[
      'f1_simple_note',
      'f2_velocity_zero',
      'f3_three_note_burst',
      'f4_arpeggiated',
      'f5_unmatched_note_on',
      'f6_unmatched_note_off',
      'f7_multiple_sessions',
      'f8_non_note_midi',
      'f9_duplicate_candidate',
      'f10_integrity_anomaly',
    ];

    for (final name in allFixtures) {
      test('$name replays twice into an identical report', () {
        expect(_canonical(pipeline(name).report), _canonical(pipeline(name).report));
      });

      test('$name normalized events retain their raw sources', () {
        final replay = reader.read(fixture(name));
        final normalized = normalizer.normalizeAll(replay.events);
        final report = analyzer.analyze(normalized, config);
        final events = replay.events;

        expect(normalized, hasLength(events.length));
        for (var i = 0; i < normalized.length; i++) {
          expect(identical(normalized[i].source, events[i]), isTrue,
              reason: 'index $i');
        }
        expect(report, isA<DiagnosticAnalysisReport>());
      });
    }
  });
}

int _noteOnCount(DiagnosticAnalysisReport report) {
  var count = 0;
  for (final c in report.channelSummaries) {
    count += c.noteOnCount;
  }
  return count + _noteOnsWithoutChannel(report);
}

int _noteOnsWithoutChannel(DiagnosticAnalysisReport report) {
  var count = 0;
  for (final e in report.noteOnTimeline) {
    if (e.channel == null) {
      count += 1;
    }
  }
  return count;
}

int _noteOffCount(DiagnosticAnalysisReport report) {
  var count = 0;
  for (final c in report.channelSummaries) {
    count += c.noteOffCount;
  }
  return count + _noteOffsWithoutChannel(report);
}

int _noteOffsWithoutChannel(DiagnosticAnalysisReport report) {
  var count = 0;
  for (final e in report.noteOffTimeline) {
    if (e.channel == null) {
      count += 1;
    }
  }
  return count;
}

/// Stable, cross-instance canonical projection of a diagnostic report.
///
/// The frozen H2.2 report `==` is identity-unstable for duplicate candidates
/// (it chains to `RawMidiEvent` which has no value equality), so determinism is
/// proven on this projection, which uses only scalar fields derived from the
/// stored capture - never object identity.
String _canonical(DiagnosticAnalysisReport report) {
  final b = StringBuffer();
  for (final s in report.sessionSummaries) {
    b.writeln(
        'session:${s.sessionId} first=${s.firstTimestampMs} last=${s.lastTimestampMs} '
        'span=${s.sessionSpanMs} total=${s.totalEvents} on=${s.noteOnCount} '
        'off=${s.noteOffCount} other=${s.otherCount} '
        'ch=${s.uniqueChannels} pitch=${s.uniquePitches} '
        'largestIoi=${s.largestIoiMs} largestBurst=${s.largestBurstSpreadMs} '
        'anomalies=${s.integrityAnomalyCount}');
  }
  for (final e in report.noteOnTimeline) {
    b.writeln(
        'on:seq=${e.sourceSeq} ts=${e.timestampMs} sess=${e.sessionId} '
        'ch=${e.channel} pitch=${e.pitch} vel=${e.velocity} ord=${e.ordinal}');
  }
  for (final e in report.noteOffTimeline) {
    b.writeln('off:${_noteTimeline(e)}');
  }
  final d = report.noteDurations;
  b.writeln(
      'durations:count=${d.count} min=${d.minMs} max=${d.maxMs} '
      'mean=${d.meanMs} median=${d.medianMs} p95=${d.p95Ms}');
  final i = report.ioI;
  b.writeln(
      'ioi:count=${i.count} min=${i.minMs} max=${i.maxMs} mean=${i.meanMs} '
      'median=${i.medianMs} zero=${i.zeroDeltaCount}');
  final v = report.velocity;
  b.writeln(
      'velocity:count=${v.count} min=${v.min} max=${v.max} mean=${v.mean} '
      'median=${v.median} std=${v.stdDev}');
  for (final p in report.pitchSummaries) {
    b.writeln(
        'pitch:${p.pitch} on=${p.noteOnCount} off=${p.noteOffCount} '
        'paired=${p.pairedCount} unOn=${p.unmatchedNoteOnCount} '
        'unOff=${p.unmatchedNoteOffCount} minD=${p.minDurationMs} '
        'maxD=${p.maxDurationMs} meanD=${p.meanDurationMs}');
  }
  for (final c in report.channelSummaries) {
    b.writeln(
        'channel:${c.channel} total=${c.totalEvents} on=${c.noteOnCount} '
        'off=${c.noteOffCount} other=${c.otherCount} pitches=${c.uniquePitchCount}');
  }
  for (final burst in report.temporalBursts) {
    b.writeln(
        'burst:${burst.burstId} sess=${burst.sessionId} first=${burst.firstTimestampMs} '
        'last=${burst.lastTimestampMs} spread=${burst.spreadMs} '
        'count=${burst.eventCount} pitches=${burst.pitches} '
        'channels=${burst.channels} seqs=${burst.sourceSequences}');
  }
  for (final gap in report.gapDiagnostics) {
    b.writeln(
        'gap:from=${gap.previousSourceSeq}@${gap.previousTimestampMs} '
        'to=${gap.nextSourceSeq}@${gap.nextTimestampMs} '
        'gapMs=${gap.gapMs} sess=${gap.sessionId} ch=${gap.channelContext}');
  }
  for (final c in report.duplicateCandidates) {
    b.writeln(
        'dup:delta=${c.deltaMs} threshold=${c.thresholdMs} '
        'first=${c.first.sourceSeq} second=${c.second.sourceSeq}');
  }
  final integrity = report.integrity;
  b.writeln(
      'integrity:seqReg=${integrity.sequenceRegressionCount} '
      'dupSeq=${integrity.duplicateSequenceCount} '
      'tsReg=${integrity.timestampRegressionCount} '
      'unsupported=${integrity.unsupportedCount} '
      'unOn=${integrity.unmatchedNoteOnCount} unOff=${integrity.unmatchedNoteOffCount} '
      'negDuration=${integrity.negativeDurationCount} '
      'crossSession=${integrity.crossSessionPairingCount}');
  return b.toString();
}

String _noteTimeline(NoteTimelineEntry e) =>
    'seq=${e.sourceSeq} ts=${e.timestampMs} sess=${e.sessionId} '
    'ch=${e.channel} pitch=${e.pitch} vel=${e.velocity} ord=${e.ordinal}';