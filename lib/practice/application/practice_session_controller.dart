import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../midi/application/midi_device_connection.dart';
import '../../midi/application/midi_device_discovery.dart';
import '../../midi/application/midi_event_stream.dart';
import '../../midi/application/midi_raw_event_capture.dart';
import '../../midi/domain/evaluation_result.dart';
import '../../midi/domain/expected_musical_target.dart';
import '../../midi/domain/midi_connection_error.dart';
import '../../midi/domain/midi_connection_state.dart';
import '../../midi/domain/midi_source_info.dart';
import '../../midi/domain/raw_midi_event.dart';
import '../domain/attempt.dart';
import '../domain/exercise_instance.dart';
import '../domain/practice_clock.dart';
import '../domain/practice_interaction.dart';
import '../domain/practice_item.dart';
import 'evaluation_flow.dart';
import 'lesson_progress.dart';
import 'lesson_progress_service.dart';
import 'practice_runtime.dart';
import 'target_prompt.dart';

/// Cradle-observable snapshot of the learner-facing practice session state.
///
/// UI never reads internal architecture vocabulary (no EvidenceGroup, no
/// PracticeInteraction, no ExecutionSession, no AttemptState). It only sees
/// learner-facing concepts: Lesson, Practice, Result, Stars, Continue, Retry.
class PracticeSessionSnapshot {
  final bool isConnected;
  final String sourceName;
  final String sessionId;
  final String deviceId;
  final String connectionType;
  final String lessonTitle;
  final String targetDescription;
  final String playInstruction;
  final int currentStars;
  final int lessonStars;
  final int attemptCount;
  final bool attemptInProgress;
  final String resultMessage;
  final String? errorMessage;

  /// MIDI pitches currently held down during a live practice attempt.
  ///
  /// This is a learner-facing projection only: it is never used for grading and
  /// never touches the evaluation pipeline. The set is immutable-by-convention:
  /// every producer wraps it as unmodifiable, so a mutable set never escapes to
  /// the UI.
  final Set<int> pressedNotes;

  const PracticeSessionSnapshot({
    required this.isConnected,
    required this.sourceName,
    this.sessionId = '',
    this.deviceId = '',
    this.connectionType = '',
    required this.lessonTitle,
    required this.targetDescription,
    required this.playInstruction,
    required this.currentStars,
    required this.lessonStars,
    required this.attemptCount,
    required this.attemptInProgress,
    required this.resultMessage,
    this.errorMessage,
    this.pressedNotes = const <int>{},
  });

  factory PracticeSessionSnapshot.initial() => const PracticeSessionSnapshot(
        isConnected: false,
        sourceName: '',
        lessonTitle: 'C Major',
        targetDescription: 'Play the C block',
        playInstruction: 'Play C4, E4, and G4 together.',
        currentStars: 0,
        lessonStars: 0,
        attemptCount: 0,
        attemptInProgress: false,
        resultMessage: '',
      );

  factory PracticeSessionSnapshot.forTarget(ExpectedMusicalTarget target) {
    return PracticeSessionSnapshot(
      isConnected: false,
      sourceName: '',
      lessonTitle: '${target.root.label} ${target.quality.label}',
      targetDescription: 'Play the C ${target.mode.name}',
      playInstruction: TargetPrompt.playInstruction(target),
      currentStars: 0,
      lessonStars: 0,
      attemptCount: 0,
      attemptInProgress: false,
      resultMessage: '',
    );
  }

