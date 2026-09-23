import 'dart:io';

import 'package:flutter/material.dart';

import 'midi/application/midi_device_connection.dart';
import 'midi/application/midi_device_discovery.dart';
import 'midi/application/midi_event_stream.dart';
import 'practice/application/learning_catalog.dart';
import 'practice/application/lesson_progress_service.dart';
import 'practice/application/lesson_progress_store.dart';
import 'practice/application/json_lesson_progress_store.dart';
import 'practice/domain/practice_clock.dart';
import 'ui/home/home_screen.dart';

void main() {
  runApp(const MidiTutorApp());
}

/// Default macOS Application Support directory for lesson progress.
Directory _defaultProgressRoot() {
  final home = Platform.environment['HOME'];
  return Directory(
    '$home${Platform.pathSeparator}Library${Platform.pathSeparator}'
    'Application Support${Platform.pathSeparator}Midigo',
  );
}

class MidiTutorApp extends StatefulWidget {
  const MidiTutorApp({
    super.key,
    this.discovery,
    this.connection,
    this.captureFactory,
    this.progressStore,
    this.clock,
  });

  final MidiDeviceDiscovery? discovery;
  final MidiDeviceConnection? connection;
  final MidiEventStream Function()? captureFactory;
  final LessonProgressStore? progressStore;
  final PracticeClock? clock;

  @override
  State<MidiTutorApp> createState() => _MidiTutorAppState();
}

class _MidiTutorAppState extends State<MidiTutorApp> {
  late final MidiDeviceDiscovery _discovery;
  late final MidiDeviceConnection _connection;
  late final MidiEventStream Function() _captureFactory;
  late final LessonProgressService _progressService;
  late final PracticeClock _clock;

  @override
  void initState() {
    super.initState();
    _discovery = widget.discovery ?? MacosMidiDeviceDiscovery();
    _connection = widget.connection ?? MacosMidiDeviceConnection();
    _captureFactory = widget.captureFactory ?? (() => MacosMidiEventStream());
    final store = widget.progressStore ??
        JsonLessonProgressStore(root: _defaultProgressRoot());
    _progressService = LessonProgressService(store: store);
    _clock = widget.clock ?? const SystemPracticeClock();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MIDI Tutor',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: HomeScreen(
        catalog: const LearningCatalog(),
        discovery: _discovery,
        connection: _connection,
        captureFactory: _captureFactory,
        progressService: _progressService,
        clock: _clock,
      ),
    );
  }
}