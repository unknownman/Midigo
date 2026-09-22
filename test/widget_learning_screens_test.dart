import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/main.dart';
import 'package:miditutor/practice/application/in_memory_lesson_progress_store.dart';

import 'fakes.dart';

Widget _app({
  FakeDiscovery? discovery,
  FakeConnection? connection,
  FakeMidiStream? stream,
}) {
  return MidiTutorApp(
    discovery: discovery ?? FakeDiscovery(),
    connection: connection ?? FakeConnection(),
    captureFactory: () => stream ?? FakeMidiStream(),
    progressStore: InMemoryLessonProgressStore(),
    clock: FakeClock(DateTime(2025, 1, 1, 9, 0, 0)),
  );
}

void main() {
  testWidgets('home shows Learning Path, Review, and developer entry',
      (WidgetTester tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Learning Path'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('No reviews due'), findsOneWidget);
    expect(find.byIcon(Icons.settings_input_component), findsOneWidget);
  });

  testWidgets('review screen shows the empty state', (WidgetTester tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(find.text('Review'), findsOneWidget);
    expect(find.text('No reviews due'), findsOneWidget);
  });

  testWidgets('learning path renders the C Major lesson', (WidgetTester tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Learning Path'));
    await tester.pumpAndSettle();

    expect(find.text('Lesson 1 · C Major'), findsOneWidget);
    expect(find.text('0 / 10 stars'), findsOneWidget);
  });

  testWidgets('developer entry opens the MIDI diagnostics view',
      (WidgetTester tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_input_component));
    await tester.pumpAndSettle();

    expect(find.text('MIDI Sources'), findsOneWidget);
    expect(find.text('APC Key 25'), findsOneWidget);
  });
}