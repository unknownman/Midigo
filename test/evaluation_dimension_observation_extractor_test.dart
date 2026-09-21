import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/midi/application/evaluation_dimension_observation_extractor.dart';
import 'package:miditutor/midi/application/expected_musical_target_factory.dart';
import 'package:miditutor/midi/application/midi_normalizer.dart';
import 'package:miditutor/midi/application/musical_event_interpreter.dart';
import 'package:miditutor/midi/application/structural_aligner.dart';
import 'package:miditutor/midi/domain/evaluation_dimension_observations.dart';
import 'package:miditutor/midi/domain/expected_musical_target.dart';
import 'package:miditutor/midi/domain/expected_note_event.dart';
import 'package:miditutor/midi/domain/musical_event.dart';
import 'package:miditutor/midi/domain/normalized_midi_event.dart';
import 'package:miditutor/midi/domain/raw_midi_event.dart';

const _session = 'h27-session';
const _otherSession = 'h27-other-session';

String _project(EvaluationDimensionObservations o) => jsonEncode(o.toMap());

/// Spec T19 forbidden evaluation concepts, substring-matched against output keys.
const _forbiddenTokens = <String>[
  'correct',
  'incorrect',
  'pass',
  'fail',
  'score',
  'grade',
  'tolerance',
  'error',
  'vector',
  'mastery',
  'evidence',
  'priority',
  'interval',
];

/// Words forbidden inside the semantic meaning of observations. Whole-word
/// matched against string values only.
const _nonGoalSemanticWords = <String>[
  'correct',
  'incorrect',
  'pass',
  'fail',
  'good',
  'bad',
  'late',
  'early',
  'wrong',
  'missed',
  'extra',
];

Set<String> _collectKeys(Object? value, Set<String> into) {
  if (value is Map) {
    for (final entry in value.entries) {
      into.add(entry.key.toString().toLowerCase());
      _collectKeys(entry.value, into);
    }
  } else if (value is List) {
    for (final item in value) {
      _collectKeys(item, into);
    }
  }
  return into;
}

List<String> _collectStringValues(Object? value, List<String> into) {
  if (value is Map) {
    for (final entry in value.entries) {
      _collectStringValues(entry.value, into);
    }
  } else if (value is List) {
    for (final item in value) {
      _collectStringValues(item, into);
    }
  } else if (value is String) {
    into.add(value.toLowerCase());
  }
  return into;
}

NormalizedMidiEvent _norm(int seq, int ts, int? note,
        {String session = _session, String kind = 'on'}) =>
    NormalizedMidiEvent(
      source: RawMidiEvent(
        sessionId: session,
        deviceId: 'dev',
        connectionType: 'USB',
        seq: seq,
        appMonotonicTsMs: ts,
        messageType: switch (kind) {
          'off' => RawMidiMessageType.noteOff,
          'other' => RawMidiMessageType.other,
          _ => RawMidiMessageType.noteOn,
        },
        channel: 0,
        note: note,
        velocity: 90,
        rawBytes: <int>[0x90, note ?? 0, 90],
      ),
      type: switch (kind) {
        'off' => NormalizedMidiMessageType.noteOff,
        'other' => NormalizedMidiMessageType.other,
        _ => NormalizedMidiMessageType.noteOn,
      },
      normalizationRule: 'verbatim',
    );

MusicalEvent _lifecycle(int idx, int ts, int pitch,
        {String session = _session}) =>
    MusicalEvent(
      eventIndex: idx,
      sessionId: session,
      type: MusicalSemanticType.noteLifecycle,
      startTimestampMs: ts,
      endTimestampMs: ts + 100,
      channel: 0,
      pitch: pitch,
      velocity: 90,
      durationMs: 100,
      sources: <NormalizedMidiEvent>[
        _norm(idx, ts, pitch, session: session),
        _norm(idx, ts + 100, pitch, session: session, kind: 'off'),
      ],
    );

