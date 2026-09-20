import 'package:flutter/material.dart';

import 'diagnostics/midi_source_diagnostic_view.dart';
import 'midi/application/midi_device_connection.dart';
import 'midi/application/midi_device_discovery.dart';

void main() {
  runApp(const MidiTutorApp());
}

class MidiTutorApp extends StatelessWidget {
  const MidiTutorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MIDI Tutor',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: MidiSourceDiagnosticView(
        discovery: MacosMidiDeviceDiscovery(),
        connection: MacosMidiDeviceConnection(),
      ),
    );
  }
}