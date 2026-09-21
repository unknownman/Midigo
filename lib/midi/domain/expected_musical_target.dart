import 'expected_note_event.dart';

/// Which hand(s) the target is intended to be played with.
///
/// [bothUnison] is a single musical realization expected from both hands at
/// once: it does NOT duplicate the semantic note list per hand. Hand identity
/// is represented explicitly rather than by cloning pitches.
enum TargetHand {
  right,
  left,
  bothUnison;

  String get label => switch (this) {
        TargetHand.right => 'RH',
        TargetHand.left => 'LH',
        TargetHand.bothUnison => 'Both-Unison',
      };
}

/// Expected target shape: played as one simultaneous group ([block]) or as an
/// explicitly ordered sequence of onset groups ([arpeggio]).
enum TargetMode {
  block,
  arpeggio;

  String get label => switch (this) {
        TargetMode.block => 'Block',
        TargetMode.arpeggio => 'Arpeggio',
      };
}

/// Expected chord quality. Only the qualities required by the MVP target set.
enum TargetQuality {
  major,
  minor;

  String get label => switch (this) {
        TargetQuality.major => 'Major',
        TargetQuality.minor => 'Minor',
      };
}

/// Expected root pitch, preserving the requested spelling as target metadata.
///
/// The MVP deliberately includes F#/Gb to exercise theoretical-spelling
/// separation: MIDI does not encode whether a pitch was conceptually F# or Gb,
/// so [TargetRoot] keeps the requested spelling for identity purposes while the
/// concrete expected pitches stay strictly numeric and pitch-class based.
/// There is no artificial MIDI-level F#/Gb distinction.
enum TargetRoot {
  c(60, 'C'),
  fSharp(66, 'F#'),
  bFlat(70, 'Bb');

  final int midiPitch;
  final String label;

  const TargetRoot(this.midiPitch, this.label);

  int get pitchClass => midiPitch % 12;
}

/// One expected temporal group of the target.
///
/// This is a neutral, expected grouping constructed by the target builder -
/// it is NEVER derived from the H2.2 diagnostic 60 ms simultaneity window, and
/// it carries no simultaneity pass/fail semantics. Timing is expressed only as
/// an expected absolute onset offset (null = no timing prescribed) with no
/// tolerance. Inter-event interval and duration are derivable whites; no
/// evaluation parameters live here.
final class ExpectedOnsetGroup {
  /// Deterministic zero-based group index.
  final int index;

  /// Ordered member indices into the target's expected note list (unique,
  /// non-empty, and referencing existing notes).
  final List<int> memberEventIndices;

  /// Expected absolute onset offset from target start, in milliseconds.
  /// Null means the target prescribes no timing. No tolerance is stored.
  final int? expectedOnsetOffsetMs;

  ExpectedOnsetGroup({
    required this.index,
    required List<int> memberEventIndices,
    this.expectedOnsetOffsetMs,
  }) : memberEventIndices = List<int>.unmodifiable(memberEventIndices) {
    if (index < 0) {
      throw const FormatException('ExpectedOnsetGroup: index must be >= 0.');
    }
    if (memberEventIndices.isEmpty) {
      throw const FormatException(
          'ExpectedOnsetGroup: memberEventIndices must not be empty.');
    }
    if (expectedOnsetOffsetMs != null && expectedOnsetOffsetMs! < 0) {
      throw const FormatException(
          'ExpectedOnsetGroup: expectedOnsetOffsetMs must be >= 0.');
    }
    final seenMembers = <int>{};
    for (final member in memberEventIndices) {
      if (!seenMembers.add(member)) {
        throw const FormatException(
            'ExpectedOnsetGroup: duplicate member event indices are not '
            'allowed.');
      }
    }
  }

