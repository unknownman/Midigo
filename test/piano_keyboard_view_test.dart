import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/midi/application/expected_musical_target_factory.dart';
import 'package:miditutor/midi/domain/expected_musical_target.dart';
import 'package:miditutor/practice/application/fingering_data.dart';
import 'package:miditutor/practice/application/lesson_instruction.dart';
import 'package:miditutor/ui/widgets/hand_visual_style.dart';
import 'package:miditutor/ui/widgets/piano_keyboard_view.dart';

LessonInstruction _instruction({
  required TargetHand hand,
  required TargetMode mode,
}) {
  final handCode = switch (hand) {
    TargetHand.right => 'rh',
    TargetHand.left => 'lh',
    TargetHand.bothUnison => 'bothUnison',
  };
  final target = const ExpectedMusicalTargetFactory().build(
    quality: TargetQuality.major,
    root: TargetRoot.c,
    hand: hand,
    mode: mode,
    targetId: 'major-c-$handCode-${mode.name}',
  );
  return LessonInstructionFactory().build(
    target: target,
    fingerings: const FingeringCatalog().fingeringsFor(target.targetId),
  );
}

Future<void> _pump(
  WidgetTester tester,
  LessonInstruction instruction, {
  double width = 700,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: PianoKeyboardView(instruction: instruction),
          ),
        ),
      ),
    ),
  );
}

Color _containerColor(WidgetTester tester, String key) {
  final Container container =
      tester.widget<Container>(find.byKey(ValueKey<String>(key)));
  return (container.decoration! as BoxDecoration).color!;
}

void main() {
  group('PianoKeyboardView', () {
    testWidgets('block target renders every white key in the C..G range',
        (tester) async {
      await _pump(tester, _instruction(hand: TargetHand.right, mode: TargetMode.block));
      for (final letter in <String>['C', 'D', 'E', 'F', 'G']) {
        expect(find.text(letter), findsOneWidget);
      }
      expect(find.text('A'), findsNothing);
      expect(find.text('B'), findsNothing);
      for (final pitch in <int>[61, 63, 66]) {
        expect(find.byKey(ValueKey<String>('black-$pitch')), findsOneWidget);
      }
    });

    testWidgets('arpeggio target expands the range to C..C5',
        (tester) async {
      await _pump(tester, _instruction(hand: TargetHand.right, mode: TargetMode.arpeggio));
      expect(find.text('C'), findsNWidgets(2));
      for (final letter in <String>['D', 'E', 'F', 'G', 'A', 'B']) {
        expect(find.text(letter), findsOneWidget);
      }
      for (final pitch in <int>[61, 63, 66, 68, 70]) {
        expect(find.byKey(ValueKey<String>('black-$pitch')), findsOneWidget);
      }
    });

    testWidgets('target keys are highlighted in the hand color; others plain',
        (tester) async {
      await _pump(tester, _instruction(hand: TargetHand.right, mode: TargetMode.block));
      for (final pitch in <int>[60, 64, 67]) {
        final box = tester.widget<ColoredBox>(find.descendant(
          of: find.byKey(ValueKey<String>('key-$pitch')),
          matching: find.byType(ColoredBox),
        ));
        expect(box.color, HandVisualStyle.right.color);
      }
      expect(_containerColor(tester, 'key-62'), Colors.white);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('key-62')),
          matching: find.byType(ColoredBox),
        ),
        findsNothing,
      );
    });

    testWidgets('finger numbers render on highlighted target keys',
        (tester) async {
      await _pump(tester, _instruction(hand: TargetHand.left, mode: TargetMode.block));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('key-60')),
          matching: find.text('5'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('key-64')),
          matching: find.text('3'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('key-67')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('block renders no step badges (play together)',
        (tester) async {
      await _pump(tester, _instruction(hand: TargetHand.right, mode: TargetMode.block));
      for (var step = 1; step <= 4; step++) {
        expect(
          find.byKey(ValueKey<String>('step-$step')),
          findsNothing,
        );
      }
    });

    testWidgets('arpeggio renders ordered step badges 1..4', (tester) async {
      await _pump(tester, _instruction(hand: TargetHand.right, mode: TargetMode.arpeggio));
      for (var step = 1; step <= 4; step++) {
        expect(
          find.byKey(ValueKey<String>('step-$step')),
          findsOneWidget,
        );
      }
    });

    testWidgets('bothUnison block keys render one colored half per hand',
        (tester) async {
      await _pump(tester,
          _instruction(hand: TargetHand.bothUnison, mode: TargetMode.block));
      for (final pitch in <int>[60, 64, 67]) {
        final left = tester.widget<ColoredBox>(
          find.byKey(ValueKey<String>('half-$pitch-left')),
        );
        final right = tester.widget<ColoredBox>(
          find.byKey(ValueKey<String>('half-$pitch-right')),
        );
        expect(left.color, HandVisualStyle.left.color);
        expect(right.color, HandVisualStyle.right.color);
      }
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('half-60-left')),
          matching: find.text('5'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('half-60-right')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('legend maps the hand color to its label', (tester) async {
      await _pump(tester,
          _instruction(hand: TargetHand.bothUnison, mode: TargetMode.arpeggio));
      expect(find.text('Right Hand'), findsOneWidget);
      expect(find.text('Left Hand'), findsOneWidget);
    });
  });
}