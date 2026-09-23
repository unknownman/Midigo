/// One deterministic lesson in the Learning Path.
///
/// A lesson is a coherent learning unit (Learn -> Guided Practice -> Repeat ->
/// Result), not a raw exercise. Its [id] is a stable, deterministic identity;
/// the lesson targets exactly one [targetId] (the canonical target id the
/// whole stack agrees on, e.g. `major-c-rh-block`).
///
/// This is curriculum-only: it carries no MIDI types, no evaluation types, and
/// no CoreMIDI. The musical form (quality/root/hand/mode) lives on the catalog.
final class LearningLesson {
  /// Deterministic lesson identity (never random, never clock-derived).
  final String id;

  /// Learner-facing title (e.g. "C Major").
  final String title;

  /// Learner-facing subtitle (e.g. "C Major · Right Hand · Played together").
  final String subtitle;

  /// Position within the Learning Path, 1-based.
  final int order;

  /// Canonical target id this lesson exercises.
  final String targetId;

  const LearningLesson({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.order,
    required this.targetId,
  }) : assert(order > 0, 'LearningLesson: order must be >= 1.');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LearningLesson &&
          other.id == id &&
          other.title == title &&
          other.subtitle == subtitle &&
          other.order == order &&
          other.targetId == targetId;

  @override
  int get hashCode => Object.hash(id, title, subtitle, order, targetId);

  @override
  String toString() => 'LearningLesson($id: $targetId)';
}