  PracticeSessionSnapshot copyWith({
    bool? isConnected,
    String? sourceName,
    String? sessionId,
    String? deviceId,
    String? connectionType,
    String? lessonTitle,
    String? targetDescription,
    String? playInstruction,
    int? currentStars,
    int? lessonStars,
    int? attemptCount,
    bool? attemptInProgress,
    String? resultMessage,
    Object? errorMessage = _unset,
    Set<int>? pressedNotes,
  }) {
    return PracticeSessionSnapshot(
      isConnected: isConnected ?? this.isConnected,
      sourceName: sourceName ?? this.sourceName,
      sessionId: sessionId ?? this.sessionId,
      deviceId: deviceId ?? this.deviceId,
      connectionType: connectionType ?? this.connectionType,
      lessonTitle: lessonTitle ?? this.lessonTitle,
      targetDescription: targetDescription ?? this.targetDescription,
      playInstruction: playInstruction ?? this.playInstruction,
      currentStars: currentStars ?? this.currentStars,
      lessonStars: lessonStars ?? this.lessonStars,
      attemptCount: attemptCount ?? this.attemptCount,
      attemptInProgress: attemptInProgress ?? this.attemptInProgress,
      resultMessage: resultMessage ?? this.resultMessage,
      errorMessage:
          identical(errorMessage, _unset) ? this.errorMessage : errorMessage as String?,
      pressedNotes: pressedNotes == null
          ? this.pressedNotes
          : Set<int>.unmodifiable(pressedNotes),
    );
  }

  static const Object _unset = Object();
}

/// The app-level orchestrator at the MIDI + practice boundary.
///
/// Owns discovery/connection/event-stream/capture plus the [PracticeRuntime],
/// [EvaluationFlowService], and [LessonProgressService]. UI never touches
/// `EvaluationEngine` / `RawMidiEvent` / CoreMIDI - it only consumes the
/// [session] snapshot and the learner-facing methods on this controller.
class PracticeSessionController {
  PracticeSessionController({
    required this.discovery,
    required this.connection,
    required MidiEventStream Function() captureFactory,
    required this.evaluation,
    required this.progressService,
    required this.clock,
    required this.targetProvider,
  })  : _runtime = PracticeRuntime(clock: clock),
        session = ValueNotifier<PracticeSessionSnapshot>(
            PracticeSessionSnapshot.forTarget(targetProvider())) {
    // The MIDI event stream is created exactly once per controller and shared
    // by both the capture (per-attempt buffering) and the live projection.
    _events = captureFactory();
    _capture = MidiRawEventCapture(_events);
    // The shared [MidiDeviceConnection] is the single authoritative source of
    // connection truth. If a session already exists (e.g. established from the
    // MIDI diagnostics screen or a previous lesson), Practice adopts it instead
    // of pretending it is disconnected.
    _reconcileConnection();
    // One live subscription for the whole controller lifetime (cancelled in
    // [dispose]): it drives the learner-facing pressed-key projection and never
    // inherits or filters evaluation capture (the capture keeps its own
    // listener via [MidiRawEventCapture]).
    _liveSubscription = _events.events.listen(_handleLiveEvent);
  }

  final MidiDeviceDiscovery discovery;
  final MidiDeviceConnection connection;
  final EvaluationFlowService evaluation;
  final LessonProgressService progressService;
  final PracticeClock clock;
  final ExpectedMusicalTarget Function() targetProvider;

  final PracticeRuntime _runtime;
  late final MidiEventStream _events;
  late final MidiRawEventCapture _capture;

  /// Live sourced subscription for the pressed-key projection. There is
  /// exactly one per controller and it is cancelled in [dispose].
  StreamSubscription<RawMidiEvent>? _liveSubscription;

  /// Currently held-down pitches during an active attempt, projected for the
  /// UI. Cleared at every attempt boundary and on disconnect.
  final Set<int> _pressedNotes = <int>{};

  /// Read-only access for tests; UI must not mutate runtime state directly.
  PracticeRuntime get runtime => _runtime;

  final ValueNotifier<PracticeSessionSnapshot> session;

  bool _interactionStarted = false;

  Future<List<MidiSourceInfo>> listSources() => discovery.listSources();

