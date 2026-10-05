import 'dart:async';

import 'package:flutter/material.dart';

import '../../midi/application/midi_device_connection.dart';
import '../../midi/application/midi_device_discovery.dart';
import '../../midi/application/midi_event_stream.dart';
import '../../midi/application/raw_midi_export_sink.dart';
import '../../practice/application/evaluation_flow.dart';
import '../../practice/application/fingering_data.dart';
import '../../practice/application/learning_catalog.dart';
import '../../practice/application/learning_path_service.dart';
import '../../practice/application/lesson_instruction.dart';
import '../../practice/application/lesson_progress_service.dart';
import '../../practice/application/practice_sequence_catalog.dart';
import '../../practice/application/practice_sequence_controller.dart';
import '../../practice/application/practice_session_controller.dart';
import '../../practice/application/teach_sequence.dart';
import '../../practice/domain/learning_lesson.dart';
import '../../practice/domain/learning_path.dart';
import '../../practice/domain/practice_clock.dart';
import '../../practice/domain/practice_exercise.dart';
import '../../midi/domain/evaluation_result.dart';
import 'practice_view.dart';
import 'result_view.dart';
import 'teach_view.dart';

enum _Stage { teach, practice, result }

class LessonScreen extends StatefulWidget {
  const LessonScreen({
    super.key,
    required this.lesson,
    required this.catalog,
    required this.discovery,
    required this.connection,
    required this.captureFactory,
    required this.progressService,
    required this.clock,
    this.exportSink,
  });

  final LearningLesson lesson;
  final LearningCatalog catalog;
  final MidiDeviceDiscovery discovery;
  final MidiDeviceConnection connection;
  final MidiEventStream Function() captureFactory;
  final LessonProgressService progressService;
  final PracticeClock clock;
  final RawMidiExportSink? exportSink;

  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  final ValueNotifier<_Stage> _stage = ValueNotifier<_Stage>(_Stage.teach);

  // The Lesson owns one deterministic Practice Sequence; N = 1 today but the
  // controller is N-capable (architecture §14): exercises map one-to-one to
  // genuinely distinct, runtime-executable interactions - never a label around
  // the same interaction.
  late final PracticeSequence _practiceSequence;
  late final PracticeSequenceController _sequence;

  // One session per exercise, cached by exercise id. Advancing to a different
  // exercise builds a fresh session controller (fresh capture/interaction
  // boundary); retrying the same exercise reuses it via retryAttempt().
  String? _sessionExerciseId;
  PracticeSessionController? _session;

  PracticeSessionController get _ensureController {
    final exercise = _sequence.value.currentExercise;
    if (_session != null && _sessionExerciseId == exercise.id) {
      return _session!;
    }
    _session?.dispose();
    final fresh = PracticeSessionController(
      discovery: widget.discovery,
      connection: widget.connection,
      captureFactory: widget.captureFactory,
      evaluation: const EvaluationFlowService(),
      progressService: widget.progressService,
      clock: widget.clock,
      exercise: exercise,
      targetFactory: widget.catalog.buildTargetForTargetId,
    );
    _session = fresh;
    _sessionExerciseId = exercise.id;
    return fresh;
  }

  @override
  void initState() {
    super.initState();
    _practiceSequence =
        PracticeSequenceCatalog(widget.catalog).sequenceFor(widget.lesson);
    _sequence = PracticeSequenceController(sequence: _practiceSequence);
  }

  @override
  void dispose() {
    _stage.dispose();
    _sequence.dispose();
    _session?.dispose();
    super.dispose();
  }

  void _startPractice() {
    setState(() {
      _stage.value = _Stage.practice;
    });
  }

  /// Marks the just-finished exercise completed when the authoritative
  /// evaluated result cleared the completion threshold (§12). NEP and
  /// zero-star evaluated results are real attempts but never complete the
  /// exercise, so Continue stays gated and the learner must retry.
  void _syncExerciseCompletion() {
    final result = _ensureController.session.value.latestCompletedResult;
    if (result is EvaluatedResult &&
        result.stars >= PracticeExercise.completionStarThreshold) {
      _sequence.completeCurrentExercise();
    }
  }

