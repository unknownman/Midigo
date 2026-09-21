import 'evaluation_input.dart'
    show DataAvailability, EvaluationDimension, EvaluationDimensionState;
import 'evaluation_policy.dart'
    show ErrorVectorEntry, EvaluationResultState, SeverityTier;

/// Serialisation vocabulary for the six evaluation dimensions. The mapping is
/// locked by the H2.9A contract and the H2.9I conformance suite; it carries no
/// grading semantics.
String _dimensionSerial(EvaluationDimension dimension) {
  switch (dimension) {
    case EvaluationDimension.pitch:
      return 'pitch';
    case EvaluationDimension.timing:
      return 'timing';
    case EvaluationDimension.order:
      return 'order';
    case EvaluationDimension.simultaneity:
      return 'simultaneity';
    case EvaluationDimension.ioi:
      return 'ioi';
    case EvaluationDimension.retrievalLatency:
      return 'retrieval_latency';
  }
}

bool _dimensionListEq(List<DimensionResult> a, List<DimensionResult> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
    if (a[i].runtimeType != b[i].runtimeType) {
      return false;
    }
  }
  return true;
}

int _dimensionListHash(List<DimensionResult> list) {
  var hash = 0;
  for (final entry in list) {
    hash = Object.hash(hash, entry);
  }
  return hash;
}

bool _errorVectorListEq(List<ErrorVectorEntry> a, List<ErrorVectorEntry> b) {
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

int _errorVectorListHash(List<ErrorVectorEntry> list) {
  var hash = 0;
  for (final entry in list) {
    hash = Object.hash(hash, entry);
  }
  return hash;
}

bool _numMapEq(Map<String, num> a, Map<String, num> b) {
  if (a.length != b.length) {
    return false;
  }
  for (final key in a.keys) {
    if (!b.containsKey(key) || a[key] != b[key]) {
      return false;
    }
  }
  return true;
}

int _numMapHash(Map<String, num> map) {
  var hash = 0;
  for (final entry in map.entries) {
    hash = Object.hash(hash, entry.key, entry.value);
  }
  return hash;
}

/// One evaluated dimension of the performance.
///
/// Represents the outcome of exactly one of the six [EvaluationDimension]s for
/// the target mode. [state] and [dataAvailability] are never collapsed:
/// a dimension is either enabled or not-applicable for the resolved profile,
/// and independent of that, its data was either available or unavailable.
class DimensionResult {
  final EvaluationDimension dimension;
  final EvaluationDimensionState state;
  final DataAvailability dataAvailability;
  final SeverityTier severity;
  final Map<String, num> metrics;
  final List<ErrorVectorEntry> errors;

  DimensionResult({
    required this.dimension,
    required this.state,
    required this.dataAvailability,
    required this.severity,
    Map<String, num>? metrics,
    List<ErrorVectorEntry>? errors,
  }) : metrics = Map<String, num>.unmodifiable(
         metrics ?? const <String, num>{},
       ),
       errors = List<ErrorVectorEntry>.unmodifiable(
         errors ?? const <ErrorVectorEntry>[],
       );

  Map<String, Object?> toMap() => <String, Object?>{
    'dimension': _dimensionSerial(dimension),
    'state': state.serialName,
    'data_availability': dataAvailability.serialName,
    'severity': severity.serialName,
    'metrics': <String, Object?>{
      for (final entry in metrics.entries) entry.key: entry.value,
    },
    'errors': <Object?>[for (final entry in errors) entry.toMap()],
  };

  @override
  bool operator ==(Object other) =>
      other is DimensionResult &&
      other.dimension == dimension &&
      other.state == state &&
      other.dataAvailability == dataAvailability &&
      other.severity == severity &&
      _numMapEq(other.metrics, metrics) &&
      _errorVectorListEq(other.errors, errors);

  @override
  int get hashCode => Object.hash(
    dimension,
    state,
    dataAvailability,
    severity,
    _numMapHash(metrics),
    _errorVectorListHash(errors),
  );
}

/// The immutable, serialisable outcome of one evaluation.
///
/// Exactly two result kinds exist:
///
/// * [NotEnoughPerformanceResult] - there was not enough structurally-aligned
///   performance to grade at all; it carries no stars and no zero-star
///   interpretation.
/// * [EvaluatedResult] - a graded performance with whole stars in `0..5`.
///
/// There is deliberately no aggregate PASS/FAIL vocabulary anywhere here.
sealed class EvaluationResult {
  final EvaluationResultState state;
  const EvaluationResult({required this.state});

  bool get isEvaluated;
  List<DimensionResult> get dimensions;
  List<ErrorVectorEntry> get errorVector;
  Map<String, Object?> toMap();
}

/// Produced when the required-note association count is zero (or the
/// structural authority itself is unavailable).
class NotEnoughPerformanceResult extends EvaluationResult {
  @override
  final List<DimensionResult> dimensions;
  @override
  final List<ErrorVectorEntry> errorVector;

  NotEnoughPerformanceResult({
    required List<DimensionResult> dimensions,
    List<ErrorVectorEntry>? errorVector,
  }) : dimensions = List<DimensionResult>.unmodifiable(dimensions),
       errorVector = List<ErrorVectorEntry>.unmodifiable(
         errorVector ?? const <ErrorVectorEntry>[],
       ),
       super(state: EvaluationResultState.notEnoughPerformance);

  @override
  bool get isEvaluated => false;

  @override
  Map<String, Object?> toMap() => <String, Object?>{
    'state': state.serialName,
    'dimensions': <Object?>[
      for (final dimension in dimensions) dimension.toMap(),
    ],
    'error_vector': <Object?>[for (final entry in errorVector) entry.toMap()],
  };

  @override
  bool operator ==(Object other) =>
      other is NotEnoughPerformanceResult &&
      _dimensionListEq(other.dimensions, dimensions) &&
      _errorVectorListEq(other.errorVector, errorVector);

  @override
  int get hashCode => Object.hash(
    state,
    _dimensionListHash(dimensions),
    _errorVectorListHash(errorVector),
  );
}

/// A graded performance. [stars] is an integer in `0..resultState`.
/// A zero-star result is still [EVALUATED]; it is not a not-enough-performance
/// state and not a failure verdict.
class EvaluatedResult extends EvaluationResult {
  final int stars;
  @override
  final List<DimensionResult> dimensions;
  @override
  final List<ErrorVectorEntry> errorVector;

  EvaluatedResult({
    required this.stars,
    required List<DimensionResult> dimensions,
    List<ErrorVectorEntry>? errorVector,
  }) : assert(stars >= 0 && stars <= 5, 'EvaluatedResult: stars must be 0..5.'),
       dimensions = List<DimensionResult>.unmodifiable(dimensions),
       errorVector = List<ErrorVectorEntry>.unmodifiable(
         errorVector ?? const <ErrorVectorEntry>[],
       ),
       super(state: EvaluationResultState.evaluated);

  @override
  bool get isEvaluated => true;

  @override
  Map<String, Object?> toMap() => <String, Object?>{
    'state': state.serialName,
    'stars': stars,
    'dimensions': <Object?>[
      for (final dimension in dimensions) dimension.toMap(),
    ],
    'error_vector': <Object?>[for (final entry in errorVector) entry.toMap()],
  };

  @override
  bool operator ==(Object other) =>
      other is EvaluatedResult &&
      other.stars == stars &&
      _dimensionListEq(other.dimensions, dimensions) &&
      _errorVectorListEq(other.errorVector, errorVector);

  @override
  int get hashCode => Object.hash(
    state,
    stars,
    _dimensionListHash(dimensions),
    _errorVectorListHash(errorVector),
  );
}
