import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/main.dart';
import 'package:miditutor/midi/domain/midi_source_info.dart';

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

    await tester.pumpWidget(const MidiTutorApp());
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

    await tester.pumpWidget(const MidiTutorApp());
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

    await tester.pumpWidget(const MidiTutorApp());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Captured Events: 0'), findsOneWidget);

    midiSink!.success(<String, Object?>{
      'sessionId': 'session-abc',
      'deviceId': '123456',
      'connectionType': 'USB',
      'seq': 1,
      'appMonotonicTsMs': 123456,
      'messageType': 'note_on',
      'channel': 0,
      'note': 60,
      'velocity': 83,
      'rawBytes': <int>[0x90, 60, 83],
    });
    await tester.pumpAndSettle();

    expect(find.text('Captured Events: 1'), findsOneWidget);
    expect(find.textContaining('NOTE_ON'), findsOneWidget);
    expect(find.textContaining('0    60    83'), findsOneWidget);
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

    await tester.pumpWidget(const MidiTutorApp());
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

    await tester.pumpWidget(const MidiTutorApp());
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

    await tester.pumpWidget(const MidiTutorApp());
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