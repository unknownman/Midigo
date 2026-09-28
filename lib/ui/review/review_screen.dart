import 'package:flutter/material.dart';

import '../../midi/application/midi_device_connection.dart';
import '../../midi/application/midi_device_discovery.dart';
import '../../midi/application/midi_event_stream.dart';
import '../../midi/application/raw_midi_export_sink.dart';
import '../../practice/application/learning_catalog.dart';
import '../../practice/application/lesson_progress_service.dart';
import '../../practice/application/review_scheduler.dart';
import '../../practice/domain/learning_lesson.dart';
import '../../practice/domain/practice_clock.dart';
import '../lesson/lesson_screen.dart';
import 'normal_practice_screen.dart';
import 'review_session_screen.dart';

/// Review Hub: every review-related action lives here (Review Scheduler
/// Contract §14). Skills the user is solid on are surfaced as working practice;
/// skills that are due appear as scheduled reviews.
///
/// * `Review` -> [ReviewSessionScreen]: completes the skill's reviews against
///   the shared scheduler.
/// * `Start` -> [NormalPracticeScreen]: practice the lesson without any review
///   effect.
/// * `Lesson` -> the normal lesson flow (Teach -> Practice -> Result).
/// * `Skip for Now` -> leave the item due again; no scheduler mutation.
/// * `Start All` -> reviews every due item in one session, in catalog order.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({
    super.key,
    required this.catalog,
    required this.discovery,
    required this.connection,
    required this.captureFactory,
    required this.progressService,
    required this.reviewScheduler,
    required this.clock,
    this.exportSink,
  });

  final LearningCatalog catalog;
  final MidiDeviceDiscovery discovery;
  final MidiDeviceConnection connection;
  final MidiEventStream Function() captureFactory;
  final LessonProgressService progressService;
  final ReviewScheduler reviewScheduler;
  final PracticeClock clock;
  final RawMidiExportSink? exportSink;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewEntry {
  const _ReviewEntry({required this.lesson, required this.item});

  final LearningLesson lesson;
  final ReviewItem item;
}

class _ReviewScreenState extends State<ReviewScreen> {
  Future<List<_ReviewEntry>> _load() async {
    final items = await widget.reviewScheduler.getReadyReviews();
    final entries = <_ReviewEntry>[];
    for (final item in items) {
      final lesson = widget.catalog.lessonByTargetId(item.skillId);
      if (lesson == null) {
        continue;
      }
      entries.add(_ReviewEntry(lesson: lesson, item: item));
    }
    return entries;
  }

  void _refresh() {
    setState(() {});
  }

  Future<void> _openReviews(List<String> skillIds) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReviewSessionScreen(
          skillIds: skillIds,
          catalog: widget.catalog,
          discovery: widget.discovery,
          connection: widget.connection,
          captureFactory: widget.captureFactory,
          progressService: widget.progressService,
          reviewScheduler: widget.reviewScheduler,
          clock: widget.clock,
        ),
      ),
    );
    _refresh();
  }

  Future<void> _openStart(LearningLesson lesson) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NormalPracticeScreen(
          lesson: lesson,
          catalog: widget.catalog,
          discovery: widget.discovery,
          connection: widget.connection,
          captureFactory: widget.captureFactory,
          progressService: widget.progressService,
          clock: widget.clock,
        ),
      ),
    );
    _refresh();
  }

  void _openLesson(LearningLesson lesson) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => LessonScreen(
              lesson: lesson,
              catalog: widget.catalog,
              discovery: widget.discovery,
              connection: widget.connection,
              captureFactory: widget.captureFactory,
              progressService: widget.progressService,
              clock: widget.clock,
              exportSink: widget.exportSink,
            ),
          ),
        )
        .then((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Review')),
      body: FutureBuilder<List<_ReviewEntry>>(
        future: _load(),
        builder: (context, snapshot) {
          final entries = snapshot.data;
          if (entries == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (entries.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.done_all, size: 48),
                  const SizedBox(height: 12),
                  Text("You're all caught up.", style: theme.textTheme.titleMedium),
                ],
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                entries.length == 1
                    ? '1 review ready'
                    : '${entries.length} reviews ready',
                key: const ValueKey('ready-count'),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const ValueKey('start-all'),
                icon: const Icon(Icons.playlist_play),
                label: const Text('Start All'),
                onPressed: () => _openReviews(
                  [for (final entry in entries) entry.item.skillId],
                ),
              ),
              const SizedBox(height: 12),
              for (final entry in entries)
                _ReviewTile(
                  entry: entry,
                  onReview: () => _openReviews([entry.item.skillId]),
                  onStart: () => _openStart(entry.lesson),
                  onLesson: () => _openLesson(entry.lesson),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({
    required this.entry,
    required this.onReview,
    required this.onStart,
    required this.onLesson,
  });

  final _ReviewEntry entry;
  final VoidCallback onReview;
  final VoidCallback onStart;
  final VoidCallback onLesson;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.music_note),
              title: Text(entry.lesson.title),
              subtitle: Text(entry.lesson.subtitle),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: onReview,
                  child: const Text('Review'),
                ),
                OutlinedButton(
                  onPressed: onStart,
                  child: const Text('Start'),
                ),
                TextButton(
                  onPressed: onLesson,
                  child: const Text('Lesson'),
                ),
                TextButton(
                  onPressed: () {
                    // Skip for Now: zero mutation. The item simply stays due
                    // and is refreshed with the next ready list.
                  },
                  child: const Text('Skip for Now'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}