  /// Connects to [source], returning whether the practice session is now
  /// connected to it.
  ///
  /// Success includes adopting an already-active shared connection for the same
  /// device: when [MacosMidiDeviceConnection] already holds a session for
  /// [source.id], the practice snapshot reconciles with that existing session
  /// instead of reporting it as an error. Clears the learner-facing error state
  /// on success; surfaces a learner-safe message (no internal vocabulary) when
  /// the platform connection genuinely fails. The MIDI capture itself starts
  /// per-attempt via [startAttempt].
  Future<bool> connect(MidiSourceInfo source) async {
    try {
      await connection.connect(source);
    } on MidiConnectionException catch (e) {
      return _applyConnectionFailure(e, source);
    }
    _reconcileConnection(requestedSourceName: source.name);
    session.value = session.value.copyWith(errorMessage: null);
    return true;
  }

  /// Reconciles the practice snapshot with the shared connection's
  /// authoritative [MidiDeviceConnection.state]/[currentSession], keeping the
  /// learner-facing [session] truthful. Never invents a connection: only a live
  /// platform session is surfaced as connected, and its exact `sessionId` /
  /// `deviceId` / `connectionType` are preserved.
  void _reconcileConnection({String? requestedSourceName}) {
    final active = connection.currentSession;
    if (connection.state == MidiConnectionState.connected && active != null) {
      session.value = session.value.copyWith(
        isConnected: true,
        sourceName: requestedSourceName ?? session.value.sourceName,
        sessionId: active.sessionId,
        deviceId: active.deviceId,
        connectionType: active.connectionType,
      );
      return;
    }
    session.value = session.value.copyWith(
      isConnected: false,
      sourceName: '',
      sessionId: '',
      deviceId: '',
      connectionType: '',
    );
  }

  /// Decides how a platform connect error shapes the practice snapshot.
  ///
  /// `alreadyConnected` for the requested device is a reconciliation, not a
  /// failure: the existing session is adopted and `true` is returned. A live
  /// session for a *different* device is never replaced or silently adopted;
  /// Practice keeps reflecting the active connection and surfaces the existing
  /// conflict message. Any genuine failure leaves the connection truth as-is.
  bool _applyConnectionFailure(
      MidiConnectionException error, MidiSourceInfo source) {
    final active = connection.currentSession;
    final sameDevice = active != null && active.deviceId == source.id;
    if (error.code == MidiConnectionError.alreadyConnected && sameDevice) {
      _reconcileConnection(requestedSourceName: source.name);
      session.value = session.value.copyWith(errorMessage: null);
      return true;
    }
    _reconcileConnection();
    session.value =
        session.value.copyWith(errorMessage: _connectionMessage(error.code));
    return false;
  }

  /// When Practice adopted an already-active shared connection, the device's
  /// human-readable name is not part of [MidiConnectionSession]; resolve it from
  /// discovery so the connected header shows the actual device name.
  Future<void> resolveSourceName() async {
    final snapshot = session.value;
    if (!snapshot.isConnected || snapshot.sourceName.isNotEmpty) {
      return;
    }
    List<MidiSourceInfo> sources;
    try {
      sources = await discovery.listSources();
    } catch (_) {
      return;
    }
    for (final source in sources) {
      if (source.id == snapshot.deviceId) {
        session.value = session.value.copyWith(sourceName: source.name);
        return;
      }
    }
  }