MusicalEvent _attack(int idx, int ts, int pitch, {String session = _session}) =>
    MusicalEvent(
      eventIndex: idx,
      sessionId: session,
      type: MusicalSemanticType.noteAttack,
      startTimestampMs: ts,
      channel: 0,
      pitch: pitch,
      velocity: 90,
      sources: <NormalizedMidiEvent>[_norm(idx, ts, pitch, session: session)],
    );

MusicalEvent _release(int idx, int ts, int pitch, {String session = _session}) =>
    MusicalEvent(
      eventIndex: idx,
      sessionId: session,
      type: MusicalSemanticType.noteRelease,
      startTimestampMs: ts,
      channel: 0,
      pitch: pitch,
      sources: <NormalizedMidiEvent>[
        _norm(idx, ts, pitch, session: session, kind: 'off'),
      ],
    );

MusicalEvent _nonNote(int idx, int ts, {String session = _session}) =>
    MusicalEvent(
      eventIndex: idx,
      sessionId: session,
      type: MusicalSemanticType.nonNote,
      startTimestampMs: ts,
      sources: <NormalizedMidiEvent>[
        _norm(idx, ts, null, session: session, kind: 'other'),
      ],
    );

MusicalEvent _anomaly(int idx, int ts, String category,
        {String session = _session}) =>
    MusicalEvent(
      eventIndex: idx,
      sessionId: session,
      type: MusicalSemanticType.integrityAnomaly,
      startTimestampMs: ts,
      channel: 0,
      pitch: 60,
      anomalyCategory: category,
      sources: <NormalizedMidiEvent>[_norm(idx, ts, 60, session: session)],
    );

ExpectedMusicalTarget _blockTarget(List<int> pitches,
        {String targetId = 't-block'}) =>
    ExpectedMusicalTarget(
      targetId: targetId,
      quality: TargetQuality.major,
      root: TargetRoot.c,
      hand: TargetHand.right,
      mode: TargetMode.block,
      notes: <ExpectedNoteEvent>[
        for (var i = 0; i < pitches.length; i++)
          ExpectedNoteEvent(index: i, pitch: pitches[i]),
      ],
      onsetGroups: <ExpectedOnsetGroup>[
        ExpectedOnsetGroup(
          index: 0,
          memberEventIndices: <int>[for (var i = 0; i < pitches.length; i++) i],
          expectedOnsetOffsetMs: 0,
        ),
      ],
    );

EvaluationDimensionObservations _extract(ExpectedMusicalTarget target,
        List<MusicalEvent> observed, {String session = _session}) =>
    const EvaluationDimensionObservationExtractor().extract(
      target: target,
      observed: observed,
      alignment: const StructuralAligner()
          .align(target: target, sessionId: session, observed: observed),
    );

