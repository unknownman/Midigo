import '../domain/expected_musical_target.dart';
import '../domain/expected_note_event.dart';

/// Deterministic builder for the MVP-required expected musical targets.
///
/// Constructs only target FORMS (quality + root + hand + mode). It never
/// generates an Exercise Instance, does not implement the curriculum, and does
/// not build more than the exemplar set (the five forms exercised by H2.5
/// tests). All output is derived purely from the input arguments - no random
/// identifiers, no wall-clock time, no hidden state.
final class ExpectedMusicalTargetFactory {
  /// Interval pattern (semitones) above the root for each quality.
  static const Map<TargetQuality, List<int>> _triadIntervals = <TargetQuality, List<int>>{
    TargetQuality.major: <int>[0, 4, 7],
    TargetQuality.minor: <int>[0, 3, 7],
  };

  /// Rising-one-octave interval pattern used for arpeggio realization.
  static const Map<TargetQuality, List<int>> _octaveIntervals = <TargetQuality, List<int>>{
    TargetQuality.major: <int>[0, 4, 7, 12],
    TargetQuality.minor: <int>[0, 3, 7, 12],
  };

  /// Deterministic inter-group spacing applied to arpeggio onset offsets (ms).
  /// This is expected target structure, not a tolerance and not an evaluator.
  static const int arpeggioStepMs = 250;

  const ExpectedMusicalTargetFactory();

  /// Builds the expected target for the given form.
  ///
  /// * [TargetMode.block] normally realizes one onset group holding every note.
  /// * [TargetMode.arpeggio] realizes one ordered onset group per note with a
  ///   deterministic expected onset offset of `i * arpeggioStepMs`.
  ///
  /// [targetId] defaults to a deterministic derivation from the definition;
  /// callers may supply an explicit identifier instead.
  ExpectedMusicalTarget build({
    required TargetQuality quality,
    required TargetRoot root,
    required TargetHand hand,
    required TargetMode mode,
    String? targetId,
    String modelVersion = '1',
  }) {
    final intervals = mode == TargetMode.block
        ? _triadIntervals[quality]!
        : _octaveIntervals[quality]!;

    final notes = <ExpectedNoteEvent>[
      for (var i = 0; i < intervals.length; i++)
        ExpectedNoteEvent(
          index: i,
          pitch: root.midiPitch + intervals[i],
        ),
    ];

    final List<ExpectedOnsetGroup> groups;
    if (mode == TargetMode.block) {
      groups = <ExpectedOnsetGroup>[
        ExpectedOnsetGroup(
          index: 0,
          memberEventIndices: <int>[for (var i = 0; i < notes.length; i++) i],
          expectedOnsetOffsetMs: 0,
        ),
      ];
    } else {
      groups = <ExpectedOnsetGroup>[
        for (var i = 0; i < notes.length; i++)
          ExpectedOnsetGroup(
            index: i,
            memberEventIndices: <int>[i],
            expectedOnsetOffsetMs: i * arpeggioStepMs,
          ),
      ];
    }

    return ExpectedMusicalTarget(
      targetId: targetId ?? _deriveTargetId(quality, root, hand, mode),
      quality: quality,
      root: root,
      hand: hand,
      mode: mode,
      notes: notes,
      onsetGroups: groups,
      modelVersion: modelVersion,
    );
  }

  /// Deterministic, definition-derived identifier (e.g.
  /// `major-c-rh-block`). Preserves the requested spelling label of the root
  /// (F# vs Bb) as identity metadata while concrete pitches stay numeric.
  static String _deriveTargetId(TargetQuality quality, TargetRoot root,
          TargetHand hand, TargetMode mode) =>
      '${quality.name}-${root.name}-${hand.name}-${mode.name}';
}