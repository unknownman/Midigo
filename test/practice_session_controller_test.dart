import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:miditutor/midi/application/expected_musical_target_factory.dart';
import 'package:miditutor/midi/application/midi_device_connection.dart';
import 'package:miditutor/midi/application/midi_device_discovery.dart';
import 'package:miditutor/midi/application/midi_event_stream.dart';
import 'package:miditutor/midi/domain/expected_musical_target.dart';
import 'package:miditutor/midi/domain/midi_connection_session.dart';
import 'package:miditutor/midi/domain/midi_connection_state.dart';
import 'package:miditutor/midi/domain/midi_source_info.dart';
import 'package:miditutor/midi/domain/raw_midi_event.dart';
import 'package:miditutor/practice/application/evaluation_flow.dart';
import 'package:miditutor/practice/application/in_memory_lesson_progress_store.dart';
import 'package:miditutor/practice/application/lesson_progress_service.dart';
import 'package:miditutor/practice/application/practice_session_controller.dart';
import 'package:miditutor/practice/application/slice1_catalog.dart';
import 'package:miditutor/practice/domain/attempt.dart';
import 'package:miditutor/practice/domain/practice_clock.dart';
import 'package:miditutor/practice/domain/practice_interaction.dart';

final class _FakeClock implements PracticeClock {
  DateTime current;
  _FakeClock(this.current);
  @override
  DateTime now() => current;
}

final class _FakeDiscovery implements MidiDeviceDiscovery {
  final List<MidiSourceInfo> sources;
  _FakeDiscovery(this.sources);
  @override
  Future<List<MidiSourceInfo>> listSources() async => sources;
}

final class _FakeConnection implements MidiDeviceConnection {
  MidiConnectionSession? session;
  MidiConnectionState _state = MidiConnectionState.notConnected;

  @override
  MidiConnectionState get state => _state;

  @override
  MidiConnectionSession? get currentSession => session;

  @override
  Future<MidiConnectionSession> connect(MidiSourceInfo source) async {
    session = MidiConnectionSession(
      sessionId: 'session-1',
      deviceId: source.id,
      connectionType: 'USB',
    );
    _state = MidiConnectionState.connected;
    return session!;
  }

  @override
  Future<void> disconnect() async {
    session = null;
    _state = MidiConnectionState.disconnected;
  }
}

final class _FakeMidiStream implements MidiEventStream {
  final StreamController<RawMidiEvent> _controller =
      StreamController<RawMidiEvent>.broadcast();
  @override
  Stream<RawMidiEvent> get events => _controller.stream;
}

RawMidiEvent _note(int seq, int ts, int note, {bool on = true}) => RawMidiEvent(
      sessionId: 'session-1',
      deviceId: 'dev',
      connectionType: 'USB',
      seq: seq,
      appMonotonicTsMs: ts,
      messageType: on ? RawMidiMessageType.noteOn : RawMidiMessageType.noteOff,
      channel: 0,
      note: note,
      velocity: on ? 90 : 0,
      rawBytes: <int>[on ? 0x90 : 0x80, note, on ? 90 : 0],
    );

