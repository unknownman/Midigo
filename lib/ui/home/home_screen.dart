import 'package:flutter/material.dart';

import '../../diagnostics/midi_source_diagnostic_view.dart';
import '../../midi/application/midi_device_connection.dart';
import '../../midi/application/midi_device_discovery.dart';
import '../../midi/application/midi_event_stream.dart';
import '../../midi/application/raw_midi_export_sink.dart';
import '../../practice/application/learning_catalog.dart';
import '../../practice/application/learning_path_service.dart';
import '../../practice/application/lesson_progress_service.dart';
import '../../practice/domain/learning_path.dart';
import '../../practice/domain/practice_clock.dart';
import '../learning_path/learning_path_screen.dart';
import '../review/review_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.catalog,
    required this.discovery,
    required this.connection,
    required this.captureFactory,
    required this.progressService,
    required this.clock,
    this.exportSink,
  });

  final LearningCatalog catalog;
  final MidiDeviceDiscovery discovery;
  final MidiDeviceConnection connection;
  final MidiEventStream Function() captureFactory;
  final LessonProgressService progressService;
  final PracticeClock clock;
  final RawMidiExportSink? exportSink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('MIDI Tutor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_input_component),
            tooltip: 'Developer MIDI diagnostics',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MidiSourceDiagnosticView(
                    discovery: discovery,
                    connection: connection,
                    captureFactory: captureFactory,
                    exportSink: exportSink,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Welcome back', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 16),
          _LearningPathCard(
            catalog: catalog,
            discovery: discovery,
            connection: connection,
            captureFactory: captureFactory,
            progressService: progressService,
            clock: clock,
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.event_note),
              title: const Text('Review'),
              subtitle: const Text('No reviews due'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ReviewScreen(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LearningPathCard extends StatelessWidget {
  const _LearningPathCard({
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: LearningPathService(
        catalog: catalog,
        progressService: progressService,
      ).loadPath(),
      builder: (context, snapshot) {
        final path = snapshot.data;
        final current = path == null ? null : _currentLesson(path);
        final Card card;
        if (current == null) {
          card = Card(
            child: ListTile(
              leading: const Icon(Icons.school),
              title: const Text('Learning Path'),
              subtitle: const Text('Loading…'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openPath(context),
            ),
          );
        } else {
          card = Card(
            child: ListTile(
              leading: const Icon(Icons.school),
              title: const Text('Learning Path'),
              subtitle: Text(
                '${current.lesson.subtitle} · ${current.progress.stars} / 10 stars',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openPath(context),
            ),
          );
        }
        return card;
      },
    );
  }

  LessonState<dynamic> _currentLesson(LearningPath<dynamic> path) {
    for (final state in path.lessons) {
      if (state.availability != LessonAvailability.completed) {
        return state;
      }
    }
    return path.lessons.first;
  }

  void _openPath(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LearningPathScreen(
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
}