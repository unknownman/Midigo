import 'package:flutter/material.dart';

import '../../midi/application/midi_device_connection.dart';
import '../../midi/application/midi_device_discovery.dart';
import '../../midi/application/midi_event_stream.dart';
import '../../practice/application/learning_catalog.dart';
import '../../practice/application/learning_path_service.dart';
import '../../practice/application/lesson_progress_service.dart';
import '../../practice/domain/learning_lesson.dart';
import '../../practice/domain/learning_path.dart';
import '../../practice/domain/practice_clock.dart';
import '../lesson/lesson_screen.dart';

class LearningPathScreen extends StatelessWidget {
  const LearningPathScreen({
    super.key,
    required this.catalog,
    required this.discovery,
    required this.connection,
    required this.captureFactory,
    required this.progressService,
    required this.clock,
  });

  final LearningCatalog catalog;
  final MidiDeviceDiscovery discovery;
  final MidiDeviceConnection connection;
  final MidiEventStream Function() captureFactory;
  final LessonProgressService progressService;
  final PracticeClock clock;

  Future<LearningPath<dynamic>> _load() async {
    final service = LearningPathService(
      catalog: catalog,
      progressService: progressService,
    );
    return await service.loadPath();
  }

  void _openLesson(BuildContext context, LearningLesson lesson) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LessonScreen(
          lesson: lesson,
          catalog: catalog,
          discovery: discovery,
          connection: connection,
          captureFactory: captureFactory,
          progressService: progressService,
          clock: clock,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Learning Path')),
      body: FutureBuilder<LearningPath<dynamic>>(
        future: _load(),
        builder: (context, snapshot) {
          final path = snapshot.data;
          if (path == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final state in path.lessons)
                _LessonTile(state: state, onOpen: () => _openLesson(context, state.lesson)),
            ],
          );
        },
      ),
    );
  }
}

/// One deterministic path row. Locked lessons are shown disabled; everything
/// else opens the lesson so learners may revisit/re-practice.
class _LessonTile extends StatelessWidget {
  const _LessonTile({required this.state, required this.onOpen});

  final LessonState<dynamic> state;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final availability = state.availability;
    final locked = availability == LessonAvailability.locked;
    final completed = availability == LessonAvailability.completed;

    final IconData leadingIcon = locked
        ? Icons.lock
        : completed
            ? Icons.check_circle
            : Icons.music_note;

    return Card(
      child: ListTile(
        enabled: !locked,
        leading: Icon(leadingIcon),
        title: Text(
          'Lesson ${state.lesson.order} · ${state.lesson.title}',
          style: locked ? theme.textTheme.bodyLarge?.copyWith(color: theme.disabledColor) : null,
        ),
        subtitle: Text(
          locked
              ? 'Locked'
              : completed
                  ? '${state.progress.stars} / 10 stars · completed'
                  : '${state.progress.stars} / 10 stars',
        ),
        trailing: locked ? null : const Icon(Icons.chevron_right),
        onTap: locked ? null : onOpen,
      ),
    );
  }
}