import 'practice_item.dart';

/// Why a Practice Interaction ended (RT-022). Abandoned means the learner
/// left before completing every focus item of the interaction.
enum PracticeInteractionEndReason {
  completed,
  abandoned;
}

/// The single execution session of a Practice Interaction (PR-015).
///
/// PR-015 locks the relationship at exactly 1:1: one Practice Interaction owns
/// exactly one Execution Session, and one Execution Session belongs to exactly
/// one Practice Interaction. This immutability rule is enforced by both types
/// cross-referencing each other's ids.
class ExecutionSession {
  /// Deterministic, caller-supplied id (never random, never clock-derived).
  final String id;

  /// Id of the owning Practice Interaction.
  final String practiceInteractionId;

  ExecutionSession({required this.id, required this.practiceInteractionId}) {
    if (id.isEmpty) {
      throw const FormatException('ExecutionSession: id must not be empty.');
    }
    if (practiceInteractionId.isEmpty) {
      throw const FormatException(
          'ExecutionSession: practiceInteractionId must not be empty.');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExecutionSession &&
          other.id == id &&
          other.practiceInteractionId == practiceInteractionId;

  @override
  int get hashCode => Object.hash(id, practiceInteractionId);

  @override
  String toString() => 'ExecutionSession($id -> $practiceInteractionId)';
}

/// A bounded practice interaction: the learner practices the focus items of
/// one execution session (1:1, PR-015) from `armed` until [endReason].
///
/// This is the Practice-Interaction-level container. Each item inside owns its
/// own Attempt records. Scheduler, mastery, and evaluation semantics live
/// strictly outside this type.
class PracticeInteraction {
  /// Deterministic, caller-supplied id (never random, never clock-derived).
  final String id;

  /// The unique execution session of this interaction (1:1).
  final ExecutionSession executionSession;

  /// Focus items of this interaction, in deterministic order.
  final List<PracticeItem> items;

  /// Practice-clock timestamp of interaction start (created time).
  final DateTime startedAt;

  /// Practice-clock timestamp when the interaction ended.
  /// Null while the interaction is still open.
  final DateTime? endedAt;

  final PracticeInteractionEndReason? endReason;

  PracticeInteraction({
    required this.id,
    required this.executionSession,
    List<PracticeItem>? items,
    required this.startedAt,
    this.endedAt,
    this.endReason,
  })  : items = List<PracticeItem>.unmodifiable(items ?? const <PracticeItem>[]) {
    if (id.isEmpty) {
      throw const FormatException(
          'PracticeInteraction: id must not be empty.');
    }
    // PR-015: the execution session must reference exactly this interaction.
    if (executionSession.practiceInteractionId != id) {
      throw const FormatException(
          'PracticeInteraction: execution session must reference the owning '
          'interaction (PR-015 1:1).');
    }
    if (endReason != null && endedAt == null) {
      throw const FormatException(
          'PracticeInteraction: an endReason requires an endedAt timestamp.');
    }
  }

  PracticeInteraction copyWith({
    List<PracticeItem>? items,
    DateTime? endedAt,
    PracticeInteractionEndReason? endReason,
  }) =>
      PracticeInteraction(
        id: id,
        executionSession: executionSession,
        items: items ?? this.items,
        startedAt: startedAt,
        endedAt: endedAt ?? this.endedAt,
        endReason: endReason ?? this.endReason,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeInteraction &&
          other.id == id &&
          other.executionSession == executionSession &&
          _itemListEq(other.items, items) &&
          other.startedAt == startedAt &&
          other.endedAt == endedAt &&
          other.endReason == endReason;

  @override
  int get hashCode => Object.hash(id, executionSession, Object.hashAll(items),
      startedAt, endedAt, endReason);

  @override
  String toString() =>
      'PracticeInteraction($id: ${items.length} items, ${endReason?.name ?? "open"})';
}

bool _itemListEq(List<PracticeItem> a, List<PracticeItem> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}