  void _toResult() {
    _syncExerciseCompletion();
    setState(() {
      _stage.value = _Stage.result;
    });
  }

  void _retry() {
    _ensureController.retryAttempt();
    setState(() {
      _stage.value = _Stage.practice;
    });
  }

  /// Continues: closes the finished practice interaction, then opens the next
  /// lesson when it became available, otherwise returns to the Learning Path.
  /// Only reachable once the sequence completes.
  ///
  /// Closing the interaction is the completion boundary of the practice
  /// engagement; the controller decides what that means for the runtime
  /// lifecycle, so this screen stays free of any temporal/evidence vocabulary.
  Future<void> _continue() async {
    _ensureController.completeInteraction();
    await _ensureController.disconnect();
    if (!mounted) {
      return;
    }
    final service = LearningPathService(
      catalog: widget.catalog,
      progressService: widget.progressService,
    );
    final next = (await service.loadPath()).nextLessonAfter(widget.lesson.id);
    if (!mounted) {
      return;
    }
    if (next != null && next.availability != LessonAvailability.locked) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => LessonScreen(
            lesson: next.lesson,
            catalog: widget.catalog,
            discovery: widget.discovery,
            connection: widget.connection,
            captureFactory: widget.captureFactory,
            progressService: widget.progressService,
            clock: widget.clock,
            exportSink: widget.exportSink,
          ),
        ),
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  String get _exerciseContext {
    final snapshot = _sequence.value;
    return 'Exercise ${snapshot.currentIndex + 1} of '
        '${snapshot.totalExercises} · ${snapshot.currentExercise.title}';
  }

  /// A learner exit before Continue is an abandonment, never a completion.
  ///
  /// `PopScope` observes the platform/UI Back navigation without blocking it and
  /// without owning any lifecycle logic: it only forwards the exit to the
  /// controller, which decides what abandoning the engagement means (RT-009).
  /// Leaving while a Practice Interaction is open therefore ends it `abandoned`;
  /// the Continue path ends it `completed` and stays distinguishable. When no
  /// session was ever built (Back from Teach) there is nothing to abandon.
  void _handlePop(bool didPop) {
    if (didPop) {
      unawaited(_session?.abandonAttempt());
    }
  }

  @override
  Widget build(BuildContext context) {
    final teachTarget = widget.catalog.buildTarget(widget.lesson);
    final teachInstruction = LessonInstructionFactory().build(
      target: teachTarget,
      fingerings: const FingeringCatalog().fingeringsFor(widget.lesson.targetId),
    );
    final exerciseTarget = widget.catalog
        .buildTargetForTargetId(_sequence.value.currentExercise.targetId);
    final exerciseInstruction = LessonInstructionFactory().build(
      target: exerciseTarget,
      fingerings:
          const FingeringCatalog().fingeringsFor(exerciseTarget.targetId),
    );
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) => _handlePop(didPop),
      child: Scaffold(
        appBar: AppBar(title: Text(widget.lesson.title)),
        body: ValueListenableBuilder<_Stage>(
          valueListenable: _stage,
          builder: (context, stage, _) {
            return switch (stage) {
              _Stage.teach => TeachView(
                  lesson: widget.lesson,
                  instruction: teachInstruction,
                  steps: TeachSequence().build(
                    lesson: widget.lesson,
                    instruction: teachInstruction,
                  ),
                  onStartPractice: _startPractice,
                ),
              _Stage.practice => PracticeView(
                  controller: _ensureController,
                  instruction: exerciseInstruction,
                  onFinished: _toResult,
                  exerciseContext: _exerciseContext,
                ),
              _Stage.result => ResultView(
                  snapshot: _ensureController.session.value,
                  exerciseContext: _exerciseContext,
                  practiceComplete: _sequence.value.sequenceComplete,
                  canContinue: _sequence.value.sequenceComplete,
                  onRetry: _retry,
                  onContinue: _continue,
                ),
            };
          },
        ),
      ),
    );
  }
}