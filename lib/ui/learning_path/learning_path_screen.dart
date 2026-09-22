import 'package:flutter/material.dart';

import '../lesson/lesson_screen.dart';
import '../../midi/application/midi_device_connection.dart';
import '../../midi/application/midi_device_discovery.dart';
import '../../midi/application/midi_event_stream.dart';
import '../../practice/application/lesson_progress_service.dart';
import '../../practice/application/slice1_catalog.dart';
import '../../practice/domain/practice_clock.dart';

class LearningPathScreen extends StatelessWidget {
  const LearningPathScreen({
    super.key,
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
    return Scaffold(
      appBar: AppBar(title: const Text('Learning Path')),
      body: FutureBuilder(
        future: progressService.loadProgress(Slice1Catalog.cMajorTargetId),
        builder: (context, snapshot) {
          final stars = snapshot.data?.stars ?? 0;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.music_note),
                  title: const Text('Lesson 1 · C Major'),
                  subtitle: Text('$stars / 10 stars'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => LessonScreen(
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
              ),
            ],
          );
        },
      ),
    );
  }
}