import '../domain/normalized_midi_event.dart';
import '../domain/raw_midi_event.dart';

/// Deterministic H2 normalization layer over raw H1 capture.
///
/// The raw capture is immutable and authoritative. This layer derives a
/// normalized representation; it never rewrites, reorders, renumbers,
/// deduplicates, or repairs the source events.
///
/// Rules (MVP, only those justified by locked H1 findings):
///
/// * `note_on_velocity_zero` — status high nibble `0x90`, velocity `0`:
///   derives a normalized Note-Off while the raw event stays `note_on`
///   (raw status `0x90` and raw bytes unchanged).
/// * `note_on` — status high nibble `0x90`, velocity `> 0`.
/// * `note_off` — status high nibble `0x80`.
/// * `other` — any other MIDI message; no invented musical semantics.
///
/// No sustain-pedal, controller, pitch-bend, aftertouch, program-change,
/// clock, or running-status interpretation is performed here.
final class MidiNormalizer {
  const MidiNormalizer();

  static const String ruleNoteOnVelocityZero = 'note_on_velocity_zero';
  static const String ruleNoteOn = 'note_on';
  static const String ruleNoteOff = 'note_off';
  static const String ruleOther = 'other';

  List<NormalizedMidiEvent> normalizeAll(Iterable<RawMidiEvent> events) =>
      events.map(normalize).toList(growable: false);

  NormalizedMidiEvent normalize(RawMidiEvent event) {
    final status = event.rawBytes.isEmpty ? 0 : event.rawBytes.first;
    final high = status & 0xF0;

    final String rule;
    final NormalizedMidiMessageType type;
    switch (high) {
      case 0x90 when event.velocity == 0:
        type = NormalizedMidiMessageType.noteOff;
        rule = ruleNoteOnVelocityZero;
      case 0x90:
        type = NormalizedMidiMessageType.noteOn;
        rule = ruleNoteOn;
      case 0x80:
        type = NormalizedMidiMessageType.noteOff;
        rule = ruleNoteOff;
      default:
        type = NormalizedMidiMessageType.other;
        rule = ruleOther;
    }

    return NormalizedMidiEvent(
      source: event,
      type: type,
      normalizationRule: rule,
    );
  }
}