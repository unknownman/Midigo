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
      await tester.tap(find.widgetWithText(FilledButton, 'Finish Practice'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    expect(find.text('Result'), findsOneWidget);
    expect(find.text('Perfect! All notes matched.'), findsOneWidget);
    expect(find.text('5 / 10 stars'), findsOneWidget);
    // The attempt's own stars come from the actual EvaluatedResult.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('attempt-stars')),
        matching: find.byIcon(Icons.star_rounded),
      ),
      findsNWidgets(5),
    );
    // Lesson progress is rendered separately: 5 of 10 filled so far.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('lesson-progress')),
        matching: find.byIcon(Icons.star_rounded),
      ),
      findsNWidgets(5),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('lesson-progress')),
        matching: find.byIcon(Icons.star_outline_rounded),
      ),
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
      await tester.tap(find.widgetWithText(FilledButton, 'Finish Practice'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Practice · APC Key 25'), findsOneWidget);

    stream.pushPerfectCMajorBlock();
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Finish Practice'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    expect(find.text('Result'), findsOneWidget);
    expect(find.text('10 / 10 stars'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('lesson-progress')),
        matching: find.byIcon(Icons.star_rounded),
      ),
      findsNWidgets(10),
    );
  });

  testWidgets('empty performance shows not enough performance message',
      (WidgetTester tester) async {
    await goToLesson(tester);
    await startPractice(tester);

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Finish Practice'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    expect(find.text('Result'), findsOneWidget);
    expect(find.text('Not enough performance to evaluate.'), findsOneWidget);
    expect(find.byKey(const ValueKey('nep-message')), findsOneWidget);
    // NEP is a distinct state: no attempt-star row at all, so the empty
    // "0/5" does not read like a zero-star evaluation.
    expect(find.byKey(const ValueKey('attempt-stars')), findsNothing);
    expect(find.text('0 / 10 stars'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('lesson-progress')),
        matching: find.byIcon(Icons.star_outline_rounded),
      ),
      findsNWidgets(10),
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
      await tester.tap(find.widgetWithText(FilledButton, 'Finish Practice'));
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
      await tester.tap(find.widgetWithText(FilledButton, 'Finish Practice'));
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

    expect(find.text('Finish Practice'), findsOneWidget);
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

  testWidgets('live MIDI presses drive the pressed keys and live status',
      (WidgetTester tester) async {
    final preconnected = FakeConnection()
      ..preconnect(const MidiConnectionSession(
        sessionId: 'session-1',
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

    // Not in an attempt yet: a live press is not projected.
    stream.pushNoteOn(0, 1000, 60);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pressed-60')), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Start Attempt'));
    await tester.pumpAndSettle();
    expect(find.text('Attempt active'), findsOneWidget);

    stream.pushNoteOn(1, 1000, 60);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pressed-60')), findsOneWidget);
    expect(find.text('Pressed: C4 · 1 / 3 target notes'), findsOneWidget);

    stream.pushNoteOn(2, 1000, 64);
    stream.pushNoteOn(3, 1000, 67);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pressed-64')), findsOneWidget);
    expect(find.byKey(const ValueKey('pressed-67')), findsOneWidget);
    expect(
      find.text('Pressed: C4, E4, G4 · 3 / 3 target notes'),
      findsOneWidget,
    );

    // A wrong key inside the visible range shows only the neutral pressed
    // wash - never an Incorrect/Wrong/Error marker.
    stream.pushNoteOn(4, 1000, 62);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pressed-62')), findsOneWidget);
    expect(
      find.text('Pressed: C4, D4, E4, G4 · 4 / 3 target notes'),
      findsOneWidget,
    );
    expect(find.textContaining('Incorrect'), findsNothing);
    expect(find.textContaining('Wrong'), findsNothing);
    expect(find.textContaining('Error'), findsNothing);

    stream.pushNoteOff(5, 1060, 60);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pressed-60')), findsNothing);
    expect(
      find.text('Pressed: D4, E4, G4 · 3 / 3 target notes'),
      findsOneWidget,
    );
  });

  testWidgets('a zero-star evaluated attempt renders zero attempt stars without '
      'the NEP message', (WidgetTester tester) async {
    await goToLesson(tester);
    await startPractice(tester);

    stream.pushMessyCMajorBlock();
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Finish Practice'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    expect(find.text('Result'), findsOneWidget);
    expect(find.text('Keep practicing the C block.'), findsOneWidget);
    // A 0-star EvaluatedResult is NOT the NEP state: attempt-stars exist.
    expect(find.byKey(const ValueKey('nep-message')), findsNothing);
    expect(find.byIcon(Icons.music_off), findsNothing);
    expect(find.byKey(const ValueKey('attempt-stars')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('attempt-stars')),
        matching: find.byIcon(Icons.star_rounded),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('attempt-stars')),
        matching: find.byIcon(Icons.star_outline_rounded),
      ),
      findsNWidgets(5),
    );
    expect(find.text('0 / 10 stars'), findsOneWidget);
  });

  testWidgets('Continue after NOT_ENOUGH_PERFORMANCE leaves the next lesson '
      'locked', (WidgetTester tester) async {
    await goToLesson(tester);
    await startPractice(tester);

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Finish Practice'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nep-message')), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Learning Path'), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsNWidgets(5));
    expect(find.text('Locked'), findsNWidgets(5));
  });

  testWidgets('double tapping Finish completes the practice exactly once',
      (WidgetTester tester) async {
    await goToLesson(tester);
    await startPractice(tester);
    stream.pushPerfectCMajorBlock();
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      // Two rapid presses on the same still-mounted button: the second lands
      // before the first completion can rebuild/leave the tree. Exactly one
      // completion must be honored.
      final center = tester.getCenter(
        find.widgetWithText(FilledButton, 'Finish Practice'),
      );
      final press1 = await tester.startGesture(center);
      final press2 = await tester.startGesture(center);
      await press1.up();
      await press2.up();
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    expect(find.text('Result'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('attempt-stars')),
        matching: find.byIcon(Icons.star_rounded),
      ),
      findsNWidgets(5),
    );
    final progress = await LessonProgressService(store: store)
        .loadProgress(Slice1Catalog.cMajorTargetId);
    expect(progress.attemptCount, 1);
    expect(progress.stars, 5);
  });
}