void main() {
  final target = const ExpectedMusicalTargetFactory().build(
    quality: TargetQuality.major,
    root: TargetRoot.c,
    hand: TargetHand.right,
    mode: TargetMode.block,
    targetId: 'major-c-rh-block',
  );

  late _FakeDiscovery discovery;
  late _FakeConnection connection;
  late _FakeMidiStream stream;
  late PracticeSessionController controller;

  Future<PracticeSessionController> buildController() async {
    final clock = _FakeClock(DateTime(2025, 1, 1, 11, 0, 0));
    discovery = _FakeDiscovery(const <MidiSourceInfo>[
      MidiSourceInfo(id: 'dev', name: 'APC Key 25', manufacturer: 'Akai'),
    ]);
    connection = _FakeConnection();
    stream = _FakeMidiStream();
    final store = InMemoryLessonProgressStore();
    controller = PracticeSessionController(
      discovery: discovery,
      connection: connection,
      captureFactory: () => stream,
      evaluation: const EvaluationFlowService(),
      progressService: LessonProgressService(store: store),
      clock: clock,
      targetProvider: () => target,
    );
    return controller;
  }

  Future<void> connectAndStart() async {
    await controller.connect(discovery.sources.first);
    await controller.startAttempt();
  }

  Future<void> playPerfectBlock() async {
    for (final (i, note) in const <int>[60, 64, 67].indexed) {
      stream._controller.add(_note(i, 1000, note));
    }
    for (final (i, note) in const <int>[60, 64, 67].indexed) {
      stream._controller.add(_note(i + 3, 1050, note, on: false));
    }
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> playStaggeredWithExtras() async {
    final onRows = <List<int>>[const [60], const [64, 62], const [67, 65], const [69]];
    final offRows = <List<int>>[[60], [64, 62], [67, 65], [69]];
    var seq = 0;
    for (final (i, row) in onRows.indexed) {
      for (final note in row) {
        stream._controller.add(_note(seq++, 1000 + i * 50, note));
      }
    }
    for (final (i, row) in offRows.indexed) {
      for (final note in row) {
        stream._controller.add(_note(seq++, 1050 + i * 50, note, on: false));
      }
    }
    await Future<void>.delayed(Duration.zero);
  }

  test('lists MIDI sources through discovery', () async {
    final controller = await buildController();
    final sources = await controller.listSources();
    expect(sources, hasLength(1));
    expect(sources.first.name, 'APC Key 25');
  });

  test('startAttempt before connect surfaces a learner-safe error', () async {
    await buildController();
    await controller.startAttempt();

    expect(controller.session.value.isConnected, isFalse);
    expect(controller.session.value.errorMessage, 'Connect a MIDI keyboard first.');
    expect(controller.session.value.attemptInProgress, isFalse);
    expect(controller.runtime.hasOpenInteraction, isFalse);
  });

  test('connect then startAttempt arms one attempt with deterministic ids',
      () async {
    await buildController();
    await connectAndStart();

    final snapshot = controller.session.value;
    expect(snapshot.isConnected, isTrue);
    expect(snapshot.sourceName, 'APC Key 25');
    expect(snapshot.attemptInProgress, isTrue);

    final interaction = controller.runtime.currentInteraction!;
    expect(interaction.id, 'pi-major-c-rh-block');
    expect(interaction.executionSession.id, 'es-pi-major-c-rh-block');
    expect(interaction.items, hasLength(1));
    final attempt = interaction.items.first.attempts.last;
    expect(attempt.id, 'pi-major-c-rh-block-item-0-attempt-1');
    expect(attempt.state, AttemptState.armed);
    expect(attempt.startedAt, isNull);
  });

  test('endAttempt evaluates a perfect block to 5 stars and records progress',
      () async {
    await buildController();
    await connectAndStart();
    await playPerfectBlock();

    await controller.endAttempt();

    final snapshot = controller.session.value;
    expect(snapshot.currentStars, 5);
    expect(snapshot.attemptInProgress, isFalse);
    expect(snapshot.resultMessage, 'Perfect! All notes matched.');

    final attempt =
        controller.runtime.currentInteraction!.items.first.attempts.last;
    expect(attempt.state, AttemptState.completed);
    expect(attempt.endedAt, isNotNull);

    final progress =
        await controller.progressService.loadProgress(Slice1Catalog.cMajorTargetId);
    expect(progress.stars, 5);
    expect(progress.attemptCount, 1);
  });

  test('retryAttempt arms a fresh deterministic attempt id', () async {
    await buildController();
    await connectAndStart();
    await playPerfectBlock();
    await controller.endAttempt();

    await controller.retryAttempt();

    final item = controller.runtime.currentInteraction!.items.first;
    expect(item.attempts, hasLength(2));
    expect(item.attempts.last.state, AttemptState.armed);
    expect(item.attempts.last.id, 'pi-major-c-rh-block-item-0-attempt-2');
  });

  test('per-attempt stars after 5-star then NEP show NEP, not the earlier 5',
      () async {
    await buildController();
    await connectAndStart();
    await playPerfectBlock();
    await controller.endAttempt();
    expect(controller.session.value.currentStars, 5);
    expect(controller.session.value.resultMessage, 'Perfect! All notes matched.');

    await controller.retryAttempt();
    await controller.endAttempt();

    expect(controller.session.value.currentStars, 0);
    expect(
      controller.session.value.resultMessage,
      'Not enough performance to evaluate.',
    );
  });

  test('per-attempt stars after 5-star then 0-star show 0', () async {
    await buildController();
    await connectAndStart();
    await playPerfectBlock();
    await controller.endAttempt();
    expect(controller.session.value.currentStars, 5);

    await controller.retryAttempt();
    await playStaggeredWithExtras();
    await controller.endAttempt();

    expect(controller.session.value.currentStars, 0);
    expect(controller.session.value.resultMessage, 'Keep practicing the C block.');
  });

  test('abandonAttempt mid-attempt leaves the attempt abandoned', () async {
    await buildController();
    await connectAndStart();

    await controller.abandonAttempt();

    final interaction = controller.runtime.currentInteraction!;
    expect(interaction.endReason, PracticeInteractionEndReason.abandoned);
    final attempt = interaction.items.first.attempts.last;
    expect(attempt.state, AttemptState.abandoned);
    expect(attempt.endedAt, isNotNull);
  });

  test('disconnect stops capture and clears the session', () async {
    await buildController();
    await connectAndStart();

    await controller.disconnect();

    expect(controller.session.value.isConnected, isFalse);
    expect(connection.currentSession, isNull);
    expect(
      controller.session.value.sourceName,
      isEmpty,
    );
  });
}