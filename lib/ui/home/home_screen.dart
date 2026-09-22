import 'package:flutter/material.dart';

import '../../diagnostics/midi_source_diagnostic_view.dart';
import '../../midi/application/midi_device_connection.dart';
import '../../midi/application/midi_device_discovery.dart';
import '../../midi/application/midi_event_stream.dart';
import '../../midi/application/raw_midi_export_sink.dart';
import '../../practice/application/lesson_progress_service.dart';
import '../../practice/application/slice1_catalog.dart';
import '../../practice/domain/practice_clock.dart';
import '../learning_path/learning_path_screen.dart';
import '../review/review_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
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
    required this.discovery,
    required this.connection,
    required this.captureFactory,
    required this.progressService,
    required this.clock,
  });

  final MidiDeviceDiscovery discovery;
  final MidiDeviceConnection connection;
  final MidiEventStream Function() captureFactory;
  final LessonProgressService progressService;
  final PracticeClock clock;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: progressService.loadProgress(Slice1Catalog.cMajorTargetId),
      builder: (context, snapshot) {
        final stars = snapshot.data?.stars ?? 0;
        return Card(
          child: ListTile(
            leading: const Icon(Icons.school),
            title: const Text('Learning Path'),
            subtitle: Row(
              children: [
                const Text('C Major · '),
                Text(
                  '$stars / 10 stars',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                for (var i = 0; i < stars; i++) const Text('★'),
              ],
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LearningPathScreen(
                    discovery: discovery,
                    connection: connection,
                    captureFactory: captureFactory,
                    progressService: progressService,
                    clock: clock,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}