  @override
  String toString() =>
      'ExpectedOnsetGroup($index: $memberEventIndices @ $expectedOnsetOffsetMs ms)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExpectedOnsetGroup &&
          other.index == index &&
          _intListEq(other.memberEventIndices, memberEventIndices) &&
          other.expectedOnsetOffsetMs == expectedOnsetOffsetMs;

  @override
  int get hashCode => Object.hash(index, Object.hashAll(memberEventIndices),
      expectedOnsetOffsetMs);

  Map<String, Object?> toMap() => <String, Object?>{
        'index': index,
        'member_event_indices': memberEventIndices,
        'expected_onset_offset_ms': expectedOnsetOffsetMs,
      };

  factory ExpectedOnsetGroup.fromMap(Map<String, Object?> map) {
    final index = map['index'];
    final members = map['member_event_indices'];
    final offset = map['expected_onset_offset_ms'];
    if (index is! int || members is! List) {
      throw const FormatException(
          'ExpectedOnsetGroup.fromMap: fields must be {int index, '
          'List<int> member_event_indices, int? expected_onset_offset_ms}.');
    }
    int? offsetMs;
    if (offset != null) {
      if (offset is! int) {
        throw const FormatException(
            'ExpectedOnsetGroup.fromMap: expected_onset_offset_ms must be an '
            'int or null.');
      }
      offsetMs = offset;
    }
    final memberList = <int>[];
    for (final member in members) {
      if (member is! int) {
        throw const FormatException(
            'ExpectedOnsetGroup.fromMap: member_event_indices must contain '
            'only ints.');
      }
      memberList.add(member);
    }
    return ExpectedOnsetGroup(
      index: index,
      memberEventIndices: memberList,
      expectedOnsetOffsetMs: offsetMs,
    );
  }
}

/// Immutable, deterministic description of an expected musical target: "what
/// exactly was the learner expected to play?".
///
/// It is NOT an Attempt, a MusicalEvent stream, an Evaluation result, a Mastery
/// state, or an Exercise Instance. No correctness, tolerance, score, or mastery
/// data lives here.
final class ExpectedMusicalTarget {
  /// Deterministic target identity. Either supplied by the caller or derived
  /// purely from the target definition - never random and never time-based.
  final String targetId;

  final TargetQuality quality;
  final TargetRoot root;
  final TargetHand hand;
  final TargetMode mode;

  /// Expected notes in deterministic order (ascending index).
  final List<ExpectedNoteEvent> notes;

  /// Expected onset groups in deterministic order (ascending index).
  final List<ExpectedOnsetGroup> onsetGroups;

  /// Provenance/version metadata for the target definition.
  final String modelVersion;

  ExpectedMusicalTarget({
    required this.targetId,
    required this.quality,
    required this.root,
    required this.hand,
    required this.mode,
    required List<ExpectedNoteEvent> notes,
    required List<ExpectedOnsetGroup> onsetGroups,
    this.modelVersion = '1',
  })  : notes = List<ExpectedNoteEvent>.unmodifiable(notes),
        onsetGroups = List<ExpectedOnsetGroup>.unmodifiable(onsetGroups) {
    if (targetId.isEmpty) {
      throw const FormatException(
          'ExpectedMusicalTarget: targetId must not be empty.');
    }
    if (notes.isEmpty) {
      throw const FormatException(
          'ExpectedMusicalTarget: at least one expected note is required.');
    }
    _validateNoteOrdering();
    _validateMembership();
  }

  void _validateNoteOrdering() {
    var previous = -1;
    final seen = <int>{};
    for (final note in notes) {
      if (note.index <= previous) {
        throw const FormatException(
            'ExpectedMusicalTarget: note indices must be unique and '
            'strictly ascending.');
      }
      if (!seen.add(note.index)) {
        throw const FormatException(
            'ExpectedMusicalTarget: duplicate note index.');
      }
      previous = note.index;
    }
  }

