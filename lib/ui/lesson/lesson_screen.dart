import 'package:flutter/material.dart';

import '../../midi/application/midi_device_connection.dart';
import '../../midi/application/midi_device_discovery.dart';
import '../../midi/application/midi_event_stream.dart';
import '../../midi/application/raw_midi_export_sink.dart';
import '../../practice/application/evaluation_flow.dart';
import '../../practice/application/lesson_progress_service.dart';
import '../../practice/application/practice_session_controller.dart';
import '../../practice/application/slice1_catalog.dart';
import '../../practice/domain/practice_clock.dart';
import 'practice_view.dart';
import 'result_view.dart';
import 'teach_view.dart';

enum _Stage { teach, practice, result }

class LessonScreen extends StatefulWidget {
  const LessonScreen({
    super.key,
    required this.discovery,
    required this.connection,
    required this.captureFactory,
    required this.progressService,
    required this.clock,
    this.exportSink,
  });

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
      final catalog = const Slice1Catalog();
      _controller = PracticeSessionController(
        discovery: widget.discovery,
        connection: widget.connection,
        captureFactory: widget.captureFactory,
        evaluation: const EvaluationFlowService(),
        progressService: widget.progressService,
        clock: widget.clock,
        targetProvider: () => catalog.buildCMajorBlockExercise().expectedTarget,
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

  Future<void> _continue() async {
    await _controller.disconnect();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('C Major')),
      body: ValueListenableBuilder<_Stage>(
        valueListenable: _stage,
        builder: (context, stage, _) {
          return switch (stage) {
            _Stage.teach => TeachView(
                progressService: widget.progressService,
                onStartPractice: _startPractice,
              ),
            _Stage.practice => PracticeView(
                controller: _ensureController,
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