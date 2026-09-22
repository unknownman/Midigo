import '../../midi/application/evaluation_dimension_observation_extractor.dart';
import '../../midi/application/evaluation_input_preparer.dart';
import '../../midi/application/midi_normalizer.dart';
import '../../midi/application/musical_event_interpreter.dart';
import '../../midi/application/structural_aligner.dart';
import '../../midi/domain/evaluation_engine.dart';
import '../../midi/domain/evaluation_input.dart';
import '../../midi/domain/evaluation_policy.dart';
import '../../midi/domain/evaluation_result.dart';
import '../../midi/domain/expected_musical_target.dart';
import '../../midi/domain/raw_midi_event.dart';

/// Outcome of one evaluation flow run: the frozen [EvaluationResult] plus the
/// provenance that identifies which target/session produced it.
class EvaluationFlowResult {
  final EvaluationResult result;

  /// The evaluated target id.
  final String targetId;

  /// The MIDI capture session id the events came from.
  final String sessionId;

  final TargetMode mode;

  EvaluationFlowResult({
    required this.result,
    required this.targetId,
    required this.sessionId,
    required this.mode,
  });

  bool get isEvaluated => result.isEvaluated;

  /// Practice-friendly stars view: null means not-enough-performance.
  int? get stars => (result is EvaluatedResult) ? (result as EvaluatedResult).stars : null;

  bool get isNotEnoughPerformance => result is NotEnoughPerformanceResult;
}

/// Application-layer composition of the frozen H1/H2 evaluation pipeline.
///
/// This layer only wires existing components together and adapts at this
/// application boundary. It contains no new grading logic, no normalization
/// changes, no alignment changes, and no evaluation-policy changes. Every
/// component below is used exactly as it exists in the repository:
///
/// ```text
/// RawMidiEvent
///   -> MidiNormalizer
///   -> MusicalEventInterpreter
///   -> StructuralAligner
///   -> EvaluationDimensionObservationExtractor
///   -> EvaluationInputPreparer
///   -> EvaluationEngine
///   -> EvaluationResult
/// ```
final class EvaluationFlowService {
  const EvaluationFlowService();

  /// Deterministic composition version for the application boundary.
  static const String algorithmVersion = '1';

  /// Evaluates one capture of raw MIDI [events] against [target].
  ///
  /// [sessionId] must be the capture session the events were recorded under.
  /// The evaluation context is fixed for Slice 1: [learnerLevel] defaults to
  /// [LearnerLevelKey.beginner] and [tempoBpm] defaults to 90. These are
  /// required by the existing evaluation semantics and are NOT a tempo engine,
  /// tempo progression, or tempo ownership: the Practice Runtime never owns or
  /// mutates tempo.
  EvaluationFlowResult evaluate({
    required ExpectedMusicalTarget target,
    required String sessionId,
    required List<RawMidiEvent> events,
    LearnerLevelKey learnerLevel = LearnerLevelKey.beginner,
    int tempoBpm = 90,
  }) {
    final normalized = const MidiNormalizer().normalizeAll(events);
    final musicalEvents = const MusicalEventInterpreter().interpret(normalized);
    final alignment = const StructuralAligner().align(
      target: target,
      sessionId: sessionId,
      observed: musicalEvents,
    );
    final observations = const EvaluationDimensionObservationExtractor().extract(
      target: target,
      observed: musicalEvents,
      alignment: alignment,
    );
    final input = const EvaluationInputPreparer().prepare(observations: observations);
    final context = PolicyResolutionContext(
      profileId: MvpDefaultEvaluationProfile.profileId,
      profileVersion: MvpDefaultEvaluationProfile.contractVersion,
      mode: target.mode,
      learnerLevel: learnerLevel,
      tempoBpm: tempoBpm,
    );
    final result = const EvaluationEngine().evaluate(
      input: input,
      policy: EvaluationPolicyProfile.instance,
      context: context,
    );
    return EvaluationFlowResult(
      result: result,
      targetId: target.targetId,
      sessionId: sessionId,
      mode: target.mode,
    );
  }
}