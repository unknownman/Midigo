import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
    print('subscribed: ${sub.isPaused}');
    await tester.pump();
    print('after pump() before cancel');

    var cancelled = false;
    final f = sub.cancel().then((x) {
      cancelled = true;
      print('CANCEL FUTURE DONE');
    });
    print('cancel() returned synchronously; cancelled=$cancelled');

    await tester.pump();
    print('after pump()#1 cancelled=$cancelled');
    await tester.pump(const Duration(milliseconds: 50));
    print('after pump(50ms)#2 cancelled=$cancelled');
    await f.timeout(const Duration(seconds: 1), onTimeout: () {
      print('CANCEL TIMEOUT');
      return null;
    });
    print('await f finished cancelled=$cancelled');
  });
}