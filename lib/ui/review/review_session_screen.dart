import 'dart:async';

import 'package:flutter/material.dart';

import '../../midi/application/midi_device_connection.dart';
import '../../midi/application/midi_device_discovery.dart';
import '../../midi/application/midi_event_stream.dart';
import '../../midi/domain/evaluation_result.dart';
import '../../practice/application/evaluation_flow.dart';
import '../../practice/application/fingering_data.dart';
import '../../practice/application/learning_catalog.dart';
import '../../practice/application/lesson_instruction.dart';
import '../../practice/application/lesson_progress_service.dart';
import '../../practice/application/practice_sequence_catalog.dart';
import '../../practice/application/practice_session_controller.dart';
import '../../practice/application/review_scheduler.dart';
import '../../practice/domain/learning_lesson.dart';
import '../../practice/domain/practice_clock.dart';
import '../lesson/practice_view.dart';
import '../widgets/star_display.dart';

enum _ReviewStage { practice, result }

/// One scheduled-review session for an ordered list of due [skillIds].
///
/// Reuses the existing Practice Runtime + [EvaluationFlowService] pipeline
/// (H2.9.6): the learner plays the exercise, finishing produces the frozen
/// result, and the commit point is the Review Result screen's Continue
/// (H2.9.7). Review must never modify lesson progress/mastery, so its
/// controllers run with `recordLessonProgress: false` (H2.9.10).
class ReviewSessionScreen extends StatefulWidget {
  const ReviewSessionScreen({
    super.key,
    required this.skillIds,
    required this.catalog,
    required this.discovery,
    required this.connection,
    required this.captureFactory,
    required this.progressService,
    required this.reviewScheduler,
    required this.clock,
  });

  final List<String> skillIds;
  final LearningCatalog catalog;
  final MidiDeviceDiscovery discovery;
  final MidiDeviceConnection connection;
  final MidiEventStream Function() captureFactory;
  final LessonProgressService progressService;
  final ReviewScheduler reviewScheduler;
  final PracticeClock clock;

  @override
  State<ReviewSessionScreen> createState() => _ReviewSessionScreenState();
}

class _ReviewSessionScreenState extends State<ReviewSessionScreen> {
  late int _index;
  PracticeSessionController? _controller;
  final ValueNotifier<_ReviewStage> _stage =
      ValueNotifier<_ReviewStage>(_ReviewStage.practice);

  /// Guards a scheduler commit in flight so a double-tap can never commit a
  /// response twice (exactly one response per review item, H2.9.7).
  bool _committing = false;

  String get _skillId => widget.skillIds[_index];

  @override
  void initState() {
    super.initState();
    _index = 0;
    _controller = _buildController();
  }

  PracticeSessionController _buildController() {
    final skillId = _skillId;
    return PracticeSessionController(
      discovery: widget.discovery,
      connection: widget.connection,
      captureFactory: widget.captureFactory,
      evaluation: const EvaluationFlowService(),
      progressService: widget.progressService,
      clock: widget.clock,
      exercise: PracticeSequenceCatalog(widget.catalog)
          .exerciseForTargetId(skillId),
      targetFactory: widget.catalog.buildTargetForTargetId,
      recordLessonProgress: false,
    );
  }

  @override
  void dispose() {
    _stage.dispose();
    _controller?.dispose();
    super.dispose();
  }

  /// Commits exactly one scheduler response for the current item, then moves
  /// on. [reviewResponseFor] maps the frozen result: 3+ stars -> successful,
  /// 0..2 -> unsuccessful, NEP/abandoned -> null (never reach the scheduler).
  ///
  /// This is also the completion boundary of the review practice interaction:
  /// Review is ordinary practice against the same Practice Runtime, so it uses
  /// the same interaction-end path as the Start/lesson flows - there is no
  /// Review-specific lifecycle here.
  Future<void> _commitAndAdvance() async {
    if (_committing) {
      return;
    }
    final controller = _controller;
    if (controller == null) {
      return;
    }
    _committing = true;
    final response = reviewResponseFor(
      controller.session.value.latestCompletedResult,
    );
    controller.completeInteraction();
    if (response != null) {
      await widget.reviewScheduler.recordReviewResponse(_skillId, response);
    }
    _advance();
  }

  /// I Already Know: an explicit action that commits an `iAlreadyKnow`
  /// response without any MIDI practice or evaluation (H2.9.10).
  Future<void> _iAlreadyKnow() async {
    if (_committing) {
      return;
    }
    _committing = true;
    await widget.reviewScheduler.recordReviewResponse(
      _skillId,
      ReviewResponse.iAlreadyKnow,
    );
    _advance();
  }

  void _retry() {
    _controller?.retryAttempt();
    _stage.value = _ReviewStage.practice;
  }

