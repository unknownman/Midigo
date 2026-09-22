import '../../midi/domain/evaluation_result.dart';

/// Attempt lifecycle vocabulary for one performance against a Practice Item.
///
/// RT-009/RT-010: exactly six states. There is deliberately NO `failed` state:
/// a zero-star [EvaluatedResult] and a [NotEnoughPerformanceResult] are
/// evaluation outcomes, not Attempt states.
enum AttemptState {
  armed,
  active,
  paused,
  completed,
  abandoned,
  invalidated;
}

/// Deterministic attempt state-transition table (RT-011/UI-facing contract).
///
/// * armed -> active, abandoned, invalidated
/// * active <-> paused, active -> completed/abandoned/invalidated
/// * paused -> active/completed/abandoned/invalidated
/// * completed/abandoned/invalidated are terminal.
abstract final class AttemptLifecycle {
  /// Legal destinations indexed by source state.
  static const Map<AttemptState, Set<AttemptState>> transitions =
      <AttemptState, Set<AttemptState>>{
    AttemptState.armed: <AttemptState>{
      AttemptState.active,
      AttemptState.abandoned,
      AttemptState.invalidated,
    },
    AttemptState.active: <AttemptState>{
      AttemptState.paused,
      AttemptState.completed,
      AttemptState.abandoned,
      AttemptState.invalidated,
    },
    AttemptState.paused: <AttemptState>{
      AttemptState.active,
      AttemptState.completed,
      AttemptState.abandoned,
      AttemptState.invalidated,
    },
    AttemptState.completed: <AttemptState>{},
    AttemptState.abandoned: <AttemptState>{},
    AttemptState.invalidated: <AttemptState>{},
  };

  static const Set<AttemptState> terminalStates = <AttemptState>{
    AttemptState.completed,
    AttemptState.abandoned,
    AttemptState.invalidated,
  };

  static bool canTransition(AttemptState from, AttemptState to) =>
      transitions[from]?.contains(to) ?? false;

  static List<AttemptState> allowedFrom(AttemptState from) =>
      List<AttemptState>.unmodifiable(transitions[from] ?? const <AttemptState>[]);
}

/// An immutable runtime record of one performance against a Practice Item.
///
/// [state] transitions are validated through [AttemptLifecycle]. When the
/// attempt is [AttemptState.completed], [evaluationResult] holds the already
/// produced frozen [EvaluationResult]; the record does not itself grade.
class Attempt {
  /// Deterministic, caller-supplied id (never random, never clock-derived).
  final String id;

  /// Id of the Practice Item this attempt belongs to.
  final String practiceItemId;

  final AttemptState state;

  /// Practice-clock timestamp of the `armed -> active` transition.
  /// Null while the attempt is still [AttemptState.armed].
  final DateTime? startedAt;

  /// Practice-clock timestamp of entry into a terminal state.
  /// Null while the attempt is not terminal.
  final DateTime? endedAt;

  /// Evaluation outcome attached when the attempt reaches
  /// [AttemptState.completed]; null otherwise.
  final EvaluationResult? evaluationResult;

  Attempt({
    required this.id,
    required this.practiceItemId,
    required this.state,
    this.startedAt,
    this.endedAt,
    this.evaluationResult,
  }) {
    if (id.isEmpty) {
      throw const FormatException('Attempt: id must not be empty.');
    }
    if (practiceItemId.isEmpty) {
      throw const FormatException(
          'Attempt: practiceItemId must not be empty.');
    }
    if (evaluationResult != null && state != AttemptState.completed) {
      throw const FormatException(
          'Attempt: an evaluation result may only be attached to a completed '
          'attempt.');
    }
    if (state == AttemptState.completed &&
        (startedAt == null || endedAt == null)) {
      throw const FormatException(
          'Attempt: a completed attempt must carry startedAt and endedAt.');
    }
  }

  Attempt copyWith({
    AttemptState? state,
    DateTime? startedAt,
    DateTime? endedAt,
    EvaluationResult? evaluationResult,
  }) =>
      Attempt(
        id: id,
        practiceItemId: practiceItemId,
        state: state ?? this.state,
        startedAt: startedAt ?? this.startedAt,
        endedAt: endedAt ?? this.endedAt,
        evaluationResult: evaluationResult ?? this.evaluationResult,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Attempt &&
          other.id == id &&
          other.practiceItemId == practiceItemId &&
          other.state == state &&
          other.startedAt == startedAt &&
          other.endedAt == endedAt &&
          other.evaluationResult == evaluationResult;

  @override
  int get hashCode => Object.hash(
        id,
        practiceItemId,
        state,
        startedAt,
        endedAt,
        evaluationResult,
      );

  @override
  String toString() => 'Attempt($id[$practiceItemId]: $state)';
}