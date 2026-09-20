import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore_for_file: avoid_print

void main() {
  testWidgets('diag cancel resolution', (WidgetTester tester) async {
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

    final stream = const EventChannel('piano_midi/macos/events')
        .receiveBroadcastStream();
    final sub = stream.listen((e) => print('EVENT $e'));
    await tester.pump();
    print('before cancel: subscribed=${!sub.isPaused}');

    await tester.runAsync(() => sub.cancel());
    print('CANCEL FUTURE COMPLETED');
    await tester.pump();
    print('TEST BODY COMPLETE');
  });
}