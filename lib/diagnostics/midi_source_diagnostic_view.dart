import 'package:flutter/material.dart';

import '../midi/application/midi_device_connection.dart';
import '../midi/application/midi_device_discovery.dart';
import '../midi/application/midi_event_stream.dart';
import '../midi/application/midi_raw_event_capture.dart';
import '../midi/domain/midi_connection_error.dart';
import '../midi/domain/midi_connection_session.dart';
import '../midi/domain/midi_connection_state.dart';
import '../midi/domain/midi_source_info.dart';

class MidiSourceDiagnosticView extends StatefulWidget {
  const MidiSourceDiagnosticView({
    super.key,
    required this.discovery,
    required this.connection,
    this.captureFactory = _defaultCaptureStream,
  });

  final MidiDeviceDiscovery discovery;
  final MidiDeviceConnection connection;
  final MidiEventStream Function() captureFactory;

  static MidiEventStream _defaultCaptureStream() => MacosMidiEventStream();

  @override
  State<MidiSourceDiagnosticView> createState() =>
      _MidiSourceDiagnosticViewState();
}

class _MidiSourceDiagnosticViewState extends State<MidiSourceDiagnosticView> {
  late Future<List<MidiSourceInfo>> _sources;
  late final MidiRawEventCapture _capture;
  bool _busy = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _sources = widget.discovery.listSources();
    _capture = MidiRawEventCapture(widget.captureFactory());
  }

  @override
  void dispose() {
    _capture.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _sources = widget.discovery.listSources();
    });
  }

  Future<void> _connect(MidiSourceInfo source) async {
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final session = await widget.connection.connect(source);
      await _capture.start(session.sessionId);
    } on MidiConnectionException catch (e) {
      setState(() => _errorMessage = e.toString());
    } catch (e) {
      setState(() => _errorMessage = 'Connect failed: $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _disconnect() async {
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      await _capture.stop();
      await widget.connection.disconnect();
    } on MidiConnectionException catch (e) {
      setState(() => _errorMessage = e.toString());
    } catch (e) {
      setState(() => _errorMessage = 'Disconnect failed: $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String _stateLabel(MidiConnectionState state) {
    return switch (state) {
      MidiConnectionState.notConnected => 'Disconnected',
      MidiConnectionState.connecting => 'Connecting…',
      MidiConnectionState.connected => 'Connected',
      MidiConnectionState.disconnecting => 'Disconnecting…',
      MidiConnectionState.disconnected => 'Disconnected',
      MidiConnectionState.error => 'Error',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MIDI Sources'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<List<MidiSourceInfo>>(
        future: _sources,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Failed to list MIDI sources.',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontFamily: 'monospace')),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _refresh,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final sources = snapshot.data ?? const <MidiSourceInfo>[];
          if (sources.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('No MIDI sources detected.'),
                  _buildErrorBanner(),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sources.length + (_errorMessage != null ? 1 : 0),
            itemBuilder: (context, index) {
              if (_errorMessage != null && index == 0) {
                return _buildErrorBanner();
              }
              final source = sources[index - (_errorMessage != null ? 1 : 0)];
              return _buildSourceCard(context, source);
            },
          );
        },
      ),
    );
  }

  Widget _buildErrorBanner() {
    final message = _errorMessage;
    if (message == null) {
      return const SizedBox.shrink();
    }
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          message,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onErrorContainer,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }

  Widget _buildSourceCard(BuildContext context, MidiSourceInfo source) {
    final session = widget.connection.currentSession;
    final isConnectedToThis =
        session != null && session.deviceId == source.id;
    final theme = Theme.of(context);
    final name =
        source.name.isEmpty ? MidiSourceInfo.unnamed : source.name;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Manufacturer: ${source.manufacturer}'),
            Text('ID: ${source.id}'),
            const SizedBox(height: 8),
            _buildConnectionControls(source, session, isConnectedToThis),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionControls(
    MidiSourceInfo source,
    MidiConnectionSession? session,
    bool isConnectedToThis,
  ) {
    final state = widget.connection.state;
    if (isConnectedToThis && session != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Status: ${_stateLabel(state)}'),
          Text('Session: ${session.sessionId}'),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: _busy ? null : _disconnect,
            child: const Text('Disconnect'),
          ),
          const SizedBox(height: 12),
          _buildCapturePanel(),
        ],
      );
    }

    final canConnect = !_busy &&
        state != MidiConnectionState.connected &&
        state != MidiConnectionState.connecting &&
        session == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Status: ${_stateLabel(state)}'),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: canConnect ? () => _connect(source) : null,
          child: const Text('Connect'),
        ),
      ],
    );
  }

  Widget _buildCapturePanel() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ValueListenableBuilder<int>(
          valueListenable: _capture.revision,
          builder: (context, _, _) {
            final events = _capture.buffer.events;
            final headerText = 'Captured Events: ${events.length}';
            final rows = events.length > _maxCaptureDisplayRows
                ? events.sublist(events.length - _maxCaptureDisplayRows)
                : events;
            final lines = <String>[
              '${'#'.padRight(5)}${'Time'.padRight(10)}'
                  '${'Type'.padRight(9)}Ch  Note  Vel',
              for (final event in rows.reversed)
                '${'${event.seq}'.padRight(5)}'
                    '${'${event.appMonotonicTsMs}'.padRight(10)}'
                    '${event.messageType.displayLabel.padRight(9)}'
                    '${event.channel ?? '-'}    '
                    '${event.note ?? '-'}    '
                    '${event.velocity ?? '-'}',
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(headerText, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      lines.join('\n'),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
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

  static const int _maxCaptureDisplayRows = 18;
}