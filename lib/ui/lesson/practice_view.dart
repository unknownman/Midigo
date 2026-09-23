import 'package:flutter/material.dart';

import 'package:miditutor/midi/domain/midi_source_info.dart';

import '../../practice/application/practice_session_controller.dart';

class PracticeView extends StatefulWidget {
  const PracticeView({
    super.key,
    required this.controller,
    required this.onFinished,
  });

  final PracticeSessionController controller;
  final VoidCallback onFinished;

  @override
  State<PracticeView> createState() => _PracticeViewState();
}

class _PracticeViewState extends State<PracticeView> {
  late Future<List<MidiSourceInfo>> _sources;

  @override
  void initState() {
    super.initState();
    _sources = widget.controller.listSources();
  }

  void _refresh() {
    setState(() {
      _sources = widget.controller.listSources();
    });
  }

  Future<void> _connect(MidiSourceInfo source) async {
    await widget.controller.connect(source);
    await widget.controller.startAttempt();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _finish() async {
    await widget.controller.endAttempt();
    if (mounted) {
      widget.onFinished();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PracticeSessionSnapshot>(
      valueListenable: widget.controller.session,
      builder: (context, snapshot, _) {
        if (!snapshot.isConnected) {
          return _buildConnectionPanel(context, snapshot);
        }
        return _buildPracticePanel(context, snapshot);
      },
    );
  }

  Widget _buildConnectionPanel(BuildContext context, PracticeSessionSnapshot snapshot) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Practice', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('Connect your MIDI keyboard to start.', style: theme.textTheme.bodyLarge),
        if (snapshot.errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            snapshot.errorMessage!,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        FutureBuilder<List<MidiSourceInfo>>(
          future: _sources,
          builder: (context, futureSnapshot) {
            if (futureSnapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final sources = futureSnapshot.data ?? const <MidiSourceInfo>[];
            if (sources.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('No MIDI sources detected.'),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _refresh,
                    child: const Text('Refresh'),
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final source in sources)
                  Card(
                    child: ListTile(
                      title: Text(source.name.isEmpty
                          ? MidiSourceInfo.unnamed
                          : source.name),
                      subtitle: Text(source.manufacturer),
                      trailing: FilledButton(
                        onPressed: () => _connect(source),
                        child: const Text('Connect'),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildPracticePanel(BuildContext context, PracticeSessionSnapshot snapshot) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Practice · ${snapshot.sourceName}', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(snapshot.targetDescription, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(snapshot.playInstruction),
        const SizedBox(height: 16),
        if (snapshot.errorMessage != null) ...[
          Text(snapshot.errorMessage!, style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: 12),
        ],
        FilledButton.icon(
          icon: const Icon(Icons.check),
          label: const Text('Finish Attempt'),
          onPressed: snapshot.attemptInProgress ? _finish : null,
        ),
      ],
    );
  }
}