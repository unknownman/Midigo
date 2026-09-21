import 'normalized_midi_event.dart';

/// Semantic classification of one musical observation.
///
/// H2.4 describes what was observed in the normalized MIDI stream. It never
/// judges correctness, pairing quality, or musical intent.
enum MusicalSemanticType {
  /// A Note-On release was not matched by any Note-Off.
  noteAttack,

  /// A Note-Off (or velocity-zero derived release) with no matching Note-On.
  noteRelease,

  /// A matched Note-On -> Note-Off lifespan (reuses H2.1 pairing verbatim).
  noteLifecycle,

  /// A normalized non-note message (CC, clock, ...). No invented meaning.
  nonNote,

  /// An observed stream anomaly (timestamp/sequence regression, duplicate
  /// sequence number). The anomaly is preserved, never repaired.
  integrityAnomaly;

  String get displayLabel => switch (this) {
        MusicalSemanticType.noteAttack => 'NOTE_ATTACK',
        MusicalSemanticType.noteRelease => 'NOTE_RELEASE',
        MusicalSemanticType.noteLifecycle => 'NOTE_LIFECYCLE',
        MusicalSemanticType.nonNote => 'NON_NOTE',
        MusicalSemanticType.integrityAnomaly => 'INTEGRITY_ANOMALY',
      };
}

/// One deterministic musical interpretation derived from normalized MIDI.
///
/// A semantic event is an interpretation of observed normalized events; it is
/// never a replacement for them. [sources] retains full provenance back to the
/// original [NormalizedMidiEvent] (and through it to the immutable raw event).
/// The interpreter never mutates those sources.
///
/// Ordering is deterministic: within a session events appear in capture
/// sequence order; sessions appear in first-seen order. Identical timestamps
/// preserve source sequence order. Integrity anomalies are surfaced as
/// explicit events; negative durations are retained verbatim.
final class MusicalEvent {
  /// Zero-based deterministic position in the semantic output stream.
  final int eventIndex;

  final String sessionId;
  final MusicalSemanticType type;

  /// Observed onset timestamp (for a lifecycle: the Note-On timestamp).
  final int startTimestampMs;

  /// Observed release timestamp; null when no release was observed.
  final int? endTimestampMs;

  final int? channel;
  final int? pitch;
  final int? velocity;

  /// Matched lifespan duration (`end - start`), retained verbatim even when
  /// negative. Null when no release was observed. Never fabricated.
  final int? durationMs;

  /// For [MusicalSemanticType.integrityAnomaly]: a stable category such as
  /// `sequence_regression`, `timestamp_regression`, or `duplicate_sequence`.
  final String? anomalyCategory;

  /// Source normalized event(s): one for attack/release/non-note/anomaly; two
  /// (Note-On, then Note-Off) for a lifecycle.
  final List<NormalizedMidiEvent> sources;

  MusicalEvent({
    required this.eventIndex,
    required this.sessionId,
    required this.type,
    required this.startTimestampMs,
    this.endTimestampMs,
    this.channel,
    this.pitch,
    this.velocity,
    this.durationMs,
    this.anomalyCategory,
    required List<NormalizedMidiEvent> sources,
  }) : sources = List<NormalizedMidiEvent>.unmodifiable(sources);

  int? get pitchClass => pitch == null ? null : pitch! % 12;

  int? get onsetTimestampMs => startTimestampMs;

  int? get releaseTimestampMs => endTimestampMs;

  /// The normalized Note-On provenance of a [MusicalSemanticType.noteLifecycle]
  /// (otherwise the single source when one exists).
  NormalizedMidiEvent? get sourceOn => sources.isNotEmpty ? sources.first : null;

  /// The normalized Note-Off provenance of a [MusicalSemanticType.noteLifecycle].
  NormalizedMidiEvent? get sourceOff => sources.length > 1 ? sources[1] : null;

  /// Raw status byte of the primary source (identity preserved, not inferred).
  int get statusByte => sources.first.rawStatus;

  /// Stable scalar equality: never compares object identity.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MusicalEvent &&
          other.eventIndex == eventIndex &&
          other.sessionId == sessionId &&
          other.type == type &&
          other.startTimestampMs == startTimestampMs &&
          other.endTimestampMs == endTimestampMs &&
          other.channel == channel &&
          other.pitch == pitch &&
          other.velocity == velocity &&
          other.durationMs == durationMs &&
          other.anomalyCategory == anomalyCategory &&
          _sameSources(other.sources, sources);

  @override
  int get hashCode => Object.hash(eventIndex, sessionId, type, startTimestampMs,
      endTimestampMs, channel, pitch, velocity, durationMs, anomalyCategory,
      Object.hashAll(sources.map(_sourceKey)));

  @override
  String toString() =>
      'MusicalEvent($type idx=$eventIndex sess=$sessionId ts=$startTimestampMs'
      '${endTimestampMs == null ? '' : '->$endTimestampMs'}'
      '${pitch == null ? '' : ' pitch=$pitch'}'
      '${velocity == null ? '' : ' vel=$velocity'}'
      '${durationMs == null ? '' : ' dur=$durationMs'}'
      '${anomalyCategory == null ? '' : ' anomaly=$anomalyCategory'})';

  static bool _sameSources(
      List<NormalizedMidiEvent> a, List<NormalizedMidiEvent> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (_sourceKey(a[i]) != _sourceKey(b[i])) {
        return false;
      }
    }
    return true;
  }

  static (String, int, int, String) _sourceKey(NormalizedMidiEvent event) =>
      (event.sessionId, event.sourceSeq, event.rawStatus, event.normalizationRule);
}