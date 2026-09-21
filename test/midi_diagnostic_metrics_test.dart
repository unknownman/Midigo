import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/midi/application/midi_normalizer.dart';
import 'package:miditutor/midi/domain/normalized_midi_event.dart';
import 'package:miditutor/midi/domain/raw_midi_event.dart';
import 'package:miditutor/midi/diagnostics/midi_diagnostic_metrics.dart';

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
  const metrics = MidiDiagnosticMetrics();

  List<NormalizedMidiEvent> norm(List<RawMidiEvent> raw) =>
      normalizer.normalizeAll(raw);

  group('MidiDiagnosticMetrics', () {
    test('event counts over normalized events', () {
      final report = metrics.compute(norm(<RawMidiEvent>[
        raw(seq: 0),
        raw(seq: 1),
        raw(seq: 2, messageType: 'note_off', note: 60, rawBytes: <int>[0x80, 60, 0]),
        raw(seq: 3, messageType: 'other', channel: 0, note: null, velocity: null, rawBytes: <int>[0xB0, 48, 1]),
      ]));

      expect(report.counts.total, 4);
      expect(report.counts.noteOn, 2);
      expect(report.counts.noteOff, 1);
      expect(report.counts.otherCount, 1);
    });

    test('pitch statistics over note events', () {
      final report = metrics.compute(norm(<RawMidiEvent>[
        raw(seq: 0, note: 48, rawBytes: <int>[0x90, 48, 1]),
        raw(seq: 1, note: 72, rawBytes: <int>[0x90, 72, 1]),
        raw(seq: 2, note: 60, rawBytes: <int>[0x90, 60, 1]),
        raw(seq: 3, messageType: 'other', channel: 0, note: null, velocity: null, rawBytes: <int>[0xF0]),
      ]));

      expect(report.pitches.minPitch, 48);
      expect(report.pitches.maxPitch, 72);
      expect(report.pitches.uniquePitchCount, 3);
    });

    test('channel statistics', () {
      final report = metrics.compute(norm(<RawMidiEvent>[
        raw(seq: 0, channel: 0),
        raw(seq: 1, channel: 1),
        raw(seq: 2, channel: 1),
      ]));

      expect(report.channels.uniqueChannels, <int>{0, 1});
      expect(report.channels.eventsPerChannel, <int, int>{0: 1, 1: 2});
    });

    test('timing statistics including zero-delta intervals (N14)', () {
      final report = metrics.compute(norm(<RawMidiEvent>[
        raw(seq: 0, ts: 1000),
        raw(seq: 1, ts: 1000),
        raw(seq: 2, ts: 1004),
        raw(seq: 3, ts: 1010),
      ]));

      final timing = report.timing;
      expect(timing.minDeltaMs, 0);
      expect(timing.maxDeltaMs, 6);
      expect(timing.meanDeltaMs, closeTo((0 + 4 + 6) / 3, 1e-9));
      expect(timing.medianDeltaMs, 4);
      expect(timing.zeroDeltaCount, 1);
    });

    test('timing is null when fewer than two events', () {
      final report = metrics.compute(norm(<RawMidiEvent>[raw(seq: 0, ts: 1000)]));

      expect(report.timing.minDeltaMs, isNull);
      expect(report.timing.maxDeltaMs, isNull);
      expect(report.timing.medianDeltaMs, isNull);
      expect(report.timing.zeroDeltaCount, 0);
    });

    test('N14: zero-delta events remain valid events', () {
      final input = <RawMidiEvent>[
        raw(seq: 0, ts: 5000, note: 60),
        raw(seq: 1, ts: 5000, note: 62),
      ];
      final normalized = norm(input);
      final report = metrics.compute(normalized);

      expect(report.timing.zeroDeltaCount, 1);
      expect(report.counts.total, 2);
      // Both events remain present and traceable.
      final tsSet = <int>{};
      for (final e in normalized) {
        tsSet.add(e.sourceAppMonotonicTsMs);
      }
      expect(tsSet, {5000});
    });
  });
}