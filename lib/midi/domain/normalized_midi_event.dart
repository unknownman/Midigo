import 'raw_midi_event.dart';

/// Derived message type produced by the H2 normalization layer.
///
/// H2 consumes the raw H1 representation and derives semantics. The raw
/// capture remains immutable and authoritative; the normalized type never
/// mutates the source event.
enum NormalizedMidiMessageType {
  noteOn,
  noteOff,
  other;

  String get displayLabel => switch (this) {
        NormalizedMidiMessageType.noteOn => 'NOTE_ON',
        NormalizedMidiMessageType.noteOff => 'NOTE_OFF',
        NormalizedMidiMessageType.other => 'OTHER',
      };
}

/// Immutable derived representation of a raw MIDI event.
///
/// Retains full provenance: the original [source] [RawMidiEvent] can be
/// audited from any normalized event. Derived fields mirror the source so the
/// normalized event is self-describing without exposing mutable byte aliases.
final class NormalizedMidiEvent {
  final RawMidiEvent source;
  final NormalizedMidiMessageType type;
  final String normalizationRule;

  const NormalizedMidiEvent({
    required this.source,
    required this.type,
    required this.normalizationRule,
  });

  String get sessionId => source.sessionId;
  int get sourceSeq => source.seq;
  int get sourceAppMonotonicTsMs => source.appMonotonicTsMs;
  int? get channel => source.channel;
  int? get pitch => source.note;
  int? get velocity => source.velocity;

  /// Raw status byte (first raw byte). `0` when the source has no bytes.
  int get rawStatus => source.rawBytes.isEmpty ? 0 : source.rawBytes.first;

  /// Defensive read-only view over the original raw bytes. The source already
  /// stores an unmodifiable list, so no copy is needed at wrap time.
  List<int> get rawBytes => source.rawBytes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NormalizedMidiEvent &&
          other.type == type &&
          other.normalizationRule == normalizationRule &&
          other.source == source;

  @override
  int get hashCode => Object.hash(type, normalizationRule, source);

  @override
  String toString() =>
      'NormalizedMidiEvent($type session=$sessionId seq=$sourceSeq '
      'rule=$normalizationRule status=0x${rawStatus.toRadixString(16).toUpperCase()})';
}