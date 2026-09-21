import 'dart:math' as math;

import '../domain/normalized_midi_event.dart';

/// Event count summary over normalized events.
final class EventCounts {
  final int total;
  final int noteOn;
  final int noteOff;
  final int otherCount;

  const EventCounts({
    required this.total,
    required this.noteOn,
    required this.noteOff,
    required this.otherCount,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventCounts &&
          other.total == total &&
          other.noteOn == noteOn &&
          other.noteOff == noteOff &&
          other.otherCount == otherCount;

  @override
  int get hashCode => Object.hash(total, noteOn, noteOff, otherCount);

  @override
  String toString() =>
      'EventCounts(total: $total, noteOn: $noteOn, noteOff: $noteOff, other: $otherCount)';
}

/// Pitch statistics over normalized note events (Note-On and Note-Off).
final class PitchStatistics {
  final int? minPitch;
  final int? maxPitch;
  final int uniquePitchCount;

  const PitchStatistics({
    required this.minPitch,
    required this.maxPitch,
    required this.uniquePitchCount,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PitchStatistics &&
          other.minPitch == minPitch &&
          other.maxPitch == maxPitch &&
          other.uniquePitchCount == uniquePitchCount;

  @override
  int get hashCode => Object.hash(minPitch, maxPitch, uniquePitchCount);

  @override
  String toString() =>
      'PitchStatistics(min: $minPitch, max: $maxPitch, unique: $uniquePitchCount)';
}

/// MIDI channel statistics over normalized events that carry a channel.
final class ChannelStatistics {
  final Set<int> uniqueChannels;
  final Map<int, int> eventsPerChannel;

  const ChannelStatistics({
    required this.uniqueChannels,
    required this.eventsPerChannel,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChannelStatistics &&
          other.uniqueChannels.length == uniqueChannels.length &&
          other.uniqueChannels.containsAll(uniqueChannels) &&
          other.eventsPerChannel.length == eventsPerChannel.length &&
          other.eventsPerChannel.entries
              .every((e) => eventsPerChannel[e.key] == e.value);

  @override
  int get hashCode => Object.hash(
      Object.hashAll(uniqueChannels), Object.hashAllUnordered(eventsPerChannel.entries));

  @override
  String toString() => 'ChannelStatistics(channels: $uniqueChannels, perChannel: $eventsPerChannel)';
}

/// Inter-event timing statistics over consecutive events in capture order.
///
/// Sequence order is authoritative; deltas are computed but events are never
/// reordered. These are diagnostics only - no musical timing score.
final class TimingStatistics {
  final int? minDeltaMs;
  final int? maxDeltaMs;
  final double? meanDeltaMs;
  final double? medianDeltaMs;
  final int zeroDeltaCount;

  const TimingStatistics({
    required this.minDeltaMs,
    required this.maxDeltaMs,
    required this.meanDeltaMs,
    required this.medianDeltaMs,
    required this.zeroDeltaCount,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimingStatistics &&
          other.minDeltaMs == minDeltaMs &&
          other.maxDeltaMs == maxDeltaMs &&
          other.meanDeltaMs == meanDeltaMs &&
          other.medianDeltaMs == medianDeltaMs &&
          other.zeroDeltaCount == zeroDeltaCount;

  @override
  int get hashCode =>
      Object.hash(minDeltaMs, maxDeltaMs, meanDeltaMs, medianDeltaMs, zeroDeltaCount);

  @override
  String toString() =>
      'TimingStatistics(min: $minDeltaMs, max: $maxDeltaMs, mean: $meanDeltaMs, '
      'median: $medianDeltaMs, zeroDelta: $zeroDeltaCount)';
}

/// Aggregate diagnostic metrics over a set of normalized events.
final class MidiMetricsReport {
  final EventCounts counts;
  final PitchStatistics pitches;
  final ChannelStatistics channels;
  final TimingStatistics timing;

  const MidiMetricsReport({
    required this.counts,
    required this.pitches,
    required this.channels,
    required this.timing,
  });
}

/// Computes deterministic diagnostic metrics over normalized events.
///
/// Deterministic: identical normalized input produces identical output.
/// Pure function over the input; no time, randomness, or global state.
final class MidiDiagnosticMetrics {
  const MidiDiagnosticMetrics();

  MidiMetricsReport compute(Iterable<NormalizedMidiEvent> events) {
    final list = List<NormalizedMidiEvent>.unmodifiable(events);

    var noteOn = 0;
    var noteOff = 0;
    var other = 0;
    int? minPitch;
    int? maxPitch;
    final pitches = <int>{};
    final channels = <int>{};
    final perChannel = <int, int>{};
    final deltas = <int>[];

    for (final event in list) {
      switch (event.type) {
        case NormalizedMidiMessageType.noteOn:
          noteOn += 1;
        case NormalizedMidiMessageType.noteOff:
          noteOff += 1;
        case NormalizedMidiMessageType.other:
          other += 1;
      }

      final pitch = event.pitch;
      if (pitch != null) {
        pitches.add(pitch);
        minPitch = math.min(minPitch ?? pitch, pitch);
        maxPitch = math.max(maxPitch ?? pitch, pitch);
      }

      final channel = event.channel;
      if (channel != null) {
        channels.add(channel);
        perChannel[channel] = (perChannel[channel] ?? 0) + 1;
      }
    }

    for (var i = 1; i < list.length; i++) {
      deltas.add(list[i].sourceAppMonotonicTsMs - list[i - 1].sourceAppMonotonicTsMs);
    }

    return MidiMetricsReport(
      counts: EventCounts(
        total: list.length,
        noteOn: noteOn,
        noteOff: noteOff,
        otherCount: other,
      ),
      pitches: PitchStatistics(
        minPitch: minPitch,
        maxPitch: maxPitch,
        uniquePitchCount: pitches.length,
      ),
      channels: ChannelStatistics(
        uniqueChannels: Set<int>.unmodifiable(channels.toList()..sort()),
        eventsPerChannel: Map<int, int>.unmodifiable(perChannel),
      ),
      timing: _timing(deltas),
    );
  }

  static TimingStatistics _timing(List<int> deltas) {
    if (deltas.isEmpty) {
      return const TimingStatistics(
        minDeltaMs: null,
        maxDeltaMs: null,
        meanDeltaMs: null,
        medianDeltaMs: null,
        zeroDeltaCount: 0,
      );
    }

    final sorted = List<int>.from(deltas)..sort();
    final zero = sorted.where((d) => d == 0).length;
    final sum = sorted.fold<int>(0, (a, b) => a + b);
    final middle = sorted.length ~/ 2;
    final median = sorted.length.isOdd
        ? sorted[middle].toDouble()
        : (sorted[middle - 1] + sorted[middle]) / 2.0;

    return TimingStatistics(
      minDeltaMs: sorted.first,
      maxDeltaMs: sorted.last,
      meanDeltaMs: sum / sorted.length,
      medianDeltaMs: median,
      zeroDeltaCount: zero,
    );
  }
}