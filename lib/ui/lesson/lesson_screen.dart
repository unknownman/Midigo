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
import '../../practice/application/practice_session_controller.dart';
import '../../practice/application/target_prompt.dart';
import '../../practice/domain/learning_lesson.dart';
import '../../practice/domain/learning_path.dart';
import '../../practice/domain/practice_clock.dart';
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
  late final PracticeSessionController _controller;
  bool _controllerBuilt = false;

  PracticeSessionController get _ensureController {
    if (!_controllerBuilt) {
      _controller = PracticeSessionController(
        discovery: widget.discovery,
        connection: widget.connection,
        captureFactory: widget.captureFactory,
        evaluation: const EvaluationFlowService(),
        progressService: widget.progressService,
        clock: widget.clock,
        targetProvider: () => widget.catalog.buildTarget(widget.lesson),
      );
      _controllerBuilt = true;
    }
    return _controller;
  }

  @override
  void dispose() {
    _stage.dispose();
    if (_controllerBuilt) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _startPractice() {
    setState(() {
      _stage.value = _Stage.practice;
    });
  }

  void _toResult() {
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

  /// Continues: opens the next lesson when it became available, otherwise
  /// returns to the Learning Path.
  Future<void> _continue() async {
    await _controller.disconnect();
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

  @override
  Widget build(BuildContext context) {
    final target = widget.catalog.buildTarget(widget.lesson);
    final instruction = LessonInstructionFactory().build(
      target: target,
      fingerings: const FingeringCatalog().fingeringsFor(widget.lesson.targetId),
    );
    return Scaffold(
      appBar: AppBar(title: Text(widget.lesson.title)),
      body: ValueListenableBuilder<_Stage>(
        valueListenable: _stage,
        builder: (context, stage, _) {
          return switch (stage) {
            _Stage.teach => TeachView(
                lesson: widget.lesson,
                noteNames: TargetPrompt.noteNames(target),
                pressInstruction: TargetPrompt.pressInstruction(target),
                instruction: instruction,
                onStartPractice: _startPractice,
              ),
            _Stage.practice => PracticeView(
                controller: _ensureController,
                instruction: instruction,
                onFinished: _toResult,
              ),
            _Stage.result => ResultView(
                snapshot: _controller.session.value,
                onRetry: _retry,
                onContinue: _continue,
              ),
          };
        },
      ),
    );
  }
}