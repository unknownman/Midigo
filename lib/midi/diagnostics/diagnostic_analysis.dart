import 'dart:math' as math;

import '../domain/normalized_midi_event.dart';
import 'duplicate_candidate_detector.dart';
import 'monotonicity_analyzer.dart';
import 'note_pairing_analyzer.dart';

/// Explicit immutable configuration for the H2.2 diagnostic layer.
///
/// No threshold is silently inherited; defaults mirror the documented MVP
/// drafts (60 ms simultaneity window, 5 ms duplicate threshold). [gapThresholdMs]
/// is caller-supplied; when null, no interval is classified as a gap.
/// The values are diagnostic grouping parameters only - never correctness
/// thresholds.
final class DiagnosticConfig {
  final int simultaneityWindowMs;
  final int? gapThresholdMs;
  final int duplicateThresholdMs;

  const DiagnosticConfig({
    this.simultaneityWindowMs = 60,
    this.gapThresholdMs,
    this.duplicateThresholdMs = 5,
  });

  bool get gapClassificationEnabled => gapThresholdMs != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiagnosticConfig &&
          other.simultaneityWindowMs == simultaneityWindowMs &&
          other.gapThresholdMs == gapThresholdMs &&
          other.duplicateThresholdMs == duplicateThresholdMs;

  @override
  int get hashCode => Object.hash(simultaneityWindowMs, gapThresholdMs, duplicateThresholdMs);
}

/// One entry in the Note-On (or Note-Off) timeline.
final class NoteTimelineEntry {
  final int sourceSeq;
  final int timestampMs;
  final String sessionId;
  final int? channel;
  final int? pitch;
  final int? velocity;

  /// Zero-based index within the Note-On (or Note-Off) stream of the input.
  final int ordinal;

