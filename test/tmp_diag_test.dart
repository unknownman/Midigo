import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/diagnostics/midi_source_diagnostic_view.dart';
import 'package:miditutor/midi/application/midi_device_connection.dart';
import 'package:miditutor/midi/application/midi_device_discovery.dart';

void main() {
  const channel = MethodChannel('piano_midi/macos');

  testWidgets('diag disconnect flow', (WidgetTester tester) async {
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
      if (call.method == 'disconnectMidiSource') {
        print('PLATFORM disconnect invoked');
        return null;
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      const EventChannel('piano_midi/macos/events'),
      MockStreamHandler.inline(
        onListen: (arguments, events) {
          print('STREAM onListen');
        },
        onCancel: (arguments) {
          print('STREAM onCancel');
        },
      ),
    );

    final connection = MacosMidiDeviceConnection();
    await tester.pumpWidget(MaterialApp(
      home: MidiSourceDiagnosticView(
        discovery: MacosMidiDeviceDiscovery(),
        connection: connection,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Connect'));
    await tester.pumpAndSettle();
    print('after connect: ${connection.state} ${connection.currentSession}');

    await tester.tap(find.widgetWithText(FilledButton, 'Disconnect'));
    print('after tap: ${connection.state}');

    await tester.pump();
    print('after pump(): ${connection.state}');

    await tester.pump(const Duration(milliseconds: 50));
    print('after pump(50ms): ${connection.state}');

    await tester.pumpAndSettle();
    print('after settle: ${connection.state}');

    for (final t in find.byType(Text).evaluate()) {
      final data = (t.widget as Text).data;
      if (data != null && data.isNotEmpty) {
        print('TEXT: $data');
      }
    }
  });
}