  /// Projects a live raw MIDI note into the learner-facing pressed state.
  ///
  /// Session safety: only events whose `sessionId` matches the connection's
  /// active session are projected; events from older/foreign sessions are
  /// ignored. Raw event semantics (Slice 2.2, documented decision): `note_on`
  /// with velocity > 0 is a press, `note_off` is a release, and `note_on` with
  /// velocity 0 is left as a raw `note_on` - it is NEVER normalized into a
  /// release, so it neither presses nor releases a note here. The projected set
  /// is never used for grading.
  void _handleLiveEvent(RawMidiEvent event) {
    final snapshot = session.value;
    final note = event.note;
    if (!snapshot.isConnected ||
        !snapshot.attemptInProgress ||
        note == null ||
        note < 0 ||
        note > 127) {
      return;
    }
    final activeSessionId = connection.currentSession?.sessionId;
    if (activeSessionId == null || event.sessionId != activeSessionId) {
      return;
    }
    final changed = switch (event.messageType) {
      RawMidiMessageType.noteOn when (event.velocity ?? 0) > 0 =>
        _pressedNotes.add(note),
      RawMidiMessageType.noteOn => false,
      RawMidiMessageType.noteOff => _pressedNotes.remove(note),
      RawMidiMessageType.other => false,
    };
    if (changed) {
      session.value = session.value.copyWith(
        pressedNotes: _snapshotPressedNotes,
      );
    }
  }

  /// Immutable-by-convention view of the pressed projection for the snapshot.
  Set<int> get _snapshotPressedNotes => Set<int>.unmodifiable(_pressedNotes);

  /// Clears the live pressed projection at an attempt boundary or disconnect so
  /// no stale keys bleed into the next attempt, a Result, or the next lesson.
  void _resetLiveProjection() {
    if (_pressedNotes.isEmpty && session.value.pressedNotes.isEmpty) {
      return;
    }
    _pressedNotes.clear();
    session.value = session.value.copyWith(pressedNotes: const <int>{});
  }

  Future<void> disconnect() async {
    await _capture.stop();
    await connection.disconnect();
    _reconcileConnection();
    _resetLiveProjection();
  }

  /// Starts one attempt: opens the interaction (once) and arms a fresh attempt,
  /// starting the MIDI capture buffer for this attempt.
  Future<void> startAttempt() async {
    if (!session.value.isConnected) {
      session.value = session.value.copyWith(
        errorMessage: session.value.errorMessage ?? 'Connect a MIDI keyboard first.',
        attemptInProgress: false,
      );
      return;
    }
    final target = targetProvider();
    final exercise = ExerciseInstance(
      id: 'exercise-${target.targetId}',
      expectedTarget: target,
    );

    _resetLiveProjection();

    if (!_runtime.hasOpenInteraction) {
      _runtime.createInteraction(
        interactionId: 'pi-${target.targetId}',
        exercises: <ExerciseInstance>[exercise],
      );
    }
    _runtime.armAttempt(itemId: _firstItemId());
    _interactionStarted = true;

    await _capture.start(connection.currentSession!.sessionId);
    session.value = session.value.copyWith(
      attemptInProgress: true,
      errorMessage: null,
      resultMessage: '',
      currentStars: 0,
    );
  }

  /// Ends the current attempt: snapshots the capture buffer, runs the frozen
  /// evaluation pipeline, completes the attempt, and records lesson progress.
  Future<void> endAttempt() async {
    if (!_interactionStarted || !session.value.attemptInProgress) {
      return;
    }
    final target = targetProvider();
    final attempt = _runtime.currentItems.first.attempts.last;
    _runtime.activateAttempt(attempt.id);
    await _capture.stop();
    final flow = evaluation.evaluate(
      target: target,
      sessionId: connection.currentSession!.sessionId,
      events: _capture.buffer.events,
    );
    _runtime.completeAttempt(attemptId: attempt.id, result: flow.result);
    await progressService.recordResult(
      targetId: target.targetId,
      result: flow.result,
    );
    await _refresh(attemptInProgress: false);
    _resetLiveProjection();
  }

  /// Abandons the current attempt and the open interaction.
  Future<void> abandonAttempt() async {
    if (!_interactionStarted) {
      return;
    }
    if (session.value.attemptInProgress) {
      final attempt = _runtime.currentItems.first.attempts.last;
      _runtime.abandonAttempt(attempt.id);
    }
    _runtime.endInteraction(reason: PracticeInteractionEndReason.abandoned);
    _interactionStarted = false;
    await _capture.stop();
    await _refresh(attemptInProgress: false);
    _resetLiveProjection();
  }

