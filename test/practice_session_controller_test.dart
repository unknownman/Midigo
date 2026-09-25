import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:miditutor/midi/application/expected_musical_target_factory.dart';
import 'package:miditutor/midi/application/midi_device_connection.dart';
import 'package:miditutor/midi/application/midi_device_discovery.dart';
import 'package:miditutor/midi/application/midi_event_stream.dart';
import 'package:miditutor/midi/domain/expected_musical_target.dart';
import 'package:miditutor/midi/domain/evaluation_result.dart';
import 'package:miditutor/midi/domain/midi_connection_error.dart';
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
  _FakeConnection();

  MidiConnectionSession? session;
  MidiConnectionState _state = MidiConnectionState.notConnected;

  MidiConnectionException? connectError;

  void preconnect(MidiConnectionSession activeSession) {
    session = activeSession;
    _state = MidiConnectionState.connected;
  }

  @override
  MidiConnectionState get state => _state;

  @override
  MidiConnectionSession? get currentSession => session;

  @override
  Future<MidiConnectionSession> connect(MidiSourceInfo source) async {
    final error = connectError;
    if (error != null) {
      throw error;
    }
    if (_state == MidiConnectionState.connected && session != null) {
      throw const MidiConnectionException(
        MidiConnectionError.alreadyConnected,
        'A MIDI source is already connected.',
      );
    }
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
  _FakeMidiStream() {
    _controller = StreamController<RawMidiEvent>.broadcast(
      onListen: () {
        _listenerCount += 1;
      },
      onCancel: () {
        _listenerCount -= 1;
      },
    );
  }

  late final StreamController<RawMidiEvent> _controller;

  /// Number of active stream listeners (live projection + capture).
  int _listenerCount = 0;
  int get listenerCount => _listenerCount;

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

/// A raw `note_on` that carries velocity 0 (the key makes no sound). Slice 2.2
/// deliberately does NOT normalize this into a `note_off`: the event stays a
/// raw `note_on`, so it neither presses nor releases the projected note.
RawMidiEvent _noteOnZeroVelocity(int seq, int ts, int note) => RawMidiEvent(
      sessionId: 'session-1',
      deviceId: 'dev',
      connectionType: 'USB',
      seq: seq,
      appMonotonicTsMs: ts,
      messageType: RawMidiMessageType.noteOn,
      channel: 0,
      note: note,
      velocity: 0,
      rawBytes: <int>[0x90, note, 0],
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

  Future<PracticeSessionController> buildController(
      {_FakeConnection? injectedConnection}) async {
    final clock = _FakeClock(DateTime(2025, 1, 1, 11, 0, 0));
    discovery = _FakeDiscovery(const <MidiSourceInfo>[
      MidiSourceInfo(id: 'dev', name: 'APC Key 25', manufacturer: 'Akai'),
    ]);
    connection = injectedConnection ?? _FakeConnection();
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

  test('Practice adopts an already-active shared connection on creation',
      () async {
    final active = _FakeConnection()
      ..preconnect(const MidiConnectionSession(
        sessionId: 'S1',
        deviceId: 'dev',
        connectionType: 'USB',
      ));
    await buildController(injectedConnection: active);

    expect(controller.session.value.isConnected, isTrue);
    expect(controller.session.value.sessionId, 'S1');
    expect(controller.session.value.deviceId, 'dev');
    expect(controller.session.value.connectionType, 'USB');
  });

  test('adopting an existing connection preserves its session identity',
      () async {
    final active = _FakeConnection()
      ..preconnect(const MidiConnectionSession(
        sessionId: 'S1',
        deviceId: 'dev',
        connectionType: 'USB',
      ));
    await buildController(injectedConnection: active);
    await controller.resolveSourceName();

    expect(controller.session.value.sourceName, 'APC Key 25');
    expect(controller.session.value.sessionId, 'S1');
    expect(controller.session.value.deviceId, 'dev');
    expect(controller.session.value.connectionType, 'USB');
  });

  test('already-connected same device reconciles instead of failing',
      () async {
    final active = _FakeConnection()
      ..preconnect(const MidiConnectionSession(
        sessionId: 'S1',
        deviceId: 'dev',
        connectionType: 'USB',
      ));
    await buildController(injectedConnection: active);
    expect(controller.session.value.isConnected, isTrue);

    final connected = await controller.connect(discovery.sources.first);

    expect(connected, isTrue);
    expect(controller.session.value.isConnected, isTrue);
    expect(controller.session.value.sessionId, 'S1');
    expect(controller.session.value.deviceId, 'dev');
    expect(controller.session.value.errorMessage, isNull);
    expect(connection.currentSession, isNotNull);
  });

  test('already-connected different device is not silently adopted', () async {
    final active = _FakeConnection()
      ..preconnect(const MidiConnectionSession(
        sessionId: 'S1',
        deviceId: 'other-dev',
        connectionType: 'USB',
      ));
    await buildController(injectedConnection: active);
    expect(controller.session.value.isConnected, isTrue);
    expect(controller.session.value.deviceId, 'other-dev');

    final connected = await controller.connect(discovery.sources.first);

    expect(connected, isFalse);
    expect(
      controller.session.value.errorMessage,
      'A MIDI keyboard is already connected.',
    );
    expect(controller.session.value.deviceId, 'other-dev');
    expect(connection.currentSession!.deviceId, 'other-dev');
  });

  test('startAttempt after a failed connect keeps the connection error',
      () async {
    final failing = _FakeConnection()
      ..connectError = const MidiConnectionException(
        MidiConnectionError.connectionFailed,
        'Could not establish the MIDI connection.',
      );
    await buildController(injectedConnection: failing);

    final connected = await controller.connect(discovery.sources.first);
    expect(connected, isFalse);
    expect(
      controller.session.value.errorMessage,
      'Could not connect to that MIDI keyboard.',
    );

    await controller.startAttempt();

    expect(
      controller.session.value.errorMessage,
      'Could not connect to that MIDI keyboard.',
    );
    expect(controller.session.value.attemptInProgress, isFalse);
    expect(controller.runtime.hasOpenInteraction, isFalse);
  });

  group('Slice 2.2 - live pressed projection', () {
    test('note_on during an active attempt projects the pressed pitch',
        () async {
      await buildController();
      await connectAndStart();
      expect(controller.session.value.pressedNotes, isEmpty);

      stream._controller.add(_note(0, 1000, 60));
      await Future<void>.delayed(Duration.zero);

      expect(controller.session.value.pressedNotes, containsAll(<int>[60]));
    });

    test('note_off removes the pressed pitch', () async {
      await buildController();
      await connectAndStart();
      stream._controller.add(_note(0, 1000, 60));
      await Future<void>.delayed(Duration.zero);
      expect(controller.session.value.pressedNotes, containsAll(<int>[60]));

      stream._controller.add(_note(1, 1050, 60, on: false));
      await Future<void>.delayed(Duration.zero);

      expect(controller.session.value.pressedNotes, isEmpty);
    });

    test('multiple simultaneous notes project an order-independent set',
        () async {
      await buildController();
      await connectAndStart();
      for (final (i, note) in const <int>[60, 64, 67].indexed) {
        stream._controller.add(_note(i, 1000, note));
      }
      await Future<void>.delayed(Duration.zero);

      expect(controller.session.value.pressedNotes, <int>{60, 64, 67});
      // The projected set is immutable: a mutable set never escapes to the UI.
      expect(
        () => controller.session.value.pressedNotes.add(75),
        throwsUnsupportedError,
      );
    });

    test('releasing one of several pressed notes keeps the rest', () async {
      await buildController();
      await connectAndStart();
      for (final (i, note) in const <int>[60, 64, 67].indexed) {
        stream._controller.add(_note(i, 1000, note));
      }
      stream._controller.add(_note(3, 1050, 60, on: false));
      await Future<void>.delayed(Duration.zero);

      expect(controller.session.value.pressedNotes, <int>{64, 67});
    });

    test('note_on with velocity 0 stays raw and neither presses nor releases',
        () async {
      await buildController();
      await connectAndStart();
      // A held note is not released by a velocity-0 note_on...
      stream._controller.add(_note(0, 1000, 60));
      await Future<void>.delayed(Duration.zero);
      expect(controller.session.value.pressedNotes, containsAll(<int>[60]));

      final rawEvent = _noteOnZeroVelocity(1, 1060, 60);
      stream._controller.add(rawEvent);
      stream._controller.add(_noteOnZeroVelocity(2, 1060, 62));
      await Future<void>.delayed(Duration.zero);

      // ...the raw event itself is unchanged (no normalization to note_off)...
      expect(rawEvent.messageType, RawMidiMessageType.noteOn);
      expect(rawEvent.velocity, 0);
      expect(rawEvent.note, 60);
      // ...and the projection is untouched: 60 stays held, 62 is not pressed.
      expect(controller.session.value.pressedNotes, containsAll(<int>[60]));
      expect(controller.session.value.pressedNotes.contains(62), isFalse);
    });

    test('notes pressed before an attempt starts are not projected',
        () async {
      await buildController();
      await controller.connect(discovery.sources.first);

      stream._controller.add(_note(0, 1000, 60));
      await Future<void>.delayed(Duration.zero);

      expect(controller.session.value.pressedNotes, isEmpty);
      expect(controller.session.value.attemptInProgress, isFalse);
    });

    test('startAttempt clears any stale pressed projection at the boundary',
        () async {
      await buildController();
      await connectAndStart();
      stream._controller.add(_note(0, 1000, 60));
      stream._controller.add(_note(1, 1000, 64));
      await Future<void>.delayed(Duration.zero);
      expect(controller.session.value.pressedNotes, <int>{60, 64});

      await controller.startAttempt();

      expect(controller.session.value.pressedNotes, isEmpty);
      expect(controller.session.value.attemptInProgress, isTrue);
      final item = controller.runtime.currentInteraction!.items.first;
      expect(item.attempts, hasLength(2));
    });

    test('endAttempt clears the pressed projection before the result',
        () async {
      await buildController();
      await connectAndStart();
      stream._controller.add(_note(0, 1000, 60));
      stream._controller.add(_note(1, 1000, 64));
      await Future<void>.delayed(Duration.zero);
      expect(controller.session.value.pressedNotes, isNotEmpty);

      await controller.endAttempt();

      expect(controller.session.value.pressedNotes, isEmpty);
      expect(controller.session.value.attemptInProgress, isFalse);
      expect(controller.session.value.resultMessage, isNotEmpty);
    });

    test('events from a foreign or old session are ignored', () async {
      await buildController();
      await connectAndStart();

      // A late event stamped with a previous/session-foreign id is dropped.
      stream._controller.add(RawMidiEvent(
        sessionId: 'old-session-0',
        deviceId: 'dev',
        connectionType: 'USB',
        seq: 0,
        appMonotonicTsMs: 1000,
        messageType: RawMidiMessageType.noteOn,
        channel: 0,
        note: 60,
        velocity: 90,
        rawBytes: <int>[0x90, 60, 90],
      ));
      await Future<void>.delayed(Duration.zero);

      expect(controller.session.value.pressedNotes, isEmpty);
    });

    test('dispose cancels the live MIDI subscription', () async {
      await buildController();
      // One listener (the live projection); the capture is idle until start.
      expect(stream.listenerCount, 1);

      controller.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(stream.listenerCount, 0);
    });

    test('live projection leaves the evaluation capture intact (5 stars)',
        () async {
      await buildController();
      await connectAndStart();
      stream._controller.add(_note(0, 1000, 60));
      await Future<void>.delayed(Duration.zero);
      expect(controller.session.value.pressedNotes, containsAll(<int>[60]));

      await playPerfectBlock();
      await controller.endAttempt();

      // The capture buffer still received every event - the 5-star block
      // evaluated exactly as before the live projection was added.
      expect(controller.session.value.currentStars, 5);
      expect(controller.session.value.pressedNotes, isEmpty);
      expect(
        controller.session.value.resultMessage,
        'Perfect! All notes matched.',
      );
    });
  });

  group('Slice 2.3 - practice completion & result', () {
    test('finish exposes the authoritative result and stops capture',
        () async {
      await buildController();
      await connectAndStart();
      expect(controller.isCapturing, isTrue);
      await playPerfectBlock();

      await controller.endAttempt();

      expect(controller.isCapturing, isFalse);
      final result = controller.session.value.latestCompletedResult;
      expect(result, isA<EvaluatedResult>());
      expect((result! as EvaluatedResult).stars, 5);
      // Exactly one source of truth: the snapshot re-exposes the same instance
      // stored on the completed attempt - it is never re-derived.
      expect(
        result,
        same(
          controller.runtime.currentInteraction!.items.first.attempts.last
              .evaluationResult,
        ),
      );
    });

    test('events arriving after finish cannot contaminate a completed attempt',
        () async {
      await buildController();
      await connectAndStart();
      await playPerfectBlock();
      await controller.endAttempt();

      final first = controller.runtime.currentInteraction!.items.first
          .attempts.last.evaluationResult! as EvaluatedResult;
      expect(first.stars, 5);

      // Late notes pushed after the completion boundary (capture is stopped).
      for (final (i, note) in const <int>[60, 64, 67].indexed) {
        stream._controller.add(_note(i, 1200, note));
      }
      await Future<void>.delayed(Duration.zero);

      expect(
        controller.runtime.currentInteraction!.items.first.attempts.last
            .evaluationResult,
        same(first),
      );
      expect(controller.session.value.latestCompletedResult, same(first));
    });

    test('a finished attempt cannot be completed twice (sequential)', () async {
      await buildController();
      await connectAndStart();
      await playPerfectBlock();
      await controller.endAttempt();

      await controller.endAttempt();

      final item = controller.runtime.currentInteraction!.items.first;
      expect(item.attempts, hasLength(1));
      expect(item.attempts.last.state, AttemptState.completed);
      final progress =
          await controller.progressService.loadProgress(Slice1Catalog.cMajorTargetId);
      expect(progress.attemptCount, 1);
    });

    test('concurrent double finish completes exactly once', () async {
      await buildController();
      await connectAndStart();
      await playPerfectBlock();

      await Future.wait(
        <Future<void>>[controller.endAttempt(), controller.endAttempt()],
      );

      final item = controller.runtime.currentInteraction!.items.first;
      expect(item.attempts, hasLength(1));
      final progress =
          await controller.progressService.loadProgress(Slice1Catalog.cMajorTargetId);
      expect(progress.attemptCount, 1);
      expect(controller.session.value.latestCompletedResult, isA<EvaluatedResult>());
    });

    test('latest completed result after 5-star then NEP is the NEP result',
        () async {
      await buildController();
      await connectAndStart();
      await playPerfectBlock();
      await controller.endAttempt();
      expect(controller.session.value.latestCompletedResult, isA<EvaluatedResult>());

      await controller.retryAttempt();
      await controller.endAttempt();

      final attempts = controller.runtime.currentInteraction!.items.first.attempts;
      expect(attempts.first.evaluationResult, isA<EvaluatedResult>());
      expect(
        (attempts.first.evaluationResult! as EvaluatedResult).stars,
        5,
      );
      expect(attempts.last.evaluationResult, isA<NotEnoughPerformanceResult>());
      expect(
        controller.session.value.latestCompletedResult,
        isA<NotEnoughPerformanceResult>(),
      );
      expect(controller.session.value.currentStars, 0);
    });

    test('latest completed result after a messy block is a 0-star evaluated '
        'result, not NEP', () async {
      await buildController();
      await connectAndStart();
      await playStaggeredWithExtras();
      await controller.endAttempt();

      final result = controller.session.value.latestCompletedResult;
      expect(result, isA<EvaluatedResult>());
      expect((result! as EvaluatedResult).stars, 0);
      expect(controller.session.value.resultMessage, 'Keep practicing the C block.');
    });

    test('NEP records progress without adding lesson stars', () async {
      await buildController();
      await connectAndStart();

      await controller.endAttempt();

      expect(
        controller.session.value.latestCompletedResult,
        isA<NotEnoughPerformanceResult>(),
      );
      final progress =
          await controller.progressService.loadProgress(Slice1Catalog.cMajorTargetId);
      expect(progress.stars, 0);
      expect(progress.attemptCount, 1);
    });

    test('zero-star evaluated result records progress without lesson stars',
        () async {
      await buildController();
      await connectAndStart();
      await playStaggeredWithExtras();
      await controller.endAttempt();

      expect(controller.session.value.latestCompletedResult, isA<EvaluatedResult>());
      final progress =
          await controller.progressService.loadProgress(Slice1Catalog.cMajorTargetId);
      expect(progress.stars, 0);
      expect(progress.attemptCount, 1);
    });

    test('retry does not reuse the previous attempt events (NEP after retry)',
        () async {
      await buildController();
      await connectAndStart();
      await playPerfectBlock();
      await controller.endAttempt();
      expect(
        (controller.runtime.currentInteraction!.items.first.attempts.first
                .evaluationResult! as EvaluatedResult)
            .stars,
        5,
      );

      await controller.retryAttempt();
      // No new events in the second attempt: it must finish NOT_ENOUGH_
      // PERFORMANCE, proving the first block's events were not carried over.
      await controller.endAttempt();

      final attempts = controller.runtime.currentInteraction!.items.first.attempts;
      expect(attempts.first.evaluationResult, isA<EvaluatedResult>());
      expect(attempts.last.evaluationResult, isA<NotEnoughPerformanceResult>());
      expect(
        controller.session.value.latestCompletedResult,
        isA<NotEnoughPerformanceResult>(),
      );
    });

    test('retry clears the pressed projection for the new attempt', () async {
      await buildController();
      await connectAndStart();
      stream._controller.add(_note(0, 1000, 60));
      await Future<void>.delayed(Duration.zero);
      expect(controller.session.value.pressedNotes, containsAll(<int>[60]));

      await controller.retryAttempt();

      expect(controller.session.value.pressedNotes, isEmpty);
      expect(controller.session.value.attemptInProgress, isTrue);
    });
  });

  group('Slice 2.4 - practice guidance state', () {
    test('no stale result leaks into a newly started attempt', () async {
      await buildController();
      await connectAndStart();
      await playPerfectBlock();
      await controller.endAttempt();
      expect(controller.session.value.latestCompletedResult, isA<EvaluatedResult>());

      await controller.startAttempt();

      expect(controller.session.value.latestCompletedResult, isNull);
      expect(controller.session.value.resultMessage, isEmpty);
      expect(controller.session.value.attemptInProgress, isTrue);
    });

    test('retry resets live state into a fresh in-progress attempt', () async {
      await buildController();
      await connectAndStart();
      stream._controller.add(_note(0, 1000, 60));
      await Future<void>.delayed(Duration.zero);
      expect(controller.session.value.pressedNotes, containsAll(<int>[60]));

      await controller.retryAttempt();

      expect(controller.session.value.pressedNotes, isEmpty);
      expect(controller.session.value.attemptInProgress, isTrue);
      expect(controller.session.value.latestCompletedResult, isNull);
      expect(controller.session.value.resultMessage, isEmpty);
      expect(controller.runtime.currentInteraction!.items.first.attempts,
          hasLength(2));
    });
  });
}