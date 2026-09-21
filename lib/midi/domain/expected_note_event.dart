/// One expected, playable note inside an [ExpectedMusicalTarget].
///
/// H2.5 describes what the learner was expected to play; it never states
/// whether they played it correctly. Evaluation-specific fields (velocity,
/// tolerance, scores) are deliberately excluded unless a later contract
/// explicitly requires them.
///
/// MIDI [pitch] is the authoritative representation of the concrete playable
/// target. Theoretical spelling (C# vs Db, note names, octave identity) is not
/// inferred from the numeric value.
final class ExpectedNoteEvent {
  /// Deterministic zero-based index of this note within its target.
  final int index;

  /// MIDI pitch (0..127), the authoritative observed/expected representation.
  final int pitch;

  /// Optional MIDI channel, present only when target semantics require it.
  /// The default target has no channel semantics and leaves this null.
  final int? channel;

  ExpectedNoteEvent({
    required this.index,
    required this.pitch,
    this.channel,
  }) {
    if (index < 0) {
      throw const FormatException('ExpectedNoteEvent: index must be >= 0.');
    }
    if (pitch < 0 || pitch > 127) {
      throw const FormatException('ExpectedNoteEvent: pitch must be in 0..127.');
    }
    if (channel != null && (channel! < 0 || channel! > 15)) {
      throw const FormatException('ExpectedNoteEvent: channel must be in 0..15.');
    }
  }

  /// Pitch class (`pitch % 12`). Mathematically derived; no spelling implied.
  int get pitchClass => pitch % 12;

  /// `index: pitch 60`.
  @override
  String toString() => 'ExpectedNoteEvent($index: $pitch)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExpectedNoteEvent &&
          other.index == index &&
          other.pitch == pitch &&
          other.channel == channel;

  @override
  int get hashCode => Object.hash(index, pitch, channel);

  Map<String, Object?> toMap() => <String, Object?>{
        'index': index,
        'pitch': pitch,
        'channel': channel,
      };

  /// Rebuilds from [toMap]. Malformed or missing fields fail deterministically
  /// with a [FormatException]; no defaults are invented.
  factory ExpectedNoteEvent.fromMap(Map<String, Object?> map) {
    final index = map['index'];
    final pitch = map['pitch'];
    final channel = map['channel'];
    if (index is! int || pitch is! int) {
      throw const FormatException(
          'ExpectedNoteEvent.fromMap: fields must be {int index, int pitch, '
          'int? channel}.');
    }
    int? channelValue;
    if (channel != null) {
      if (channel is! int) {
        throw const FormatException(
            'ExpectedNoteEvent.fromMap: channel must be an int or null.');
      }
      channelValue = channel;
    }
    return ExpectedNoteEvent(index: index, pitch: pitch, channel: channelValue);
  }
}