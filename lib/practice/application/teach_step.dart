/// One learner-facing instructional step of the Teach stage.
///
/// Authored, deterministic, chunked content: each step presents exactly one
/// concept (no textbook chapters inside a single step). A step is completed
/// when the learner indicates readiness to continue; that completion is
/// session-scoped and is NOT an evaluation attempt, mastery, practice
/// completion, or scheduler state (Learning Curriculum & Lesson Architecture
/// v1.0 §5, §12).
///
/// MVP content is text-first ([content]). [showsKeyboard] marks the passive
/// target-key demonstration steps (keyboard locations, fingering) that reuse
/// the existing piano keyboard visual; they take no MIDI input and emit no
/// audio. Future media kinds (audio / image / animation / interactive
/// demonstration) extend this model additively; none are added here.
final class TeachStep {
  const TeachStep({
    required this.id,
    required this.order,
    required this.title,
    required this.content,
    required this.learnerAction,
    this.showsKeyboard = false,
  }) : assert(order > 0, 'TeachStep: order must be >= 1.');

  /// Deterministic step identity (never random, never clock-derived).
  final String id;

  /// 1-based position within the Teach sequence.
  final int order;

  /// Short step title ("What is a chord?").
  final String title;

  /// Text-first instructional content for this step.
  final String content;

  /// What the learner does on this step ("Read; Continue", "See the highlighted
  /// keys", ...).
  final String learnerAction;

  /// Whether this step presents a passive keyboard demonstration of the target
  /// keys. A static visual only: no MIDI input, no audio, no evaluation.
  final bool showsKeyboard;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TeachStep &&
          other.id == id &&
          other.order == order &&
          other.title == title &&
          other.content == content &&
          other.learnerAction == learnerAction &&
          other.showsKeyboard == showsKeyboard;

  @override
  int get hashCode =>
      Object.hash(id, order, title, content, learnerAction, showsKeyboard);

  @override
  String toString() => 'TeachStep($id: $title)';
}