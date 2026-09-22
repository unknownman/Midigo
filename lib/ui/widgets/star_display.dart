import 'package:flutter/material.dart';

/// Learner-facing star display. [filled] stars in `0..capacity`.
///
/// No grading vocabulary leaks here: the widget only renders how many lesson
/// stars the learner has earned.
class StarDisplay extends StatelessWidget {
  const StarDisplay({
    super.key,
    required this.filled,
    this.capacity = 10,
    this.size = 22,
  });

  final int filled;
  final int capacity;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.tertiary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < capacity; i++)
          Icon(
            i < filled ? Icons.star_rounded : Icons.star_outline_rounded,
            size: size,
            color: i < filled ? color : Theme.of(context).disabledColor,
          ),
      ],
    );
  }
}