  const NoteTimelineEntry({
    required this.sourceSeq,
    required this.timestampMs,
    required this.sessionId,
    required this.channel,
    required this.pitch,
    required this.velocity,
    required this.ordinal,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteTimelineEntry &&
          other.sourceSeq == sourceSeq &&
          other.timestampMs == timestampMs &&
          other.sessionId == sessionId &&
          other.channel == channel &&
          other.pitch == pitch &&
          other.velocity == velocity &&
          other.ordinal == ordinal;

  @override
  int get hashCode =>
      Object.hash(sourceSeq, timestampMs, sessionId, channel, pitch, velocity, ordinal);
}

/// Statistics over successfully paired Note-On/Note-Off durations.
///
/// `count > 0` only when at least one pair exists. Negative durations are
/// retained (never clamped) and surface as integrity anomalies elsewhere.
final class NoteDurationSummary {
  final int count;
  final int? minMs;
  final int? maxMs;
  final double? meanMs;
  final double? medianMs;
  final double? p95Ms;

  const NoteDurationSummary({
    required this.count,
    required this.minMs,
    required this.maxMs,
    required this.meanMs,
    required this.medianMs,
    required this.p95Ms,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteDurationSummary &&
          other.count == count &&
          other.minMs == minMs &&
          other.maxMs == maxMs &&
          other.meanMs == meanMs &&
          other.medianMs == medianMs &&
          other.p95Ms == p95Ms;

  @override
  int get hashCode => Object.hash(count, minMs, maxMs, meanMs, medianMs, p95Ms);
}

/// Statistics over intra-session inter-onset intervals (Note-On deltas).
final class IoISummary {
  final int count;
  final int? minMs;
  final int? maxMs;
  final double? meanMs;
  final double? medianMs;
  final int zeroDeltaCount;

  const IoISummary({
    required this.count,
    required this.minMs,
    required this.maxMs,
    required this.meanMs,
    required this.medianMs,
    required this.zeroDeltaCount,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IoISummary &&
          other.count == count &&
          other.minMs == minMs &&
          other.maxMs == maxMs &&
          other.meanMs == meanMs &&
          other.medianMs == medianMs &&
          other.zeroDeltaCount == zeroDeltaCount;

  @override
  int get hashCode => Object.hash(count, minMs, maxMs, meanMs, medianMs, zeroDeltaCount);
}

/// Descriptive velocity statistics for normalized Note-Ons with velocity > 0.
final class VelocitySummary {
  final int count;
  final int? min;
  final int? max;
  final double? mean;
  final double? median;

  /// Population standard deviation.
  final double? stdDev;

  const VelocitySummary({
    required this.count,
    required this.min,
    required this.max,
    required this.mean,
    required this.median,
    required this.stdDev,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VelocitySummary &&
          other.count == count &&
          other.min == min &&
          other.max == max &&
          other.mean == mean &&
          other.median == median &&
          other.stdDev == stdDev;

  @override
  int get hashCode => Object.hash(count, min, max, mean, median, stdDev);
}

/// Descriptive per-pitch diagnostics. No expectation is implied.
final class PitchDiagnosticSummary {
  final int pitch;
  final int noteOnCount;
  final int noteOffCount;
  final int pairedCount;
  final int unmatchedNoteOnCount;
  final int unmatchedNoteOffCount;
  final int? minDurationMs;
  final int? maxDurationMs;
  final double? meanDurationMs;

  const PitchDiagnosticSummary({
    required this.pitch,
    required this.noteOnCount,
    required this.noteOffCount,
    required this.pairedCount,
    required this.unmatchedNoteOnCount,
    required this.unmatchedNoteOffCount,
    required this.minDurationMs,
    required this.maxDurationMs,
    required this.meanDurationMs,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PitchDiagnosticSummary &&
          other.pitch == pitch &&
          other.noteOnCount == noteOnCount &&
          other.noteOffCount == noteOffCount &&
          other.pairedCount == pairedCount &&
          other.unmatchedNoteOnCount == unmatchedNoteOnCount &&
          other.unmatchedNoteOffCount == unmatchedNoteOffCount &&
          other.minDurationMs == minDurationMs &&
          other.maxDurationMs == maxDurationMs &&
          other.meanDurationMs == meanDurationMs;

  @override
  int get hashCode => Object.hash(pitch, noteOnCount, noteOffCount, pairedCount,
      unmatchedNoteOnCount, unmatchedNoteOffCount, minDurationMs, maxDurationMs, meanDurationMs);
}

/// Descriptive per-channel diagnostics. Channel semantics are not interpreted.
final class ChannelDiagnosticSummary {
  final int channel;
  final int totalEvents;
  final int noteOnCount;
  final int noteOffCount;
  final int otherCount;
  final int uniquePitchCount;

  const ChannelDiagnosticSummary({
    required this.channel,
    required this.totalEvents,
    required this.noteOnCount,
    required this.noteOffCount,
    required this.otherCount,
    required this.uniquePitchCount,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChannelDiagnosticSummary &&
          other.channel == channel &&
          other.totalEvents == totalEvents &&
          other.noteOnCount == noteOnCount &&
          other.noteOffCount == noteOffCount &&
          other.otherCount == otherCount &&
          other.uniquePitchCount == uniquePitchCount;

  @override
  int get hashCode => Object.hash(channel, totalEvents, noteOnCount, noteOffCount, otherCount,
      uniquePitchCount);
}

/// A group of consecutive Note-Ons within one session using the configured
/// simultaneity window (chained against the burst's last timestamp).
///
/// This is purely a temporal grouping - it is never labeled a chord or a
/// performance-quality statement.
final class TemporalBurst {
  final int burstId;
  final String sessionId;
  final int firstTimestampMs;
  final int lastTimestampMs;
  final int spreadMs;
  final int eventCount;

  /// Unique pitches within the burst, ascending.
  final List<int> pitches;

  /// Unique channels within the burst, ascending.
  final List<int> channels;

  /// Source sequences of the burst events, in capture order.
  final List<int> sourceSequences;

  const TemporalBurst({
    required this.burstId,
    required this.sessionId,
    required this.firstTimestampMs,
    required this.lastTimestampMs,
    required this.spreadMs,
    required this.eventCount,
    required this.pitches,
    required this.channels,
    required this.sourceSequences,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TemporalBurst &&
          other.burstId == burstId &&
          other.sessionId == sessionId &&
          other.firstTimestampMs == firstTimestampMs &&
          other.lastTimestampMs == lastTimestampMs &&
          other.spreadMs == spreadMs &&
          other.eventCount == eventCount &&
          _intListEq(other.pitches, pitches) &&
          _intListEq(other.channels, channels) &&
          _intListEq(other.sourceSequences, sourceSequences);

  @override
  int get hashCode => Object.hash(burstId, sessionId, firstTimestampMs, lastTimestampMs,
      spreadMs, eventCount, Object.hashAll(pitches), Object.hashAll(channels),
      Object.hashAll(sourceSequences));
}

/// An interval between consecutive intra-session Note-Ons flagged by the
/// configured gap threshold.
///
/// A gap is reported only when the interval is strictly greater than
/// [DiagnosticConfig.gapThresholdMs]; an interval exactly equal to the
/// threshold is not classified as a gap. Cause (pause, interruption, rest)
/// is never inferred.
final class GapDiagnostic {
  final int previousSourceSeq;
  final int nextSourceSeq;
  final int previousTimestampMs;
  final int nextTimestampMs;
  final int gapMs;
  final String sessionId;

  /// Channel of the next Note-On; may be null for a channel-less event.
  final int? channelContext;

  const GapDiagnostic({
    required this.previousSourceSeq,
    required this.nextSourceSeq,
    required this.previousTimestampMs,
    required this.nextTimestampMs,
    required this.gapMs,
    required this.sessionId,
    required this.channelContext,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GapDiagnostic &&
          other.previousSourceSeq == previousSourceSeq &&
          other.nextSourceSeq == nextSourceSeq &&
          other.previousTimestampMs == previousTimestampMs &&
          other.nextTimestampMs == nextTimestampMs &&
          other.gapMs == gapMs &&
          other.sessionId == sessionId &&
          other.channelContext == channelContext;

  @override
  int get hashCode => Object.hash(previousSourceSeq, nextSourceSeq, previousTimestampMs,
      nextTimestampMs, gapMs, sessionId, channelContext);
}

/// Integrity anomalies reported as counts. "anomaly", not "musical error".
final class IntegritySummary {
  final int sequenceRegressionCount;
  final int duplicateSequenceCount;
  final int timestampRegressionCount;

  /// Non-note messages (normalized `other`) - raw capture is unchanged.
  final int unsupportedCount;
  final int unmatchedNoteOnCount;
  final int unmatchedNoteOffCount;
  final int negativeDurationCount;

  /// Always 0 by construction: pairing identity includes the session.
  final int crossSessionPairingCount;

  const IntegritySummary({
    required this.sequenceRegressionCount,
    required this.duplicateSequenceCount,
    required this.timestampRegressionCount,
    required this.unsupportedCount,
    required this.unmatchedNoteOnCount,
    required this.unmatchedNoteOffCount,
    required this.negativeDurationCount,
    required this.crossSessionPairingCount,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IntegritySummary &&
          other.sequenceRegressionCount == sequenceRegressionCount &&
          other.duplicateSequenceCount == duplicateSequenceCount &&
          other.timestampRegressionCount == timestampRegressionCount &&
          other.unsupportedCount == unsupportedCount &&
          other.unmatchedNoteOnCount == unmatchedNoteOnCount &&
          other.unmatchedNoteOffCount == unmatchedNoteOffCount &&
          other.negativeDurationCount == negativeDurationCount &&
          other.crossSessionPairingCount == crossSessionPairingCount;

  @override
  int get hashCode => Object.hash(sequenceRegressionCount, duplicateSequenceCount,
      timestampRegressionCount, unsupportedCount, unmatchedNoteOnCount, unmatchedNoteOffCount,
      negativeDurationCount, crossSessionPairingCount);
}

/// Per-session summary. Sessions are never merged into one timeline.
final class SessionSummary {
  final String sessionId;
  final int? firstTimestampMs;
  final int? lastTimestampMs;
  final int? sessionSpanMs;
  final int totalEvents;
  final int noteOnCount;
  final int noteOffCount;
  final int otherCount;

  /// Unique channels, ascending.
  final List<int> uniqueChannels;

  /// Unique pitches, ascending.
  final List<int> uniquePitches;
  final int? largestIoiMs;
  final int? largestBurstSpreadMs;
  final int integrityAnomalyCount;

  const SessionSummary({
    required this.sessionId,
    required this.firstTimestampMs,
    required this.lastTimestampMs,
    required this.sessionSpanMs,
    required this.totalEvents,
    required this.noteOnCount,
    required this.noteOffCount,
    required this.otherCount,
    required this.uniqueChannels,
    required this.uniquePitches,
    required this.largestIoiMs,
    required this.largestBurstSpreadMs,
    required this.integrityAnomalyCount,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionSummary &&
          other.sessionId == sessionId &&
          other.firstTimestampMs == firstTimestampMs &&
          other.lastTimestampMs == lastTimestampMs &&
          other.sessionSpanMs == sessionSpanMs &&
          other.totalEvents == totalEvents &&
          other.noteOnCount == noteOnCount &&
          other.noteOffCount == noteOffCount &&
          other.otherCount == otherCount &&
          _intListEq(other.uniqueChannels, uniqueChannels) &&
          _intListEq(other.uniquePitches, uniquePitches) &&
          other.largestIoiMs == largestIoiMs &&
          other.largestBurstSpreadMs == largestBurstSpreadMs &&
          other.integrityAnomalyCount == integrityAnomalyCount;

  @override
  int get hashCode => Object.hash(sessionId, firstTimestampMs, lastTimestampMs, sessionSpanMs,
      totalEvents, noteOnCount, noteOffCount, otherCount, Object.hashAll(uniqueChannels),
      Object.hashAll(uniquePitches), largestIoiMs, largestBurstSpreadMs, integrityAnomalyCount);
}

/// Immutable aggregate of the entire H2.2 diagnostic analysis.
final class DiagnosticAnalysisReport {
  final List<SessionSummary> sessionSummaries;
  final List<NoteTimelineEntry> noteOnTimeline;
  final List<NoteTimelineEntry> noteOffTimeline;
  final NoteDurationSummary noteDurations;
  final IoISummary ioI;
  final VelocitySummary velocity;
  final List<PitchDiagnosticSummary> pitchSummaries;
  final List<ChannelDiagnosticSummary> channelSummaries;
  final List<TemporalBurst> temporalBursts;
  final List<GapDiagnostic> gapDiagnostics;
  final List<DuplicateCandidate> duplicateCandidates;
  final IntegritySummary integrity;

  const DiagnosticAnalysisReport({
    required this.sessionSummaries,
    required this.noteOnTimeline,
    required this.noteOffTimeline,
    required this.noteDurations,
    required this.ioI,
    required this.velocity,
    required this.pitchSummaries,
    required this.channelSummaries,
    required this.temporalBursts,
    required this.gapDiagnostics,
    required this.duplicateCandidates,
    required this.integrity,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiagnosticAnalysisReport &&
          _objListEq(other.sessionSummaries, sessionSummaries) &&
          _objListEq(other.noteOnTimeline, noteOnTimeline) &&
          _objListEq(other.noteOffTimeline, noteOffTimeline) &&
          other.noteDurations == noteDurations &&
          other.ioI == ioI &&
          other.velocity == velocity &&
          _objListEq(other.pitchSummaries, pitchSummaries) &&
          _objListEq(other.channelSummaries, channelSummaries) &&
          _objListEq(other.temporalBursts, temporalBursts) &&
          _objListEq(other.gapDiagnostics, gapDiagnostics) &&
          _objListEq(other.duplicateCandidates, duplicateCandidates) &&
          other.integrity == integrity;

  @override
  int get hashCode => Object.hashAll([sessionSummaries, noteOnTimeline]);
}

/// Entry point for the H2.2 derived diagnostics layer.
///
/// Consumes normalized events (H2.1 output) plus an explicit [DiagnosticConfig]
/// and produces an immutable [DiagnosticAnalysisReport]. Deterministic: same
/// input + same config yields the identical report. Describes what happened in
/// the event stream; it never judges musical correctness.
///
/// Deterministic ordering rules:
/// * sessions by first appearance in the input;
/// * pitches ascending;
/// * channels ascending;
/// * source sequences ascending where a derived list is ordered by sequence;
/// * timelines and pairs in capture order (input order is never reordered).
final class DiagnosticAnalyzer {
  const DiagnosticAnalyzer();

  DiagnosticAnalysisReport analyze(
    Iterable<NormalizedMidiEvent> input,
    DiagnosticConfig config,
  ) {
    final events = List<NormalizedMidiEvent>.unmodifiable(input);
    final sessionOrder = <String>[];
    final bySession = <String, List<NormalizedMidiEvent>>{};
    for (final event in events) {
      final sessions = bySession.putIfAbsent(event.sessionId, () {
        sessionOrder.add(event.sessionId);
        return <NormalizedMidiEvent>[];
      });
      sessions.add(event);
    }

    final pairing = const NotePairingAnalyzer().analyze(events);
    final durations = pairing.pairs.map((p) => p.durationMs).toList(growable: false);

    final noteOnEvents = events
        .where((e) => e.type == NormalizedMidiMessageType.noteOn)
        .toList(growable: false);
    final noteOffEvents = events
        .where((e) => e.type == NormalizedMidiMessageType.noteOff)
        .toList(growable: false);

    var seqRegressions = 0;
    var tsRegressions = 0;
    var duplicateSeqIds = 0;
    for (final session in sessionOrder) {
      final monoton = const MonotonicityAnalyzer().analyze(bySession[session]!);
      seqRegressions += monoton.sequenceRegressionCount;
      tsRegressions += monoton.timestampRegressionCount;
      duplicateSeqIds += monoton.duplicateSequenceIds.length;
    }

    final noteOnTimeline = <NoteTimelineEntry>[];
    for (var i = 0; i < noteOnEvents.length; i++) {
      final e = noteOnEvents[i];
      noteOnTimeline.add(NoteTimelineEntry(
        sourceSeq: e.sourceSeq,
        timestampMs: e.sourceAppMonotonicTsMs,
        sessionId: e.sessionId,
        channel: e.channel,
        pitch: e.pitch,
        velocity: e.velocity,
        ordinal: i,
      ));
    }
    final noteOffTimeline = <NoteTimelineEntry>[];
    for (var i = 0; i < noteOffEvents.length; i++) {
      final e = noteOffEvents[i];
      noteOffTimeline.add(NoteTimelineEntry(
        sourceSeq: e.sourceSeq,
        timestampMs: e.sourceAppMonotonicTsMs,
        sessionId: e.sessionId,
        channel: e.channel,
        pitch: e.pitch,
        velocity: e.velocity,
        ordinal: i,
      ));
    }

    final bursts = _temporalBursts(events, sessionOrder, config.simultaneityWindowMs);

    final gaps = <GapDiagnostic>[];
    if (config.gapClassificationEnabled) {
      final threshold = config.gapThresholdMs!;
      for (final session in sessionOrder) {
        final sessionNoteOns = bySession[session]!
            .where((e) => e.type == NormalizedMidiMessageType.noteOn)
            .toList(growable: false);
        for (var i = 1; i < sessionNoteOns.length; i++) {
          final previous = sessionNoteOns[i - 1];
          final next = sessionNoteOns[i];
          final gap =
              next.sourceAppMonotonicTsMs - previous.sourceAppMonotonicTsMs;
          // Strictly greater than the threshold: an interval exactly equal to
          // the threshold is not classified as a gap.
          if (gap > threshold) {
            gaps.add(GapDiagnostic(
              previousSourceSeq: previous.sourceSeq,
              nextSourceSeq: next.sourceSeq,
              previousTimestampMs: previous.sourceAppMonotonicTsMs,
              nextTimestampMs: next.sourceAppMonotonicTsMs,
              gapMs: gap,
              sessionId: session,
              channelContext: next.channel,
            ));
          }
        }
      }
    }

    final duplicates =
        DuplicateCandidateDetector(thresholdMs: config.duplicateThresholdMs)
            .detect(events);

    final sessionSummaries = <SessionSummary>[];
    for (final session in sessionOrder) {
      sessionSummaries.add(
        _sessionSummary(
          session,
          bySession[session]!,
          pairing: pairing,
          bursts: bursts,
        ),
      );
    }

    return DiagnosticAnalysisReport(
      sessionSummaries: List<SessionSummary>.unmodifiable(sessionSummaries),
      noteOnTimeline: List<NoteTimelineEntry>.unmodifiable(noteOnTimeline),
      noteOffTimeline: List<NoteTimelineEntry>.unmodifiable(noteOffTimeline),
      noteDurations: _durationSummary(durations),
      ioI: _ioiSummary(events, sessionOrder),
      velocity: _velocitySummary(noteOnEvents),
      pitchSummaries: _pitchSummaries(events, pairing),
      channelSummaries: _channelSummaries(events),
      temporalBursts: List<TemporalBurst>.unmodifiable(bursts),
      gapDiagnostics: List<GapDiagnostic>.unmodifiable(gaps),
      duplicateCandidates: List<DuplicateCandidate>.unmodifiable(duplicates),
      integrity: IntegritySummary(
        sequenceRegressionCount: seqRegressions,
        duplicateSequenceCount: duplicateSeqIds,
        timestampRegressionCount: tsRegressions,
        unsupportedCount:
            events.where((e) => e.type == NormalizedMidiMessageType.other).length,
        unmatchedNoteOnCount: pairing.activeNoteOnCount,
        unmatchedNoteOffCount: pairing.unmatchedNoteOffCount,
        negativeDurationCount: durations.where((d) => d < 0).length,
        crossSessionPairingCount: 0,
      ),
    );
  }

  static List<int> _intraSessionIois(List<NormalizedMidiEvent> session) {
    final noteOns = session
        .where((e) => e.type == NormalizedMidiMessageType.noteOn)
        .toList(growable: false);
    final iois = <int>[];
    for (var i = 1; i < noteOns.length; i++) {
      iois.add(noteOns[i].sourceAppMonotonicTsMs -
          noteOns[i - 1].sourceAppMonotonicTsMs);
    }
    return iois;
  }

  static IoISummary _ioiSummary(
      List<NormalizedMidiEvent> events, List<String> sessionOrder) {
    final iois = <int>[];
    for (final session in sessionOrder) {
      final sessionEvents = events.where((e) => e.sessionId == session);
      iois.addAll(_intraSessionIois(sessionEvents.toList(growable: false)));
    }
    if (iois.isEmpty) {
      return const IoISummary(
        count: 0,
        minMs: null,
        maxMs: null,
        meanMs: null,
        medianMs: null,
        zeroDeltaCount: 0,
      );
    }
    final sorted = List<int>.from(iois)..sort();
    return IoISummary(
      count: iois.length,
      minMs: sorted.first,
      maxMs: sorted.last,
      meanMs: sorted.fold<int>(0, (a, b) => a + b) / sorted.length,
      medianMs: _medianOfSorted(sorted),
      zeroDeltaCount: sorted.where((d) => d == 0).length,
    );
  }

  static NoteDurationSummary _durationSummary(List<int> durations) {
    if (durations.isEmpty) {
      return const NoteDurationSummary(
        count: 0,
        minMs: null,
        maxMs: null,
        meanMs: null,
        medianMs: null,
        p95Ms: null,
      );
    }
    final sorted = List<int>.from(durations)..sort();
    return NoteDurationSummary(
      count: durations.length,
      minMs: sorted.first,
      maxMs: sorted.last,
      meanMs: sorted.fold<int>(0, (a, b) => a + b) / sorted.length,
      medianMs: _medianOfSorted(sorted),
      p95Ms: _percentile(sorted, 0.95),
    );
  }

  static VelocitySummary _velocitySummary(List<NormalizedMidiEvent> noteOns) {
    final velocities = noteOns
        .where((e) => e.velocity != null && e.velocity! > 0)
        .map((e) => e.velocity!)
        .toList(growable: false);
    if (velocities.isEmpty) {
      return const VelocitySummary(
        count: 0,
        min: null,
        max: null,
        mean: null,
        median: null,
        stdDev: null,
      );
    }
    final sorted = List<int>.from(velocities)..sort();
    final mean = sorted.fold<int>(0, (a, b) => a + b) / sorted.length;
    final variance = sorted.fold<double>(
            0.0, (acc, v) => acc + ((v - mean) * (v - mean))) /
        sorted.length;
    return VelocitySummary(
      count: velocities.length,
      min: sorted.first,
      max: sorted.last,
      mean: mean,
      median: _medianOfSorted(sorted),
      stdDev: math.sqrt(variance),
    );
  }

  static List<PitchDiagnosticSummary> _pitchSummaries(
    List<NormalizedMidiEvent> events,
    NotePairingReport pairing,
  ) {
    final pitches =
        events.map((e) => e.pitch).whereType<int>().toSet().toList()..sort();
    final activeByPitch = <int, List<NormalizedMidiEvent>>{};
    for (final event in pairing.activeNoteOns) {
      final pitch = event.pitch;
      if (pitch != null) {
        activeByPitch.putIfAbsent(pitch, () => <NormalizedMidiEvent>[]).add(event);
      }
    }
    final unmatchedOffByPitch = <int, List<NormalizedMidiEvent>>{};
    for (final event in pairing.unmatchedNoteOffs) {
      final pitch = event.pitch;
      if (pitch != null) {
        unmatchedOffByPitch.putIfAbsent(pitch, () => <NormalizedMidiEvent>[]).add(event);
      }
    }
    final pairsByPitch = <int, List<NotePair>>{};
    for (final pair in pairing.pairs) {
      pairsByPitch
          .putIfAbsent(pair.noteOn.pitch!, () => <NotePair>[])
          .add(pair);
    }

    return List<PitchDiagnosticSummary>.unmodifiable(pitches.map((pitch) {
      final durations = pairsByPitch[pitch]?.map((p) => p.durationMs).toList() ?? [];
      final sorted = List<int>.from(durations)..sort();
      return PitchDiagnosticSummary(
        pitch: pitch,
        noteOnCount: events
            .where((e) => e.type == NormalizedMidiMessageType.noteOn && e.pitch == pitch)
            .length,
        noteOffCount: events
            .where((e) => e.type == NormalizedMidiMessageType.noteOff && e.pitch == pitch)
            .length,
        pairedCount: pairsByPitch[pitch]?.length ?? 0,
        unmatchedNoteOnCount: activeByPitch[pitch]?.length ?? 0,
        unmatchedNoteOffCount: unmatchedOffByPitch[pitch]?.length ?? 0,
        minDurationMs: sorted.isEmpty ? null : sorted.first,
        maxDurationMs: sorted.isEmpty ? null : sorted.last,
        meanDurationMs:
            sorted.isEmpty ? null : sorted.fold<int>(0, (a, b) => a + b) / sorted.length,
      );
    }).toList(growable: false));
  }

  static List<ChannelDiagnosticSummary> _channelSummaries(
      List<NormalizedMidiEvent> events) {
    final channels =
        events.map((e) => e.channel).whereType<int>().toSet().toList()..sort();
    return List<ChannelDiagnosticSummary>.unmodifiable(channels.map((channel) {
      final channelEvents = events.where((e) => e.channel == channel);
      final pitches = <int>{};
      for (final e in channelEvents) {
        if (e.type != NormalizedMidiMessageType.other && e.pitch != null) {
          pitches.add(e.pitch!);
        }
      }
      final list = channelEvents.toList(growable: false);
      return ChannelDiagnosticSummary(
        channel: channel,
        totalEvents: list.length,
        noteOnCount: list
            .where((e) => e.type == NormalizedMidiMessageType.noteOn)
            .length,
        noteOffCount: list
            .where((e) => e.type == NormalizedMidiMessageType.noteOff)
            .length,
        otherCount: list
            .where((e) => e.type == NormalizedMidiMessageType.other)
            .length,
        uniquePitchCount: pitches.length,
      );
    }).toList(growable: false));
  }

  static List<TemporalBurst> _temporalBursts(
    List<NormalizedMidiEvent> events,
    List<String> sessionOrder,
    int windowMs,
  ) {
    final bursts = <TemporalBurst>[];
    var burstId = 1;
    for (final session in sessionOrder) {
      final sessionNoteOns = events
          .where((e) => e.sessionId == session && e.type == NormalizedMidiMessageType.noteOn)
          .toList(growable: false);
      if (sessionNoteOns.isEmpty) {
        continue;
      }
      var current = <NormalizedMidiEvent>[sessionNoteOns.first];
      var lastTs = sessionNoteOns.first.sourceAppMonotonicTsMs;
      for (var i = 1; i < sessionNoteOns.length; i++) {
        final event = sessionNoteOns[i];
        if (event.sourceAppMonotonicTsMs - lastTs <= windowMs) {
          current.add(event);
        } else {
          bursts.add(_translateBurst(burstId++, session, current));
          current = <NormalizedMidiEvent>[event];
        }
        lastTs = event.sourceAppMonotonicTsMs;
      }
      bursts.add(_translateBurst(burstId++, session, current));
    }
    return bursts;
  }

  static TemporalBurst _translateBurst(
      int burstId, String session, List<NormalizedMidiEvent> members) {
    final sorted = List<NormalizedMidiEvent>.from(members)
      ..sort((a, b) => a.sourceAppMonotonicTsMs.compareTo(b.sourceAppMonotonicTsMs));
    final first = sorted.first.sourceAppMonotonicTsMs;
    final last = sorted.last.sourceAppMonotonicTsMs;
    return TemporalBurst(
      burstId: burstId,
      sessionId: session,
      firstTimestampMs: first,
      lastTimestampMs: last,
      spreadMs: last - first,
      eventCount: members.length,
      pitches: members.map((e) => e.pitch).whereType<int>().toSet().toList()..sort(),
      channels: members.map((e) => e.channel).whereType<int>().toSet().toList()..sort(),
      sourceSequences: List<int>.from(members.map((e) => e.sourceSeq)),
    );
  }

  static SessionSummary _sessionSummary(
    String session,
    List<NormalizedMidiEvent> sessionEvents, {
    required NotePairingReport pairing,
    required List<TemporalBurst> bursts,
  }) {
    final noteOnCount = sessionEvents
        .where((e) => e.type == NormalizedMidiMessageType.noteOn)
        .length;
    final noteOffCount = sessionEvents
        .where((e) => e.type == NormalizedMidiMessageType.noteOff)
        .length;
    final otherCount =
        sessionEvents.where((e) => e.type == NormalizedMidiMessageType.other).length;
    final channels =
        sessionEvents.map((e) => e.channel).whereType<int>().toSet().toList()..sort();
    final pitches =
        sessionEvents.map((e) => e.pitch).whereType<int>().toSet().toList()..sort();
    final firstTs = sessionEvents.isEmpty ? null : sessionEvents.first.sourceAppMonotonicTsMs;
    final lastTs = sessionEvents.isEmpty ? null : sessionEvents.last.sourceAppMonotonicTsMs;
    final iois = _intraSessionIois(sessionEvents);
    final sessionBursts =
        bursts.where((b) => b.sessionId == session).toList(growable: false);
    final maxBurstSpread = sessionBursts.isEmpty
        ? null
        : sessionBursts.map((b) => b.spreadMs).reduce(math.max);

    final monoton = const MonotonicityAnalyzer().analyze(sessionEvents);
    final unmatchedIn = pairing.activeNoteOns
        .where((e) => e.sessionId == session)
        .length;
    final unmatchedOffIn = pairing.unmatchedNoteOffs
        .where((e) => e.sessionId == session)
        .length;
    final negativeInSession = pairing.pairs
        .where((p) => p.sessionId == session && p.durationMs < 0)
        .length;
    final anomalyCount = monoton.sequenceRegressionCount +
        monoton.timestampRegressionCount +
        monoton.duplicateSequenceIds.length +
        unmatchedIn +
        unmatchedOffIn +
        negativeInSession;

    return SessionSummary(
      sessionId: session,
      firstTimestampMs: firstTs,
      lastTimestampMs: lastTs,
      sessionSpanMs: (firstTs != null && lastTs != null) ? lastTs - firstTs : null,
      totalEvents: sessionEvents.length,
      noteOnCount: noteOnCount,
      noteOffCount: noteOffCount,
      otherCount: otherCount,
      uniqueChannels: List<int>.unmodifiable(channels),
      uniquePitches: List<int>.unmodifiable(pitches),
      largestIoiMs: iois.isEmpty ? null : iois.reduce(math.max),
      largestBurstSpreadMs: maxBurstSpread,
      integrityAnomalyCount: anomalyCount,
    );
  }
}

double _medianOfSorted(List<int> sorted) {
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) {
    return sorted[middle].toDouble();
  }
  return (sorted[middle - 1] + sorted[middle]) / 2.0;
}

double _percentile(List<int> sorted, double q) {
  final index =
      math.min(sorted.length - 1, (q * sorted.length).ceil() - 1);
  return sorted[index].toDouble();
}

bool _intListEq(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

bool _objListEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}