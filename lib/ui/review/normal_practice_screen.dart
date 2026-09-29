import 'package:flutter/material.dart';

import '../../midi/application/midi_device_connection.dart';
import '../../midi/application/midi_device_discovery.dart';
import '../../midi/application/midi_event_stream.dart';
import '../../practice/application/evaluation_flow.dart';
import '../../practice/application/fingering_data.dart';
import '../../practice/application/learning_catalog.dart';
import '../../practice/application/lesson_instruction.dart';
import '../../practice/application/lesson_progress_service.dart';
import '../../practice/application/practice_session_controller.dart';
import '../../practice/domain/learning_lesson.dart';
import '../../practice/domain/practice_clock.dart';
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
  });

  final LearningLesson lesson;
  final LearningCatalog catalog;
  final MidiDeviceDiscovery discovery;
  final MidiDeviceConnection connection;
  final MidiEventStream Function() captureFactory;
  final LessonProgressService progressService;
  final PracticeClock clock;

  @override
  State<NormalPracticeScreen> createState() => _NormalPracticeScreenState();
}

class _NormalPracticeScreenState extends State<NormalPracticeScreen> {
  final ValueNotifier<_NormalStage> _stage =
      ValueNotifier<_NormalStage>(_NormalStage.practice);
  late final PracticeSessionController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PracticeSessionController(
      discovery: widget.discovery,
      connection: widget.connection,
      captureFactory: widget.captureFactory,
      evaluation: const EvaluationFlowService(),
      progressService: widget.progressService,
      clock: widget.clock,
      targetProvider: () =>
          widget.catalog.buildTargetForTargetId(widget.lesson.targetId),
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
    final target = widget.catalog.buildTargetForTargetId(widget.lesson.targetId);
    final instruction = LessonInstructionFactory().build(
      target: target,
      fingerings: const FingeringCatalog().fingeringsFor(widget.lesson.targetId),
    );
    return Scaffold(
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
    );
  }
}