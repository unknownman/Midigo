import 'package:flutter/material.dart';

import '../../midi/domain/expected_musical_target.dart';

/// Semantic visual treatment attached to a hand, never to a specific pitch
/// class.
///
/// Right and Left each get one fixed color + label so the learner can map a
/// color to a hand across lessons. A [`TargetHand.bothUnison`] target renders
/// the Right Hand style AND the Left Hand style together (one half of a key per
/// hand); there is deliberately no third "both" color.
final class HandVisualStyle {
  const HandVisualStyle._(this.hand, this.color, this.label);

  /// The hand this style belongs to (right or left only, never bothUnison).
  final TargetHand hand;

  final Color color;
  final String label;

  static const HandVisualStyle right =
      HandVisualStyle._(TargetHand.right, Color(0xFF2E7D32), 'Right Hand');

  static const HandVisualStyle left =
      HandVisualStyle._(TargetHand.left, Color(0xFF1565C0), 'Left Hand');

  static const List<HandVisualStyle> all = <HandVisualStyle>[right, left];

  /// The style for [hand]; throws for [TargetHand.bothUnison] because a
  /// both-hands target is represented by both styles, not a third one.
  static HandVisualStyle of(TargetHand hand) => switch (hand) {
        TargetHand.right => right,
        TargetHand.left => left,
        TargetHand.bothUnison => throw StateError(
            'HandVisualStyle: bothUnison is rendered by combining the right '
            'and left styles; there is no third hand color.'),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HandVisualStyle &&
          other.hand == hand &&
          other.color == color &&
          other.label == label;

  @override
  int get hashCode => Object.hash(hand, color, label);
}