void main() {
  const factory = ExpectedMusicalTargetFactory();

  group('T1 - exact block', () {
    test('pitch/timing/simultaneity available; order/ioi not applicable', () {
      final target = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.block);
      final result = _extract(
        target,
        <MusicalEvent>[
          _lifecycle(0, 1000, 60),
          _lifecycle(1, 1002, 64),
          _lifecycle(2, 1004, 67),
        ],
      );

      expect(result.pitch.availability, ObservationAvailability.available);
      expect(result.pitch.observations, hasLength(3));
      expect(
          result.pitch.observations.every(
              (o) => o.associationState == AssociationState.associated),
          isTrue);
      expect(result.pitch.observations.map((o) => o.expectedPitch),
          <int?>[60, 64, 67]);
      expect(result.pitch.observations.map((o) => o.observedPitch),
          <int?>[60, 64, 67]);

      expect(result.timing.availability, ObservationAvailability.available);
      expect(result.timing.observations, hasLength(3));
      expect(result.timing.observations.map((o) => o.expectedOnsetOffsetMs),
          <int?>[0, 0, 0]);
      expect(
          result.timing.observations.map((o) => o.observedOnsetTimestampMs),
          <int?>[1000, 1002, 1004]);

      expect(result.simultaneity.availability, ObservationAvailability.available);
      expect(result.simultaneity.groups, hasLength(1));
      final group = result.simultaneity.groups.single;
      expect(group.expectedGroupIndex, 0);
      expect(group.expectedMemberIndices, <int>[0, 1, 2]);
      expect(group.observedAssociatedEventIndices, <int>[0, 1, 2]);
      expect(group.observedOnsetTimestampsMs, <int>[1000, 1002, 1004]);
      expect(group.observedSpanMs, 4);
      expect(group.unmatchedExpectedMemberIndices, isEmpty);

      expect(result.order.availability, ObservationAvailability.notApplicable);
      expect(result.ioi.availability, ObservationAvailability.notApplicable);
      expect(result.retrievalLatency.availability,
          ObservationAvailability.unavailable);
    });
  });

  group('T2 - block missing expected', () {
    test('E4 exposed as EXPECTED_UNMATCHED, never renamed', () {
      final target = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.block);
      final result = _extract(
        target,
        <MusicalEvent>[_lifecycle(0, 1000, 60), _lifecycle(1, 1002, 67)],
      );

      final unmatched = result.pitch.observations
          .where((o) => o.associationState == AssociationState.expectedUnmatched);
      expect(unmatched, hasLength(1));
      expect(unmatched.single.expectedNoteIndex, 1);
      expect(unmatched.single.expectedPitch, 64);
      expect(unmatched.single.observedEventIndex, isNull);
      expect(unmatched.single.observedPitch, isNull);

      final timing = result.timing.observations
          .where((o) => o.associationState == AssociationState.expectedUnmatched);
      expect(timing.single.expectedOnsetOffsetMs, 0);
      expect(timing.single.observedOnsetTimestampMs, isNull);

      expect(result.simultaneity.groups.single.unmatchedExpectedMemberIndices,
          <int>[1]);
    });
  });

  group('T3 - block extra observed', () {
    test('D4 exposed as OBSERVED_UNMATCHED', () {
      final target = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.block);
      final result = _extract(
        target,
        <MusicalEvent>[
          _lifecycle(0, 1000, 60),
          _lifecycle(1, 1002, 64),
          _lifecycle(2, 1004, 67),
          _lifecycle(3, 1006, 62),
        ],
      );

      final unmatched = result.pitch.observations
          .where((o) => o.associationState == AssociationState.observedUnmatched);
      expect(unmatched, hasLength(1));
      expect(unmatched.single.observedEventIndex, 3);
      expect(unmatched.single.observedPitch, 62);
      expect(unmatched.single.expectedNoteIndex, isNull);

      final timing = result.timing.observations
          .where((o) => o.associationState == AssociationState.observedUnmatched);
      expect(timing.single.observedOnsetTimestampMs, 1006);
      expect(timing.single.expectedNoteIndex, isNull);
    });
  });

  group('T4 - exact arpeggio', () {
    test('pitch/order/ioi available; simultaneity not applicable', () {
      final target = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.arpeggio);
      final result = _extract(
        target,
        <MusicalEvent>[
          _lifecycle(0, 1000, 60),
          _lifecycle(1, 1250, 64),
          _lifecycle(2, 1500, 67),
          _lifecycle(3, 1750, 72),
        ],
      );

      expect(target.notes.map((n) => n.pitch), <int>[60, 64, 67, 72]);

      expect(result.pitch.availability, ObservationAvailability.available);
      expect(result.pitch.observations, hasLength(4));

      expect(result.order.availability, ObservationAvailability.available);
      expect(result.order.order.expectedOrder.map((e) => e.index), <int>[0, 1, 2, 3]);
      expect(result.order.order.expectedOrder.map((e) => e.pitch),
          <int>[60, 64, 67, 72]);
      expect(result.order.order.expectedOrder.map((e) => e.sequencePosition),
          <int>[0, 1, 2, 3]);
      expect(result.order.order.observedOrder.map((e) => e.index), <int>[0, 1, 2, 3]);
      expect(result.order.order.associatedPairs, hasLength(4));
      expect(result.order.order.associatedPairs
          .map((p) => p.observedSequencePosition), <int>[0, 1, 2, 3]);

      expect(result.ioi.availability, ObservationAvailability.available);
      expect(result.ioi.expected.map((e) => e.ioiMs), <int?>[250, 250, 250]);
      expect(result.ioi.observed.map((e) => e.ioiMs), <int?>[250, 250, 250]);

      expect(result.simultaneity.availability,
          ObservationAvailability.notApplicable);
    });
  });

  group('T5 - reordered arpeggio', () {
    test('observed sequence preserved; no order verdict produced', () {
      final target = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.arpeggio);
      final reordered = _extract(
        target,
        <MusicalEvent>[
          _lifecycle(0, 1000, 60),
          _lifecycle(1, 1250, 67),
          _lifecycle(2, 1500, 64),
          _lifecycle(3, 1750, 72),
        ],
      );

      // Observed order stays exactly as captured.
      expect(reordered.order.order.observedOrder.map((e) => e.index),
          <int>[0, 1, 2, 3]);
      expect(reordered.order.order.observedOrder.map((e) => e.pitch),
          <int>[60, 67, 64, 72]);
      expect(reordered.order.order.associatedPairs, hasLength(4));
      expect(reordered.order.order.associatedPairs
          .map((p) => p.expectedNoteIndex), <int>[0, 1, 2, 3]);
      expect(reordered.order.order.associatedPairs
          .map((p) => p.observedEventIndex), <int>[0, 2, 1, 3]);
      expect(reordered.order.order.associatedPairs
          .map((p) => p.observedSequencePosition), <int>[0, 2, 1, 3]);

      // No order verdict anywhere in the projection.
      final keys = _collectKeys(reordered.toMap(), <String>{});
      expect(keys.contains('order_verdict'), isFalse);
      expect(keys.contains('order_correct'), isFalse);
      expect(keys.contains('order_incorrect'), isFalse);

      for (final pair in reordered.order.order.associatedPairs) {
        expect(pair.expectedPitch,
            <int>[60, 64, 67, 72][pair.expectedSequencePosition]);
      }
    });
  });

  group('T6 - timing projection', () {
    test('raw expected offsets and observed timestamps preserved exactly', () {
      final block = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.block);
      final arpeggio = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.arpeggio);

      final blockResult = _extract(
        block,
        <MusicalEvent>[
          _lifecycle(0, 1000, 60),
          _lifecycle(1, 1002, 64),
          _lifecycle(2, 1004, 67),
        ],
      );
      final arpResult = _extract(
        arpeggio,
        <MusicalEvent>[
          _lifecycle(0, 1000, 60),
          _lifecycle(1, 1240, 64),
          _lifecycle(2, 1500, 67),
          _lifecycle(3, 1780, 72),
        ],
      );

      expect(blockResult.timing.observations.map((o) => o.expectedOnsetOffsetMs),
          <int?>[0, 0, 0]);
      expect(arpResult.timing.observations.map((o) => o.expectedOnsetOffsetMs),
          <int?>[0, 250, 500, 750]);
      expect(arpResult.timing.observations.map((o) => o.observedOnsetTimestampMs),
          <int?>[1000, 1240, 1500, 1780]);

      // Arbitrary offsets/timestamps are preserved verbatim - never judged.
      final keys = _collectKeys(arpResult.toMap(), <String>{});
      expect(keys.any((k) => k.contains('tolerance')), isFalse);
      expect(keys.any((k) => k.contains('threshold')), isFalse);
    });
  });

  group('T7 - simultaneity projection', () {
    test('raw group membership, timestamps, and span exposed unclassified', () {
      final target = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.block);
      final result = _extract(
        target,
        <MusicalEvent>[
          _lifecycle(0, 1000, 60),
          _lifecycle(1, 1047, 64),
          _lifecycle(2, 1090, 67),
        ],
      );

      final group = result.simultaneity.groups.single;
      expect(group.expectedOnsetOffsetMs, 0);
      expect(group.expectedMemberIndices, <int>[0, 1, 2]);
      expect(group.expectedMemberPitches, <int>[60, 64, 67]);
      expect(group.observedAssociatedEventIndices, <int>[0, 1, 2]);
      expect(group.observedOnsetTimestampsMs, <int>[1000, 1047, 1090]);
      expect(group.minObservedOnsetMs, 1000);
      expect(group.maxObservedOnsetMs, 1090);
      expect(group.observedSpanMs, 90);
      expect(group.unmatchedExpectedMemberIndices, isEmpty);

      final keys = _collectKeys(result.toMap(), <String>{});
      expect(keys.any((k) => k.contains('simultaneous')), isFalse);
    });
  });

  group('T8 - ioi projection', () {
    test('expected and observed intervals exposed as raw quantities', () {
      final target = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.arpeggio);
      final result = _extract(
        target,
        <MusicalEvent>[
          _lifecycle(0, 1000, 60),
          _lifecycle(1, 1300, 64),
          _lifecycle(2, 1450, 67),
          _lifecycle(3, 1800, 72),
        ],
      );

      expect(result.ioi.expected.map((e) => e.fromEventIndex), <int>[0, 1, 2]);
      expect(result.ioi.expected.map((e) => e.toEventIndex), <int>[1, 2, 3]);
      expect(result.ioi.expected.map((e) => e.ioiMs), <int?>[250, 250, 250]);

      expect(result.ioi.observed.map((e) => e.fromEventIndex), <int>[0, 1, 2]);
      expect(result.ioi.observed.map((e) => e.toEventIndex), <int>[1, 2, 3]);
      expect(result.ioi.observed.map((e) => e.ioiMs), <int?>[300, 150, 350]);

      final keys = _collectKeys(result.toMap(), <String>{});
      expect(keys.any((k) => k.contains('ioi_error')), isFalse);
      expect(keys.any((k) => k.contains('too_fast')), isFalse);
      expect(keys.any((k) => k.contains('too_slow')), isFalse);
    });
  });

  group('T9 - retrieval latency unavailable', () {
    test('no anchor, no fabricated ready timestamp', () {
      final target = _blockTarget(<int>[60, 64, 67]);
      final result = _extract(
        target,
        <MusicalEvent>[
          _lifecycle(0, 1000, 60),
          _lifecycle(1, 1002, 64),
          _lifecycle(2, 1004, 67),
        ],
      );

      expect(result.retrievalLatency.availability, ObservationAvailability.unavailable);
      expect(result.retrievalLatency.reason,
          EvaluationDimensionObservationExtractor.retrievalLatencyUnavailableReason);
      expect(result.retrievalLatency.performanceAnchorTimestampMs, isNull);
      expect(result.retrievalLatency.performanceAnchorContext, isNull);
      expect(result.retrievalLatency.latencyDurationMs, isNull);
      // Raw observed data is still exposed; it is not an anchor.
      expect(result.retrievalLatency.firstObservedNoteEventIndex, 0);
      expect(result.retrievalLatency.firstObservedNoteTimestampMs, 1000);
    });
  });

  group('T10 - no valid anchor in frozen models', () {
    test('session start / first event are never used as ready timestamps', () {
      final target = _blockTarget(<int>[60, 64, 67]);
      final result = _extract(
        target,
        <MusicalEvent>[
          _lifecycle(0, 1000, 60),
          _lifecycle(1, 1002, 64),
          _lifecycle(2, 1004, 67),
        ],
      );

      // The first event's timestamp (1000) must NOT be reinterpreted as a
      // ready/anchor timestamp. UNAVAILABLE remains.
      expect(result.retrievalLatency.performanceAnchorTimestampMs, isNull);
      expect(result.retrievalLatency.performanceAnchorContext, isNull);
      expect(result.retrievalLatency.latencyDurationMs, isNull);
      expect(result.retrievalLatency.availability, ObservationAvailability.unavailable);
    });
  });

  group('T11 - unmatched note-on', () {
    test('attack with no release remains structurally associated', () {
      final target = _blockTarget(<int>[60]);
      final result = _extract(
        target,
        <MusicalEvent>[_attack(0, 1000, 60)],
      );

      expect(result.pitch.observations.single.associationState,
          AssociationState.associated);
      expect(result.pitch.observations.single.observedType,
          MusicalSemanticType.noteAttack);
      expect(result.pitch.observations.single.observedPitch, 60);
      expect(result.timing.observations, hasLength(1));
    });
  });

  group('T12 - unmatched note-off', () {
    test('release never becomes a pitch/timing observation', () {
      final target = _blockTarget(<int>[60]);
      final result = _extract(
        target,
        <MusicalEvent>[_release(0, 1000, 60)],
      );

      expect(result.pitch.observations, hasLength(1));
      expect(result.pitch.observations.single.associationState,
          AssociationState.expectedUnmatched);
      expect(result.pitch.observations.single.observedEventIndex, isNull);
      expect(result.timing.observations, hasLength(1));
      expect(result.timing.observations.single.observedEventIndex, isNull);
      expect(result.ignoredNonNoteEventRefs, isEmpty);
      expect(result.ignoredIntegrityAnomalyEventRefs, isEmpty);
    });
  });

  group('T13 - non-note events', () {
    test('control changes never become musical dimension observations', () {
      final target = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.block);
      final result = _extract(
        target,
        <MusicalEvent>[
          _lifecycle(0, 1000, 60),
          _nonNote(1, 1002),
          _lifecycle(2, 1004, 64),
          _nonNote(3, 1006),
          _lifecycle(4, 1008, 67),
        ],
      );

      expect(result.pitch.observations, hasLength(3));
      expect(result.pitch.observations.map((o) => o.observedEventIndex),
          <int?>[0, 2, 4]);
      expect(result.ignoredNonNoteEventRefs, <int>[1, 3]);
    });
  });

  group('T14 - integrity anomaly', () {
    test('anomaly provenance preserved; never converted into a verdict', () {
      final target = _blockTarget(<int>[60]);
      final result = _extract(
        target,
        <MusicalEvent>[
          _anomaly(0, 990, 'duplicate_sequence'),
          _lifecycle(1, 1000, 60),
          _anomaly(2, 1010, 'timestamp_regression'),
        ],
      );

      expect(result.pitch.observations, hasLength(1));
      expect(result.pitch.observations.single.observedEventIndex, 1);
      expect(result.ignoredIntegrityAnomalyEventRefs, <int>[0, 2]);
      final keys = _collectKeys(result.toMap(), <String>{});
      expect(keys.any((k) => k.contains('anomaly') && k.contains('error')), isFalse);
    });
  });

  group('T15 - multiple sessions', () {
    test('only the selected session contributes observations', () {
      final target = _blockTarget(<int>[60]);
      final observed = <MusicalEvent>[
        _lifecycle(0, 1000, 60, session: _session),
        _lifecycle(1, 1000, 60, session: _otherSession),
      ];
      final result = _extract(target, observed);

      expect(result.sessionId, _session);
      expect(result.pitch.observations, hasLength(1));
      expect(result.pitch.observations.single.observedEventIndex, 0);
      expect(result.ignoredOtherSessionEventRefs, <int>[1]);
    });
  });

  group('T16 - determinism', () {
    test('identical input yields identical stable projection', () {
      final target = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.arpeggio);
      final observed = <MusicalEvent>[
        _lifecycle(0, 1000, 60),
        _lifecycle(1, 1250, 64),
        _lifecycle(2, 1500, 67),
        _lifecycle(3, 1750, 72),
      ];
      final first = _extract(target, observed);
      final second = _extract(target, observed);

      expect(identical(first, second), isFalse);
      expect(_project(second), _project(first));
      expect(second, equals(first));
      expect(second.hashCode, first.hashCode);
    });
  });

  group('T17 - immutability and integrity', () {
    test('inputs unchanged; output collections unmodifiable', () {
      final target = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.block);
      final observed = List<MusicalEvent>.of(<MusicalEvent>[
        _lifecycle(0, 1000, 60),
        _lifecycle(1, 1002, 64),
        _lifecycle(2, 1004, 67),
      ]);
      final before = observed.map((e) => e.eventIndex).toList(growable: false);

      final result = _extract(target, observed);

      expect(observed.map((e) => e.eventIndex).toList(), before);
      expect(target.notes, hasLength(3));
      expect(() => result.pitch.observations.add(result.pitch.observations.first),
          throwsUnsupportedError);
      expect(() => result.timing.observations.add(result.timing.observations.first),
          throwsUnsupportedError);
      expect(() => result.simultaneity.groups.add(result.simultaneity.groups.first),
          throwsUnsupportedError);
      expect(() => result.ioi.expected.add(
              IoiEntry(fromEventIndex: 0, toEventIndex: 1, ioiMs: null)),
          throwsUnsupportedError);
      expect(() => result.ioi.observed.add(
              IoiEntry(fromEventIndex: 0, toEventIndex: 1, ioiMs: null)),
          throwsUnsupportedError);
      expect(() => result.ignoredNonNoteEventRefs.add(0), throwsUnsupportedError);
    });

    test('mismatched alignment/target or duplicate indices rejected', () {
      final targetA = _blockTarget(<int>[60, 64, 67], );
      final targetB = _blockTarget(<int>[62, 65, 66], targetId: 't-block-b');
      final observed = <MusicalEvent>[
        _lifecycle(0, 1000, 60),
        _lifecycle(1, 1002, 64),
        _lifecycle(2, 1004, 67),
      ];
      final alignmentA = const StructuralAligner()
          .align(target: targetA, sessionId: _session, observed: observed);

      expect(
          () => const EvaluationDimensionObservationExtractor().extract(
                target: targetB,
                observed: observed,
                alignment: alignmentA,
              ),
          throwsFormatException);

      final duplicated = <MusicalEvent>[
        _lifecycle(0, 1000, 60),
        _lifecycle(0, 1002, 64),
        _lifecycle(1, 1004, 67),
      ];
      expect(
          () => const EvaluationDimensionObservationExtractor().extract(
                target: targetA,
                observed: duplicated,
                alignment: alignmentA,
              ),
          throwsFormatException);
    });
  });

  group('T18 - block vs arpeggio applicability', () {
    test('block: order/ioi N/A, simultaneity available', () {
      final block = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.block);
      final result = _extract(
        block,
        <MusicalEvent>[
          _lifecycle(0, 1000, 60),
          _lifecycle(1, 1002, 64),
          _lifecycle(2, 1004, 67),
        ],
      );

      expect(result.order.availability, ObservationAvailability.notApplicable);
      expect(result.ioi.availability, ObservationAvailability.notApplicable);
      expect(result.simultaneity.availability, ObservationAvailability.available);
      expect(result.pitch.availability, ObservationAvailability.available);
      expect(result.timing.availability, ObservationAvailability.available);
    });

  test('arpeggio: simultaneity N/A, order and ioi available', () {
      final arpeggio = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.arpeggio);
      final result = _extract(
        arpeggio,
        <MusicalEvent>[
          _lifecycle(0, 1000, 60),
          _lifecycle(1, 1250, 64),
          _lifecycle(2, 1500, 67),
          _lifecycle(3, 1750, 72),
        ],
      );

      expect(result.simultaneity.availability, ObservationAvailability.notApplicable);
      expect(result.order.availability, ObservationAvailability.available);
      expect(result.ioi.availability, ObservationAvailability.available);
    });
  });

  group('T19 - no evaluation leakage', () {
    test('recursive key scan finds no forbidden concepts', () {
      final block = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.block);
      final arpeggio = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.arpeggio);

      final results = <EvaluationDimensionObservations>[
        _extract(
          block,
          <MusicalEvent>[
            _anomaly(0, 990, 'duplicate_sequence'),
            _lifecycle(1, 1000, 60),
            _nonNote(2, 1002),
            _lifecycle(3, 1004, 64),
          ],
        ),
        _extract(
          arpeggio,
          <MusicalEvent>[
            _lifecycle(0, 1000, 60),
            _lifecycle(1, 1250, 64),
            _lifecycle(2, 1500, 67),
            _lifecycle(3, 1750, 72),
          ],
        ),
      ];

      for (final result in results) {
        final keys = _collectKeys(result.toMap(), <String>{});
        for (final key in keys) {
          for (final token in _forbiddenTokens) {
            expect(key.contains(token), isFalse,
                reason: 'key "$key" must not leak "$token"');
          }
        }
        for (final value in _collectStringValues(result.toMap(), <String>[])) {
          for (final word in _nonGoalSemanticWords) {
            expect(
                RegExp('(^|[^a-z])$word([^a-z]|\$)')
                    .hasMatch(value.toLowerCase()),
                isFalse,
                reason: 'value "$value" must not use semantic word $word');
          }
        }
      }
    });
  });

  group('H2.4/H2.5/H2.6 integration', () {
    test('full pipeline: target, interpreter, alignment, extraction', () {
      final target = factory.build(
          quality: TargetQuality.major,
          root: TargetRoot.c,
          hand: TargetHand.right,
          mode: TargetMode.block);

      final raw = <RawMidiEvent>[
        _rawOn(0, 1000, 60),
        _rawOn(1, 1003, 64),
        _rawOn(2, 1007, 67),
        _rawOff(3, 1100, 60),
        _rawOff(4, 1103, 64),
        _rawOff(5, 1107, 67),
      ];
      final observed = const MusicalEventInterpreter()
          .interpret(const MidiNormalizer().normalizeAll(raw));

      final alignment = const StructuralAligner().align(
          target: target, sessionId: _session, observed: observed);
      final result = const EvaluationDimensionObservationExtractor().extract(
          target: target, observed: observed, alignment: alignment);

      expect(result.targetId, target.targetId);
      expect(result.pitch.observations, hasLength(3));
      expect(result.pitch.observations.every(
          (o) => o.associationState == AssociationState.associated), isTrue);
      expect(result.timing.observations, hasLength(3));
      expect(result.simultaneity.groups.single.observedSpanMs, 7);
      expect(result.retrievalLatency.availability,
          ObservationAvailability.unavailable);
    });
  });
}

RawMidiEvent _rawOn(int seq, int ts, int pitch) => RawMidiEvent(
      sessionId: _session,
      deviceId: 'device',
      connectionType: 'USB',
      seq: seq,
      appMonotonicTsMs: ts,
      messageType: RawMidiMessageType.noteOn,
      channel: 0,
      note: pitch,
      velocity: 90,
      rawBytes: <int>[0x90, pitch, 90],
    );

RawMidiEvent _rawOff(int seq, int ts, int pitch) => RawMidiEvent(
      sessionId: _session,
      deviceId: 'device',
      connectionType: 'USB',
      seq: seq,
      appMonotonicTsMs: ts,
      messageType: RawMidiMessageType.noteOff,
      channel: 0,
      note: pitch,
      velocity: 0,
      rawBytes: <int>[0x80, pitch, 0],
    );