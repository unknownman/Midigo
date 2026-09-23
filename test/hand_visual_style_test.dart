import 'package:flutter_test/flutter_test.dart';

import 'package:miditutor/midi/domain/expected_musical_target.dart';
import 'package:miditutor/ui/widgets/hand_visual_style.dart';

void main() {
  test('right and left styles expose distinct fixed hand labels', () {
    expect(HandVisualStyle.right.hand, TargetHand.right);
    expect(HandVisualStyle.right.label, 'Right Hand');
    expect(HandVisualStyle.left.hand, TargetHand.left);
    expect(HandVisualStyle.left.label, 'Left Hand');
  });

  test('right and left use distinct semantic colors', () {
    expect(HandVisualStyle.right.color, isNot(HandVisualStyle.left.color));
  });

  test('of() maps single hands and rejects bothUnison (no third color)', () {
    expect(HandVisualStyle.of(TargetHand.right), HandVisualStyle.right);
    expect(HandVisualStyle.of(TargetHand.left), HandVisualStyle.left);
    expect(
      () => HandVisualStyle.of(TargetHand.bothUnison),
      throwsStateError,
    );
  });
}