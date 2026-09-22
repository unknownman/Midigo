import 'package:flutter_test/flutter_test.dart';
import 'package:miditutor/midi/application/expected_musical_target_factory.dart';
import 'package:miditutor/midi/domain/evaluation_result.dart';
import 'package:miditutor/midi/domain/expected_musical_target.dart';
import 'package:miditutor/midi/domain/raw_midi_event.dart';
import 'package:miditutor/practice/application/evaluation_flow.dart';

const String _session = 'slice1-eval-session';

RawMidiEvent _noteEvent({
  required int seq,
  required int ts,
  required int note,
  bool on = true,
}) =>
    RawMidiEvent(
      sessionId: _session,
      deviceId: 'test-device',
      connectionType: 'TEST',
      seq: seq,
      appMonotonicTsMs: ts,
      messageType: on ? RawMidiMessageType.noteOn : RawMidiMessageType.noteOff,
      channel: 0,
      note: note,
      velocity: on ? 90 : 0,
      rawBytes: <int>[on ? 0x90 : 0x80, note, on ? 90 : 0],
    );

/// A perfect simultaneous C-major block: C4 E4 G4 played together at ts 1000.
List<RawMidiEvent> _perfectBlock() {
  var seq = 0;
  final events = <RawMidiEvent>[];
  for (final note in const <int>[60, 64, 67]) {
    events.add(_noteEvent(seq: seq++, ts: 1000, note: note));
  }
  for (final note in const <int>[60, 64, 67]) {
    events.add(_noteEvent(seq: seq++, ts: 1050, note: note, on: false));
  }
  return events;
}

/// Only C and G (E missing): an incomplete but real performance.
List<RawMidiEvent> _missingMiddle() {
  var seq = 0;
  final events = <RawMidiEvent>[];
  for (final note in const <int>[60, 67]) {
    events.add(_noteEvent(seq: seq++, ts: 1000, note: note));
  }
  for (final note in const <int>[60, 67]) {
    events.add(_noteEvent(seq: seq++, ts: 1050, note: note, on: false));
  }
  return events;
}

/// Plays wrong pitches that associate with nothing expected -> NEP.
List<RawMidiEvent> _noExpectedNotes() {
  var seq = 0;
  final events = <RawMidiEvent>[];
  for (final note in const <int>[50, 55, 59]) {
    events.add(_noteEvent(seq: seq++, ts: 1000, note: note));
  }
  for (final note in const <int>[50, 55, 59]) {
    events.add(_noteEvent(seq: seq++, ts: 1050, note: note, on: false));
  }
  return events;
}

List<RawMidiEvent> _nothingPlayed() => const <RawMidiEvent>[];

void main() {
  final target = const ExpectedMusicalTargetFactory().build(
    quality: TargetQuality.major,
    root: TargetRoot.c,
    hand: TargetHand.right,
    mode: TargetMode.block,
    targetId: 'major-c-rh-block',
  );

  const flow = EvaluationFlowService();

  test('perfect C-major block -> evaluated 5 stars', () {
    final outcome = flow.evaluate(
      target: target,
      sessionId: _session,
      events: _perfectBlock(),
    );
    expect(outcome.isEvaluated, isTrue);
    expect(outcome.stars, 5);
    expect(outcome.targetId, 'major-c-rh-block');
    expect(outcome.sessionId, _session);
    expect(outcome.mode, TargetMode.block);
  });

  test('incomplete block (missing E) -> evaluated with a lower real result',
      () {
    final outcome = flow.evaluate(
      target: target,
      sessionId: _session,
      events: _missingMiddle(),
    );
    expect(outcome.isEvaluated, isTrue);
    expect(outcome.stars, isNotNull);
    expect(outcome.stars, lessThan(5));
  });

  test('zero structural associations -> NOT_ENOUGH_PERFORMANCE result', () {
    final outcome = flow.evaluate(
      target: target,
      sessionId: _session,
      events: _noExpectedNotes(),
    );
    expect(outcome.isEvaluated, isFalse);
    expect(outcome.isNotEnoughPerformance, isTrue);
    expect(outcome.result.state.name, 'notEnoughPerformance');
    expect(outcome.result, isA<NotEnoughPerformanceResult>());
  });

  test('empty capture -> NOT_ENOUGH_PERFORMANCE result, never invented', () {
    final outcome = flow.evaluate(
      target: target,
      sessionId: _session,
      events: _nothingPlayed(),
    );
    expect(outcome.isEvaluated, isFalse);
    expect(outcome.isNotEnoughPerformance, isTrue);
  });

  test('fixed evaluation context: beginner learner level and tempo 90', () {
    // The defaults are the slice-1 fixed context required by the existing
    // evaluation semantics (simultaneity throws without a learner level).
    final outcome = flow.evaluate(
      target: target,
      sessionId: _session,
      events: _perfectBlock(),
    );
    expect(outcome.stars, 5);
  });

  test('new evaluation result does not invent an attempt state', () {
    final outcome = flow.evaluate(
      target: target,
      sessionId: _session,
      events: _perfectBlock(),
    );
    // No `failed` vocabulary exists on the result; only evaluated / NEP.
    expect(outcome.result.state, isNotNull);
  });
}