  void _advance() {
    _controller?.dispose();
    _controller = null;
    _index += 1;
    if (_index >= widget.skillIds.length) {
      Navigator.of(context).pop();
      return;
    }
    _committing = false;
    setState(() {
      _controller = _buildController();
      _stage.value = _ReviewStage.practice;
    });
  }

  /// Leaving the Review session before committing is an abandonment.
  ///
  /// A Back/exit is forwarded to the controller, which abandons the open
  /// interaction (RT-009). It deliberately does NOT touch the scheduler: only
  /// advancing past the Review Result via [_commitAndAdvance] commits a response,
  /// so the item simply stays ready and due (Review Scheduler Contract §13.5).
  void _handlePop(bool didPop) {
    if (didPop) {
      unawaited(_controller?.abandonAttempt());
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) => _handlePop(didPop),
      child: Scaffold(
        appBar: AppBar(title: const Text('Review')),
        body: ValueListenableBuilder<_ReviewStage>(
          valueListenable: _stage,
          builder: (context, stage, _) {
            final lesson = widget.catalog.lessonByTargetId(_skillId);
            return switch (stage) {
              _ReviewStage.practice => _buildPractice(lesson),
              _ReviewStage.result => _buildResult(lesson),
            };
          },
        ),
      ),
    );
  }

  Widget _buildPractice(LearningLesson? lesson) {
    final controller = _controller!;
    final target = widget.catalog.buildTargetForTargetId(_skillId);
    final instruction = LessonInstructionFactory().build(
      target: target,
      fingerings: const FingeringCatalog().fingeringsFor(_skillId),
    );
    return ValueListenableBuilder<PracticeSessionSnapshot>(
      valueListenable: controller.session,
      builder: (context, snapshot, _) {
        // I Already Know is available whenever no attempt is live and no
        // result is pending - even before connecting to a MIDI keyboard.
        // Once an attempt is started or a result produced, it is hidden.
        final canIAlreadyKnow =
            !snapshot.attemptInProgress && snapshot.latestCompletedResult == null;
        return Column(
          children: [
            Expanded(
              child: PracticeView(
                controller: controller,
                instruction: instruction,
                onFinished: () => _stage.value = _ReviewStage.result,
                exerciseContext: 'Review · ${lesson?.title ?? ''}',
              ),
            ),
            if (canIAlreadyKnow)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: OutlinedButton.icon(
                  key: const ValueKey('i-already-know'),
                  icon: const Icon(Icons.verified),
                  label: const Text('I Already Know'),
                  onPressed: _confirmIAlreadyKnow,
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _confirmIAlreadyKnow() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('I Already Know'),
        content: const Text(
          'If you already know this, we will check in again in a while.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('confirm-i-already-know'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Mark as Known'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _iAlreadyKnow();
    }
  }

  Widget _buildResult(LearningLesson? lesson) {
    final controller = _controller!;
    return ValueListenableBuilder<PracticeSessionSnapshot>(
      valueListenable: controller.session,
      builder: (context, snapshot, _) {
        return _ReviewResultView(
          snapshot: snapshot,
          lessonTitle: lesson?.title ?? '',
          onRetry: _retry,
          onContinue: _commitAndAdvance,
        );
      },
    );
  }
}

/// Review Result: stars or not-enough-performance plus Retry / Continue.
///
/// Deliberately mirrors the learner-facing review vocabulary and never shows
/// lesson progress (this screen produces no lesson progress by construction).
class _ReviewResultView extends StatelessWidget {
  const _ReviewResultView({
    required this.snapshot,
    required this.lessonTitle,
    required this.onRetry,
    required this.onContinue,
  });

  final PracticeSessionSnapshot snapshot;
  final String lessonTitle;
  final VoidCallback onRetry;
  final VoidCallback onContinue;

  String get _message {
    final result = snapshot.latestCompletedResult;
    if (result is EvaluatedResult) {
      return result.stars >= 3
          ? 'Nice work — we will check in again soon.'
          : 'Keep practicing — we will check in again soon.';
    }
    return 'Not enough performance to evaluate.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Review', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('$lessonTitle · Your Review', style: theme.textTheme.titleMedium),
        const SizedBox(height: 24),
        ..._resultSection(theme),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: onContinue,
                child: const Text('Continue'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _resultSection(ThemeData theme) {
    final result = snapshot.latestCompletedResult;
    if (result is EvaluatedResult) {
      return <Widget>[
        Center(
          child: KeyedSubtree(
            key: const ValueKey('review-stars'),
            child: StarDisplay(filled: result.stars, capacity: 5, size: 32),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            _message,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ),
      ];
    }
    return <Widget>[
      Icon(Icons.music_off, size: 32, color: theme.colorScheme.outline),
      const SizedBox(height: 8),
      Center(
        child: Text(
          _message,
          key: const ValueKey('review-nep-message'),
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
      ),
    ];
  }
}