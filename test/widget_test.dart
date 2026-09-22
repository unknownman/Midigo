import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/diagnostics/midi_source_diagnostic_view.dart';
import 'package:miditutor/midi/application/midi_device_connection.dart';
import 'package:miditutor/midi/application/midi_device_discovery.dart';
import 'package:miditutor/midi/application/midi_event_stream.dart';
import 'package:miditutor/midi/application/raw_midi_export_sink.dart';
import 'package:miditutor/midi/domain/midi_source_info.dart';
import 'package:miditutor/midi/domain/raw_midi_event.dart';

class _FakeExportSink implements RawMidiExportSink {
  _FakeExportSink();

  String writtenFilename = '';
  String writtenContent = '';
  int writeCount = 0;

  @override
  Future<String> write({required String filename, required String content}) async {
    writtenFilename = filename;
    writtenContent = content;
    writeCount += 1;
    return '/tmp/$filename';
  }
}

class _CountingEventStream implements MidiEventStream {
  final _controller = StreamController<RawMidiEvent>();
  int listenCount = 0;

  @override
  Stream<RawMidiEvent> get events {
    listenCount += 1;
    return _controller.stream.asBroadcastStream();
  }
}

void main() {
  const channel = MethodChannel('piano_midi/macos');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('shows a connected MIDI source', (WidgetTester tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      return <dynamic>[
        <String, dynamic>{
          'id': 123456,
          'name': 'My 25-Key Keyboard',
          'manufacturer': 'Example Manufacturer',
        },
      ];
    });

    await tester.pumpWidget(MaterialApp(
      home: MidiSourceDiagnosticView(
        discovery: MacosMidiDeviceDiscovery(),
        connection: MacosMidiDeviceConnection(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('My 25-Key Keyboard'), findsOneWidget);
    expect(find.text('Manufacturer: Example Manufacturer'), findsOneWidget);
    expect(find.text('ID: 123456'), findsOneWidget);
    expect(find.text('Status: Disconnected'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Connect'), findsOneWidget);
  });

  testWidgets('connects to a source and shows the session then disconnects',
      (WidgetTester tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'listMidiSources') {
        return <dynamic>[
          <String, dynamic>{
            'id': 123456,
            'name': 'My 25-Key Keyboard',
            'manufacturer': 'Example Manufacturer',
          },
        ];
      }
      if (call.method == 'connectMidiSource') {
        return <String, dynamic>{
          'sessionId': 'session-abc',
          'deviceId': '123456',
          'connectionType': 'USB',
        };
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      const EventChannel('piano_midi/macos/events'),
      MockStreamHandler.inline(
        onListen: (arguments, events) {},
        onCancel: (arguments) {},
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: MidiSourceDiagnosticView(
        discovery: MacosMidiDeviceDiscovery(),
        connection: MacosMidiDeviceConnection(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Connect'));
    await tester.pumpAndSettle();

    expect(find.text('Status: Connected'), findsOneWidget);
    expect(find.text('Session: session-abc'), findsOneWidget);
    expect(find.text('Captured Events: 0'), findsOneWidget);

    final disconnectButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Disconnect'),
    );
    await tester.runAsync<void>(() async {
      disconnectButton.onPressed!();
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    expect(find.text('Status: Disconnected'), findsOneWidget);
    expect(find.text('Session: session-abc'), findsNothing);
  });

  testWidgets('displays live captured raw MIDI events while connected',
      (WidgetTester tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'listMidiSources') {
        return <dynamic>[
          <String, dynamic>{
            'id': 123456,
            'name': 'My 25-Key Keyboard',
            'manufacturer': 'Example Manufacturer',
          },
        ];
      }
      if (call.method == 'connectMidiSource') {
        return <String, dynamic>{
          'sessionId': 'session-abc',
          'deviceId': '123456',
          'connectionType': 'USB',
        };
      }
      return null;
    });

    MockStreamHandlerEventSink? midiSink;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      const EventChannel('piano_midi/macos/events'),
      MockStreamHandler.inline(
        onListen: (arguments, events) {
          midiSink = events;
        },
        onCancel: (arguments) {},
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: MidiSourceDiagnosticView(
        discovery: MacosMidiDeviceDiscovery(),
        connection: MacosMidiDeviceConnection(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Captured Events: 0'), findsOneWidget);
    expect(find.text('Capture: Active'), findsOneWidget);
    expect(find.text('Connection: USB'), findsOneWidget);

    midiSink!.success(<String, Object?>{
      'sessionId': 'session-abc',
      'deviceId': '123456',
      'connectionType': 'USB',
      'seq': 1,
      'appMonotonicTsMs': 777000,
      'messageType': 'note_on',
      'channel': 0,
      'note': 60,
      'velocity': 83,
      'rawBytes': <int>[0x90, 60, 83],
    });
    midiSink!.success(<String, Object?>{
      'sessionId': 'session-abc',
      'deviceId': '123456',
      'connectionType': 'USB',
      'seq': 2,
      'appMonotonicTsMs': 444321,
      'messageType': 'note_off',
      'channel': 0,
      'note': 60,
      'velocity': 0,
      'rawBytes': <int>[0x80, 60, 0],
    });
    midiSink!.success(<String, Object?>{
      'sessionId': 'session-abc',
      'deviceId': '123456',
      'connectionType': 'USB',
      'seq': 3,
      'appMonotonicTsMs': 555111,
      'messageType': 'other',
      'channel': 0,
      'note': 64,
      'velocity': 7,
      'rawBytes': <int>[0xB0, 64, 7],
    });
    await tester.pumpAndSettle();

    expect(find.text('Captured Events: 3'), findsOneWidget);
    expect(find.textContaining('[144,60,83]'), findsOneWidget);
    expect(find.textContaining('[128,60,0]'), findsOneWidget);
    expect(find.textContaining('[176,64,7]'), findsOneWidget);
    expect(find.textContaining('note_on'), findsOneWidget);
    expect(find.textContaining('note_off'), findsOneWidget);
    expect(find.textContaining('other'), findsOneWidget);
    expect(find.textContaining('777000'), findsOneWidget);
  });

  testWidgets('preserves Note-On velocity 0 as note_on in the raw display',
      (WidgetTester tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'listMidiSources') {
        return <dynamic>[
          <String, dynamic>{
            'id': 123456,
            'name': 'My 25-Key Keyboard',
            'manufacturer': 'Example Manufacturer',
          },
        ];
      }
      if (call.method == 'connectMidiSource') {
        return <String, dynamic>{
          'sessionId': 'session-abc',
          'deviceId': '123456',
          'connectionType': 'USB',
        };
      }
      return null;
    });

    MockStreamHandlerEventSink? midiSink;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      const EventChannel('piano_midi/macos/events'),
      MockStreamHandler.inline(
        onListen: (arguments, events) {
          midiSink = events;
        },
        onCancel: (arguments) {},
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: MidiSourceDiagnosticView(
        discovery: MacosMidiDeviceDiscovery(),
        connection: MacosMidiDeviceConnection(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Connect'));
    await tester.pumpAndSettle();

    midiSink!.success(<String, Object?>{
      'sessionId': 'session-abc',
      'deviceId': '123456',
      'connectionType': 'USB',
      'seq': 4,
      'appMonotonicTsMs': 999,
      'messageType': 'note_on',
      'channel': 0,
      'note': 60,
      'velocity': 0,
      'rawBytes': <int>[0x90, 60, 0],
    });
    await tester.pumpAndSettle();

    expect(find.textContaining('note_on'), findsOneWidget);
    expect(find.textContaining('note_off'), findsNothing);
    expect(find.textContaining('[144,60,0]'), findsOneWidget);
  });

  testWidgets('clear capture resets the event view without disconnecting',
      (WidgetTester tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'listMidiSources') {
        return <dynamic>[
          <String, dynamic>{
            'id': 123456,
            'name': 'My 25-Key Keyboard',
            'manufacturer': 'Example Manufacturer',
          },
        ];
      }
      if (call.method == 'connectMidiSource') {
        return <String, dynamic>{
          'sessionId': 'session-abc',
          'deviceId': '123456',
          'connectionType': 'USB',
        };
      }
      return null;
    });

    MockStreamHandlerEventSink? midiSink;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      const EventChannel('piano_midi/macos/events'),
      MockStreamHandler.inline(
        onListen: (arguments, events) {
          midiSink = events;
        },
        onCancel: (arguments) {},
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: MidiSourceDiagnosticView(
        discovery: MacosMidiDeviceDiscovery(),
        connection: MacosMidiDeviceConnection(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Connect'));
    await tester.pumpAndSettle();

    midiSink!.success(<String, Object?>{
      'sessionId': 'session-abc',
      'deviceId': '123456',
      'connectionType': 'USB',
      'seq': 1,
      'appMonotonicTsMs': 1000,
      'messageType': 'note_on',
      'channel': 0,
      'note': 60,
      'velocity': 83,
      'rawBytes': <int>[0x90, 60, 83],
    });
    midiSink!.success(<String, Object?>{
      'sessionId': 'session-abc',
      'deviceId': '123456',
      'connectionType': 'USB',
      'seq': 2,
      'appMonotonicTsMs': 2000,
      'messageType': 'note_off',
      'channel': 0,
      'note': 60,
      'velocity': 0,
      'rawBytes': <int>[0x80, 60, 0],
    });
    await tester.pumpAndSettle();
    expect(find.text('Captured Events: 2'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Clear Capture'));
    await tester.pumpAndSettle();

    expect(find.text('Captured Events: 0'), findsOneWidget);
    expect(find.textContaining('[144'), findsNothing);
    expect(find.text('Session: session-abc'), findsOneWidget);
    expect(find.text('Status: Connected'), findsOneWidget);
  });

  testWidgets('export JSONL writes the complete capture through the exporter',
      (WidgetTester tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'listMidiSources') {
        return <dynamic>[
          <String, dynamic>{
            'id': 123456,
            'name': 'My 25-Key Keyboard',
            'manufacturer': 'Example Manufacturer',
          },
        ];
      }
      if (call.method == 'connectMidiSource') {
        return <String, dynamic>{
          'sessionId': 'session-abc',
          'deviceId': '123456',
          'connectionType': 'USB',
        };
      }
      return null;
    });

    MockStreamHandlerEventSink? midiSink;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      const EventChannel('piano_midi/macos/events'),
      MockStreamHandler.inline(
        onListen: (arguments, events) {
          midiSink = events;
        },
        onCancel: (arguments) {},
      ),
    );

    final sink = _FakeExportSink();
    await tester.pumpWidget(MaterialApp(
      home: MidiSourceDiagnosticView(
        discovery: MacosMidiDeviceDiscovery(),
        connection: MacosMidiDeviceConnection(),
        exportSink: sink,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Connect'));
    await tester.pumpAndSettle();

    midiSink!.success(<String, Object?>{
      'sessionId': 'session-abc',
      'deviceId': '123456',
      'connectionType': 'USB',
      'seq': 7,
      'appMonotonicTsMs': 1234,
      'messageType': 'note_on',
      'channel': 0,
      'note': 60,
      'velocity': 100,
      'rawBytes': <int>[0x90, 60, 100],
    });
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Export JSONL'));
    await tester.pumpAndSettle();

    expect(sink.writeCount, 1);
    expect(sink.writtenFilename, 'midi_capture_session-abc.jsonl');
    final lines = sink.writtenContent.split('\n');
    expect(lines.length, 1);
    final map = jsonDecode(lines.single) as Map<String, dynamic>;
    expect(map['schema_version'], 1);
    expect(map['session_id'], 'session-abc');
    expect(map['seq'], 7);
    expect(map['app_monotonic_ts_ms'], 1234);
    expect(map['message_type'], 'note_on');
    expect(map['status'], 144);
    expect(map['data'], <int>[144, 60, 100]);
    expect(find.text('JSONL exported'), findsOneWidget);
  });

  testWidgets('export JSONL contains the full buffer beyond the display limit',
      (WidgetTester tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'listMidiSources') {
        return <dynamic>[
          <String, dynamic>{
            'id': 123456,
            'name': 'My 25-Key Keyboard',
            'manufacturer': 'Example Manufacturer',
          },
        ];
      }
      if (call.method == 'connectMidiSource') {
        return <String, dynamic>{
          'sessionId': 'session-abc',
          'deviceId': '123456',
          'connectionType': 'USB',
        };
      }
      return null;
    });

    MockStreamHandlerEventSink? midiSink;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      const EventChannel('piano_midi/macos/events'),
      MockStreamHandler.inline(
        onListen: (arguments, events) {
          midiSink = events;
        },
        onCancel: (arguments) {},
      ),
    );

    final sink = _FakeExportSink();
    await tester.pumpWidget(MaterialApp(
      home: MidiSourceDiagnosticView(
        discovery: MacosMidiDeviceDiscovery(),
        connection: MacosMidiDeviceConnection(),
        exportSink: sink,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Connect'));
    await tester.pumpAndSettle();

    for (var i = 1; i <= 120; i++) {
      midiSink!.success(<String, Object?>{
        'sessionId': 'session-abc',
        'deviceId': '123456',
        'connectionType': 'USB',
        'seq': i,
        'appMonotonicTsMs': 1000 + i,
        'messageType': 'note_on',
        'channel': 0,
        'note': 60,
        'velocity': 1,
        'rawBytes': <int>[0x90, i, i],
      });
    }
    await tester.pumpAndSettle();

    expect(find.text('Captured Events: 120'), findsOneWidget);
    expect(find.textContaining('[144,120,120]'), findsOneWidget);
    expect(find.textContaining('[144,1,1]'), findsNothing);

    final visibleText =
        tester.widget<SelectableText>(find.byType(SelectableText)).data!;
    final visibleRows = visibleText
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .length;
    expect(visibleRows, 101);

    await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Export JSONL'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Export JSONL'));
    await tester.pumpAndSettle();

    expect(sink.writtenContent.split('\n').length, 120);
    expect(sink.writtenContent, contains('[144,1,1]'));
    expect(sink.writtenContent, contains('[144,120,120]'));
  });

  testWidgets('creates exactly one capture subscription per session',
      (WidgetTester tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'listMidiSources') {
        return <dynamic>[
          <String, dynamic>{
            'id': 123456,
            'name': 'My 25-Key Keyboard',
            'manufacturer': 'Example Manufacturer',
          },
        ];
      }
      if (call.method == 'connectMidiSource') {
        return <String, dynamic>{
          'sessionId': 'session-abc',
          'deviceId': '123456',
          'connectionType': 'USB',
        };
      }
      return null;
    });

    final stream = _CountingEventStream();
    await tester.pumpWidget(MaterialApp(
      home: MidiSourceDiagnosticView(
        discovery: MacosMidiDeviceDiscovery(),
        connection: MacosMidiDeviceConnection(),
        captureFactory: () => stream,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Connect'));
    await tester.pumpAndSettle();

    expect(stream.listenCount, 1);
  });

  testWidgets('shows a connection error when connect fails',
      (WidgetTester tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'listMidiSources') {
        return <dynamic>[
          <String, dynamic>{
            'id': 123456,
            'name': 'My 25-Key Keyboard',
            'manufacturer': 'Example Manufacturer',
          },
        ];
      }
      if (call.method == 'connectMidiSource') {
        throw PlatformException(
          code: 'NO_SOURCE',
          message: 'No MIDI source matches id 123456.',
        );
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: MidiSourceDiagnosticView(
        discovery: MacosMidiDeviceDiscovery(),
        connection: MacosMidiDeviceConnection(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Connect'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('MidiConnectionException(noSource)'),
      findsOneWidget,
    );
    expect(find.text('Status: Disconnected'), findsNothing);
  });

  testWidgets('shows no sources message when none are connected',
      (WidgetTester tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      return <dynamic>[];
    });

    await tester.pumpWidget(MaterialApp(
      home: MidiSourceDiagnosticView(
        discovery: MacosMidiDeviceDiscovery(),
        connection: MacosMidiDeviceConnection(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No MIDI sources detected.'), findsOneWidget);
  });

  testWidgets('shows a diagnostic error when the platform call fails',
      (WidgetTester tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      throw PlatformException(
        code: 'CORE_MIDI_ERROR',
        message: 'CoreMIDI failure',
      );
    });

    await tester.pumpWidget(MaterialApp(
      home: MidiSourceDiagnosticView(
        discovery: MacosMidiDeviceDiscovery(),
        connection: MacosMidiDeviceConnection(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Failed to list MIDI sources.'), findsOneWidget);
  });

  test('MidiSourceInfo is immutable and holds provided values', () {
    const info = MidiSourceInfo(
      id: '1',
      name: 'K',
      manufacturer: 'M',
    );
    expect(info.id, '1');
    expect(info.name, 'K');
    expect(info.manufacturer, 'M');
  });
}