  /// Retries: arms a fresh attempt and restarts the capture buffer.
  Future<void> retryAttempt() async {
    if (!_interactionStarted || !session.value.isConnected) {
      return;
    }
    _runtime.armAttempt(itemId: _firstItemId());
    await _capture.start(connection.currentSession!.sessionId);
    _resetLiveProjection();
    session.value = session.value.copyWith(
      attemptInProgress: true,
      resultMessage: '',
      currentStars: 0,
      errorMessage: null,
    );
  }

  Future<LessonProgress> _currentProgress() async {
    final target = targetProvider();
    return await progressService.loadProgress(target.targetId);
  }

  Future<void> _refresh({required bool attemptInProgress}) async {
    final target = targetProvider();
    final progress = await _currentProgress();
    final items = _runtime.currentItems;
    session.value = session.value.copyWith(
      isConnected: session.value.isConnected,
      targetDescription: _description(target, items),
      currentStars: _lastCompletedStars(items),
      lessonStars: progress.stars,
      attemptCount: progress.attemptCount,
      attemptInProgress: attemptInProgress,
      resultMessage: _lastResultMessage(target, items),
    );
  }

  String _firstItemId() => _runtime.currentItems.first.id;

  static bool _hasOpenAttempt(List<PracticeItem> items) =>
      items.any((item) => item.attempts.any(_isOpenAttempt));

  static bool _isOpenAttempt(Attempt attempt) =>
      attempt.state == AttemptState.armed ||
      attempt.state == AttemptState.active ||
      attempt.state == AttemptState.paused;

  static EvaluationResult? _latestCompletedResult(List<PracticeItem> items) {
    for (final item in items.reversed) {
      for (final attempt in item.attempts.reversed) {
        if (attempt.state == AttemptState.completed &&
            attempt.evaluationResult != null) {
          return attempt.evaluationResult;
        }
      }
    }
    return null;
  }

  static int _lastCompletedStars(List<PracticeItem> items) {
    final result = _latestCompletedResult(items);
    if (result is EvaluatedResult) {
      return result.stars;
    }
    return 0;
  }

  static String _lastResultMessage(
      ExpectedMusicalTarget target, List<PracticeItem> items) {
    final result = _latestCompletedResult(items);
    if (result is NotEnoughPerformanceResult) {
      return 'Not enough performance to evaluate.';
    }
    if (result is EvaluatedResult) {
      if (result.stars >= 5) {
        return 'Perfect! All notes matched.';
      }
      if (result.stars > 0) {
        return 'Good try — keep the notes together.';
      }
      return 'Keep practicing the C ${target.mode.name}.';
    }
    return '';
  }

  static String _description(ExpectedMusicalTarget target,
          List<PracticeItem> items) =>
      _hasOpenAttempt(items)
          ? 'Play the C ${target.mode.name}'
          : 'C ${target.mode.name} - completed';

  static String _connectionMessage(MidiConnectionError error) => switch (error) {
        MidiConnectionError.alreadyConnected =>
          'A MIDI keyboard is already connected.',
        MidiConnectionError.noSource =>
          'That MIDI keyboard is no longer available.',
        MidiConnectionError.notConnected =>
          'Connect a MIDI keyboard first.',
        MidiConnectionError.connectionFailed =>
          'Could not connect to that MIDI keyboard.',
        MidiConnectionError.disconnectFailed =>
          'Could not disconnect from that MIDI keyboard.',
        MidiConnectionError.invalidRequest =>
          'The MIDI keyboard request was invalid.',
        MidiConnectionError.unknown => 'Could not connect to that MIDI keyboard.',
      };

  void dispose() {
    final live = _liveSubscription;
    _liveSubscription = null;
    if (live != null) {
      unawaited(live.cancel());
    }
    unawaited(_capture.dispose());
    session.dispose();
  }
}