import 'dart:async';

import 'package:flutter/material.dart';

import '../../midi/application/midi_device_connection.dart';
import '../../midi/application/midi_device_discovery.dart';
import '../../midi/application/midi_event_stream.dart';
import '../../practice/application/evaluation_flow.dart';
import '../../practice/application/fingering_data.dart';
import '../../practice/application/learning_catalog.dart';
import '../../practice/application/lesson_instruction.dart';
import '../../practice/application/lesson_progress_service.dart';
import '../../practice/application/practice_sequence_catalog.dart';
import '../../practice/application/practice_session_controller.dart';
import '../../practice/domain/learning_lesson.dart';
import '../../practice/domain/practice_clock.dart';
import '../../practice/domain/practice_exercise.dart';
import '../lesson/practice_view.dart';
import '../lesson/result_view.dart';

enum _NormalStage { practice, result }

/// Working practice of one lesson, launched from the Review Hub's `Start`
/// action (Review Scheduler Contract §14).
///
/// This is ordinary practice: lesson progress is recorded and the scheduler is
/// never consulted, so a Start session has no review effect.
class NormalPracticeScreen extends StatefulWidget {
  const NormalPracticeScreen({
    super.key,
    required this.lesson,
    required this.catalog,
    required this.discovery,
    required this.connection,
    required this.captureFactory,
    required this.progressService,
    required this.clock,
    this.sequenceBuilder,
  });

  final LearningLesson lesson;
  final LearningCatalog catalog;
  final MidiDeviceDiscovery discovery;
  final MidiDeviceConnection connection;
  final MidiEventStream Function() captureFactory;
  final LessonProgressService progressService;
  final PracticeClock clock;

  /// Deterministic sequence source, defaulting to the canonical
  /// [PracticeSequenceCatalog] (H2.19).
  ///
  /// Normal Practice is deliberately pinned to the FIRST exercise of the
  /// lesson's sequence - it is a focused working practice, never the full
  /// lesson flow - so this seam lets a two-exercise lesson be supplied to the
  /// screen without the screen becoming sequence-aware. However many exercises
  /// the sequence carries, exactly `exercises.first` is executed.
  final PracticeSequence Function(LearningLesson lesson)? sequenceBuilder;

  @override
  State<NormalPracticeScreen> createState() => _NormalPracticeScreenState();
}

class _NormalPracticeScreenState extends State<NormalPracticeScreen> {
  final ValueNotifier<_NormalStage> _stage =
      ValueNotifier<_NormalStage>(_NormalStage.practice);

  /// The canonical curriculum exercise this session executes, resolved once
  /// from the lesson's Practice Sequence (N = 1 today) so the screen has no
  /// independent target-id -> execution path of its own.
  late final PracticeExercise _exercise;
  late final PracticeSessionController _controller;

  @override
  void initState() {
    super.initState();
    final sequenceFor =
        widget.sequenceBuilder ?? PracticeSequenceCatalog(widget.catalog).sequenceFor;
    _exercise = sequenceFor(widget.lesson).exercises.first;
    _controller = PracticeSessionController(
      discovery: widget.discovery,
      connection: widget.connection,
      captureFactory: widget.captureFactory,
      evaluation: const EvaluationFlowService(),
      progressService: widget.progressService,
      clock: widget.clock,
      exercise: _exercise,
      targetFactory: widget.catalog.buildTargetForTargetId,
    );
  }

  @override
  void dispose() {
    _stage.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _toResult() {
    _stage.value = _NormalStage.result;
  }

  void _retry() {
    _controller.retryAttempt();
    _stage.value = _NormalStage.practice;
  }

  /// Closes the finished practice interaction (the controller owns what that
  /// means for the runtime lifecycle) and leaves the session.
  Future<void> _continue() async {
    _controller.completeInteraction();
    await _controller.disconnect();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.catalog.buildTargetForTargetId(_exercise.targetId);
    final instruction = LessonInstructionFactory().build(
      target: target,
      fingerings: const FingeringCatalog().fingeringsFor(widget.lesson.targetId),
    );
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        // Leaving before Continue abandons the engagement (RT-009). Normal
        // Practice is not Review: the Review Scheduler is never consulted here,
        // so abandonment mutates neither the schedule nor lesson progress.
        if (didPop) {
          unawaited(_controller.abandonAttempt());
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.lesson.title)),
        body: ValueListenableBuilder<_NormalStage>(
          valueListenable: _stage,
          builder: (context, stage, _) {
            return switch (stage) {
              _NormalStage.practice => PracticeView(
                  controller: _controller,
                  instruction: instruction,
                  onFinished: _toResult,
                  exerciseContext: 'Practice · ${widget.lesson.subtitle}',
                ),
              _NormalStage.result => ResultView(
                  snapshot: _controller.session.value,
                  onRetry: _retry,
                  onContinue: _continue,
                  canContinue: true,
                ),
            };
          },
        ),
      ),
    );
  }
}