  void _validateMembership() {
    final noteCount = notes.length;
    for (final group in onsetGroups) {
      for (final member in group.memberEventIndices) {
        if (member < 0 || member >= noteCount) {
          throw FormatException(
              'ExpectedMusicalTarget: onset group member index $member is out '
              'of range for $noteCount notes.');
        }
      }
    }
  }

  @override
  String toString() =>
      'ExpectedMusicalTarget($targetId: $quality ${root.label} $hand '
      '${mode.label}, ${notes.length} notes, ${onsetGroups.length} groups)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExpectedMusicalTarget &&
          other.targetId == targetId &&
          other.quality == quality &&
          other.root == root &&
          other.hand == hand &&
          other.mode == mode &&
          other.modelVersion == modelVersion &&
          _noteListEq(other.notes, notes) &&
          _groupListEq(other.onsetGroups, onsetGroups);

  @override
  int get hashCode => Object.hash(targetId, quality, root, hand, mode,
      modelVersion, Object.hashAll(notes), Object.hashAll(onsetGroups));

  Map<String, Object?> toMap() => <String, Object?>{
        'target_id': targetId,
        'quality': quality.name,
        'root': root.name,
        'root_label': root.label,
        'hand': hand.name,
        'mode': mode.name,
        'model_version': modelVersion,
        'notes': notes.map((n) => n.toMap()).toList(growable: false),
        'onset_groups': onsetGroups.map((g) => g.toMap()).toList(growable: false),
      };

  /// Rebuilds from [toMap]. All semantic fields are required; malformed input
  /// fails deterministically with a [FormatException].
  factory ExpectedMusicalTarget.fromMap(Map<String, Object?> map) {
    final targetId = map['target_id'];
    final qualityName = map['quality'];
    final rootName = map['root'];
    final handName = map['hand'];
    final modeName = map['mode'];
    final version = map['model_version'];
    final notesValue = map['notes'];
    final groupsValue = map['onset_groups'];

    if (targetId is! String ||
        qualityName is! String ||
        rootName is! String ||
        handName is! String ||
        modeName is! String ||
        version is! String ||
        notesValue is! List ||
        groupsValue is! List) {
      throw const FormatException(
          'ExpectedMusicalTarget.fromMap: required string/enum/list fields are '
          'missing or malformed.');
    }

    final quality = TargetQuality.values.where((q) => q.name == qualityName);
    final root = TargetRoot.values.where((r) => r.name == rootName);
    final hand = TargetHand.values.where((h) => h.name == handName);
    final mode = TargetMode.values.where((m) => m.name == modeName);
    if (quality.isEmpty || root.isEmpty || hand.isEmpty || mode.isEmpty) {
      throw const FormatException(
          'ExpectedMusicalTarget.fromMap: unknown enum value.');
    }

    final notes = <ExpectedNoteEvent>[];
    for (final noteValue in notesValue) {
      if (noteValue is! Map) {
        throw const FormatException(
            'ExpectedMusicalTarget.fromMap: notes must contain maps.');
      }
      notes.add(ExpectedNoteEvent.fromMap(Map<String, Object?>.from(noteValue)));
    }

    final groups = <ExpectedOnsetGroup>[];
    for (final groupValue in groupsValue) {
      if (groupValue is! Map) {
        throw const FormatException(
            'ExpectedMusicalTarget.fromMap: onset_groups must contain maps.');
      }
      groups.add(
          ExpectedOnsetGroup.fromMap(Map<String, Object?>.from(groupValue)));
    }

    return ExpectedMusicalTarget(
      targetId: targetId,
      quality: quality.single,
      root: root.single,
      hand: hand.single,
      mode: mode.single,
      modelVersion: version,
      notes: notes,
      onsetGroups: groups,
    );
  }
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

bool _noteListEq(List<ExpectedNoteEvent> a, List<ExpectedNoteEvent> b) {
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

bool _groupListEq(List<ExpectedOnsetGroup> a, List<ExpectedOnsetGroup> b) {
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