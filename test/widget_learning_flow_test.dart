import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/main.dart';
import 'package:miditutor/midi/domain/evaluation_result.dart';
import 'package:miditutor/midi/domain/midi_connection_error.dart';
import 'package:miditutor/midi/domain/midi_connection_session.dart';
import 'package:miditutor/practice/application/in_memory_lesson_progress_store.dart';
import 'package:miditutor/practice/application/lesson_progress_service.dart';
import 'package:miditutor/practice/application/slice1_catalog.dart';

import 'fakes.dart';

void main() {
  late FakeConnection connection;
  late FakeMidiStream stream;
  late InMemoryLessonProgressStore store;

  Widget app({FakeConnection? injectedConnection}) {
    connection = injectedConnection ?? FakeConnection();
    stream = FakeMidiStream();
    store = InMemoryLessonProgressStore();
    return MidiTutorApp(
      discovery: FakeDiscovery(),
      connection: connection,
      captureFactory: () => stream,
      progressStore: store,
      clock: FakeClock(DateTime(2025, 1, 1, 9, 0, 0)),
    );
  }

  Future<void> goToLesson(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Learning Path'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lesson 1 · C Major'));
    await tester.pumpAndSettle();
  }

  Future<void> startPractice(WidgetTester tester) async {
    await tester.tap(find.text('Start Practice'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();
  }

  testWidgets('navigates Teach -> Practice and evaluates a real 5-star block',
      (WidgetTester tester) async {
    await goToLesson(tester);

    expect(find.text('Lesson 1 · C Major'), findsOneWidget);
    expect(find.text('C Major · Right Hand · Played together'), findsOneWidget);
    expect(find.text('Target notes: C4, E4, G4'), findsOneWidget);

    await startPractice(tester);

    expect(find.text('Practice · APC Key 25'), findsOneWidget);
    expect(find.text('Play C4, E4, and G4 together.'), findsOneWidget);

    stream.pushPerfectCMajorBlock();
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Finish Attempt'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    expect(find.text('Result'), findsOneWidget);
    expect(find.text('Attempt 1 · Lesson progress: 5 / 10 stars'), findsOneWidget);
    expect(find.text('Perfect! All notes matched.'), findsOneWidget);
    expect(
      find.byIcon(Icons.star_rounded),
      findsNWidgets(5),
    );
  });

  testWidgets('retry arms a new attempt and continues to evaluate',
      (WidgetTester tester) async {
    await goToLesson(tester);
    await startPractice(tester);
    stream.pushPerfectCMajorBlock();
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Finish Attempt'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Practice · APC Key 25'), findsOneWidget);

    stream.pushPerfectCMajorBlock();
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Finish Attempt'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    expect(find.text('Result'), findsOneWidget);
    expect(find.text('Attempt 2 · Lesson progress: 10 / 10 stars'), findsOneWidget);
  });

  testWidgets('empty performance shows not enough performance message',
      (WidgetTester tester) async {
    await goToLesson(tester);
    await startPractice(tester);

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Finish Attempt'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    expect(find.text('Result'), findsOneWidget);
    expect(find.text('Not enough performance to evaluate.'), findsOneWidget);
    expect(find.text('Attempt 1 · Lesson progress: 0 / 10 stars'), findsOneWidget);
    expect(
      find.byIcon(Icons.star_outline_rounded),
      findsNWidgets(5),
    );
    final progress = await LessonProgressService(store: store)
        .loadProgress(Slice1Catalog.cMajorTargetId);
    expect(progress.stars, 0);
    expect(progress.attemptCount, 1);
  });

  testWidgets('learning path shows all six lessons; locked until unlocked',
      (WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Learning Path'));
    await tester.pumpAndSettle();

    for (var i = 1; i <= 6; i++) {
      expect(find.text('Lesson $i · C Major'), findsOneWidget);
    }
    expect(find.text('0 / 10 stars'), findsOneWidget);
    expect(find.text('Locked'), findsNWidgets(5));
    expect(find.byIcon(Icons.lock), findsNWidgets(5));
    expect(find.byIcon(Icons.music_note), findsOneWidget);
  });

  testWidgets('completing lesson 1 unlocks lesson 2 and Continue opens it',
      (WidgetTester tester) async {
    await tester.pumpWidget(app());
    await LessonProgressService(store: store).recordResult(
      targetId: Slice1Catalog.cMajorTargetId,
      result: EvaluatedResult(
        stars: 5,
        dimensions: const [],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Learning Path'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lesson 1 · C Major'));
    await tester.pumpAndSettle();
    await startPractice(tester);

    stream.pushPerfectCMajorBlock();
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Finish Attempt'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(find.text('Result'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    expect(find.text('Lesson 2 · C Major'), findsOneWidget);
    expect(find.text('C Major · Right Hand · Played one at a time'),
        findsOneWidget);
    expect(find.text('Target notes: C4, E4, G4, C5'), findsOneWidget);
    expect(
        find.text('Press C, E, G, and C one at a time on the right side '
            'of the keyboard.'),
        findsOneWidget);
    expect(find.text('Start Practice'), findsOneWidget);
  });

  testWidgets('Continue on an incomplete lesson returns to the path',
      (WidgetTester tester) async {
    await goToLesson(tester);
    await startPractice(tester);

    stream.pushPerfectCMajorBlock();
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Finish Attempt'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Lesson 1 · C Major · Right Hand · Played together'),
        findsNothing);
    expect(find.text('Lesson 1 · C Major'), findsOneWidget);
    expect(find.text('Learning Path'), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsNWidgets(5));
  });

  testWidgets('opening Practice adopts an already-connected device',
      (WidgetTester tester) async {
    final preconnected = FakeConnection()
      ..preconnect(const MidiConnectionSession(
        sessionId: 'existing-session',
        deviceId: 'dev',
        connectionType: 'USB',
      ));
    await tester.pumpWidget(app(injectedConnection: preconnected));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Learning Path'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lesson 1 · C Major'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start Practice'));
    await tester.pumpAndSettle();

    expect(find.text('Practice · APC Key 25'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Connect'), findsNothing);
    expect(
      find.widgetWithText(FilledButton, 'Start Attempt'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Start Attempt'));
    await tester.pumpAndSettle();

    expect(find.text('Finish Attempt'), findsOneWidget);
  });

  testWidgets('a failed connect keeps the real error visible and starts nothing',
      (WidgetTester tester) async {
    final failing = FakeConnection()
      ..connectError = const MidiConnectionException(
        MidiConnectionError.connectionFailed,
        'Could not establish the MIDI connection.',
      );
    await tester.pumpWidget(app(injectedConnection: failing));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Learning Path'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lesson 1 · C Major'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start Practice'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not connect to that MIDI keyboard.'),
      findsOneWidget,
    );
    expect(find.text('Connect a MIDI keyboard first.'), findsNothing);
    expect(find.text('Practice · APC Key 25'), findsNothing);
    expect(find.text('Start Attempt'), findsNothing);
  });
}