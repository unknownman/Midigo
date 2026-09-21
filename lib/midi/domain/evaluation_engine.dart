import 'evaluation_dimension_observations.dart'
    show
        AssociationState,
        IoiEntry,
        PitchObservation,
        SimultaneityGroup,
        TimingObservation;
import 'evaluation_input.dart'
    show
        DataAvailability,
        EvaluationDimension,
        EvaluationDimensionState,
        EvaluationInput,
        IoiEvaluationInput,
        OrderEvaluationInput,
        PitchEvaluationInput,
        RetrievalLatencyEvaluationInput,
        SimultaneityEvaluationInput,
        TimingEvaluationInput;
import 'evaluation_policy.dart'
    show
        ErrorVectorEntry,
        ErrorVectorReasonCode,
        EvaluationPolicyProfile,
        PolicyResolutionContext,
        SeverityTier;
import 'evaluation_result.dart'
    show
        DimensionResult,
        EvaluationResult,
        EvaluatedResult,
        NotEnoughPerformanceResult;

/// The deterministic runtime evaluator.
///
/// Implements the already-decided H2.9H evaluation policy. It does not decide
/// what "good performance" means: every grading value is read from the
/// [EvaluationPolicyProfile]; the engine only executes it.
///
/// The engine is a pure domain service:
///
/// ```text
/// EvaluationInput + Resolved EvaluationPolicyProfile
///                     -> EvaluationEngine.evaluate(...)
///                     -> EvaluationResult
/// ```
///
/// The same `(input, policy, context)` triple always yields the same result:
/// no wall clock, no randomness, no global state, no I/O, no mutation of any
/// external learning state, and no aggregate PASS/FAIL verdict.
class EvaluationEngine {
  const EvaluationEngine();

  /// Evaluates one [input] against the resolved [policy] for [context].
  ///
  /// The caller supplies the already-resolved effective policy; the engine
  /// never invents policy resolution. Identity and version must all agree
  /// (input, policy and context); otherwise the engine fails deterministically
  /// with a [FormatException] - it never silently falls back to another policy
  /// or to legacy constants.
  EvaluationResult evaluate({
    required EvaluationInput input,
    required EvaluationPolicyProfile policy,
    required PolicyResolutionContext context,
  }) {
    _assertApplicable(input, policy, context);
    policy.validate();

    final pitch = _evaluatePitch(input.pitch, policy);
    final timing = _evaluateTiming(input.timing, policy);
    final order = _evaluateOrder(input.order, policy);
    final ioi = _evaluateIoi(input.ioi, policy);
    final simultaneity = _evaluateSimultaneity(
      input.simultaneity,
      policy,
      context,
    );
    final retrievalLatency = _evaluateRetrievalLatency(
      input.retrievalLatency,
      policy,
    );

    final dimensions = <DimensionResult>[
      pitch,
      timing,
      order,
      simultaneity,
      ioi,
      retrievalLatency,
    ];

    final associations = _associationCount(input);
    if (policy.evaluability.requiresStructuralAssociation &&
        policy.evaluability.zeroAssociationsMeansNotEnoughPerformance &&
        associations == 0) {
      return NotEnoughPerformanceResult(dimensions: dimensions);
    }

    final stars = _aggregateStars(policy, dimensions);
    return EvaluatedResult(
      stars: stars,
      dimensions: dimensions,
      errorVector: _flattenErrorVector(dimensions),
    );
  }

  // -------------------------------------------------------------------------
  // Dimension evaluators
  // -------------------------------------------------------------------------

  DimensionResult _evaluatePitch(
    PitchEvaluationInput input,
    EvaluationPolicyProfile policy,
  ) {
    if (input.dimensionState == EvaluationDimensionState.notApplicable) {
      return _inactive(
        EvaluationDimension.pitch,
        EvaluationDimensionState.notApplicable,
        input.dataAvailability,
      );
    }
    if (input.dataAvailability == DataAvailability.unavailable) {
      return _inactive(
        EvaluationDimension.pitch,
        EvaluationDimensionState.enabled,
        DataAvailability.unavailable,
      );
    }

    final associated = <PitchObservation>[];
    final missing = <PitchObservation>[];
    final extras = <PitchObservation>[];
    for (final observation in input.observations) {
      switch (observation.associationState) {
        case AssociationState.associated:
          associated.add(observation);
        case AssociationState.expectedUnmatched:
          missing.add(observation);
        case AssociationState.observedUnmatched:
          extras.add(observation);
      }
    }
    associated.sort(
      (a, b) => a.expectedNoteIndex!.compareTo(b.expectedNoteIndex!),
    );
    missing.sort(
      (a, b) => a.expectedNoteIndex!.compareTo(b.expectedNoteIndex!),
    );
    extras.sort(
      (a, b) => a.observedEventIndex!.compareTo(b.observedEventIndex!),
    );

    final wrong = <PitchObservation>[
      for (final observation in associated)
        if (observation.expectedPitch != observation.observedPitch) observation,
    ];
    final wrongCount = wrong.length;
    final missingCount = missing.length;
    final extraCount = extras.length;

    final wrongSeverity = policy.pitch.wrongNoteSeverity.classify(wrongCount);
    final extraSeverity = policy.stars.extraNote.severityByCount.classify(
      extraCount,
    );

    final errors = <ErrorVectorEntry>[];
    if (wrongCount > 0) {
      errors.add(
        ErrorVectorEntry(
          dimension: EvaluationDimension.pitch,
          severity: wrongSeverity,
          reasonCode: ErrorVectorReasonCode.pitchWrong,
          expectedValue: wrong.first.expectedPitch,
          observedValue: wrong.first.observedPitch,
          count: wrongCount,
          context: <String, Object?>{
            'expected_note_indices': <Object?>[
              for (final observation in wrong) observation.expectedNoteIndex,
            ],
          },
        ),
      );
    }
    if (missingCount > 0) {
      errors.add(
        ErrorVectorEntry(
          dimension: EvaluationDimension.pitch,
          severity: SeverityTier.none,
          reasonCode: ErrorVectorReasonCode.pitchMissing,
          expectedValue: missing.first.expectedPitch,
          count: missingCount,
          context: <String, Object?>{
            'expected_note_indices': <Object?>[
              for (final observation in missing) observation.expectedNoteIndex,
            ],
          },
        ),
      );
    }
    if (extraCount > 0) {
      errors.add(
        ErrorVectorEntry(
          dimension: EvaluationDimension.pitch,
          severity: extraSeverity,
          reasonCode: ErrorVectorReasonCode.pitchExtra,
          observedValue: extras.first.observedPitch,
          count: extraCount,
          context: <String, Object?>{
            'observed_event_indices': <Object?>[
              for (final observation in extras) observation.observedEventIndex,
            ],
          },
        ),
      );
    }

    return DimensionResult(
      dimension: EvaluationDimension.pitch,
      state: EvaluationDimensionState.enabled,
      dataAvailability: DataAvailability.available,
      severity: wrongSeverity,
      metrics: <String, num>{
        'associated_note_count': associated.length,
        'wrong_note_count': wrongCount,
        'missing_note_count': missingCount,
        'extra_note_count': extraCount,
      },
      errors: errors,
    );
  }

  DimensionResult _evaluateTiming(
    TimingEvaluationInput input,
    EvaluationPolicyProfile policy,
  ) {
    if (input.dimensionState == EvaluationDimensionState.notApplicable) {
      return _inactive(
        EvaluationDimension.timing,
        EvaluationDimensionState.notApplicable,
        input.dataAvailability,
      );
    }
    if (input.dataAvailability == DataAvailability.unavailable) {
      return _inactive(
        EvaluationDimension.timing,
        EvaluationDimensionState.enabled,
        DataAvailability.unavailable,
      );
    }

    // Only associated notes to which the target prescribes timing participate
    // in absolute-timing comparison. Notes without prescribed timing are
    // excluded entirely.
    final prescribed = <TimingObservation>[
      for (final observation in input.observations)
        if (observation.associationState == AssociationState.associated &&
            observation.expectedOnsetOffsetMs != null)
          observation,
    ];
    if (prescribed.isEmpty) {
      return DimensionResult(
        dimension: EvaluationDimension.timing,
        state: EvaluationDimensionState.enabled,
        dataAvailability: DataAvailability.available,
        severity: SeverityTier.none,
        metrics: <String, num>{'evaluated_note_count': 0},
      );
    }
    prescribed.sort((a, b) {
      final byOffset = a.expectedOnsetOffsetMs!.compareTo(
        b.expectedOnsetOffsetMs!,
      );
      if (byOffset != 0) {
        return byOffset;
      }
      return a.expectedNoteIndex!.compareTo(b.expectedNoteIndex!);
    });

    // The first prescribed note establishes the performance start anchor.
    // Its own absolute lateness is therefore never penalised.
    final anchor = prescribed.first;
    final anchorObserved = anchor.observedOnsetTimestampMs!;
    final anchorExpected = anchor.expectedOnsetOffsetMs!;
    final anchorIndex = anchor.expectedNoteIndex!;

    // The reference interval used to scale deviations into the percentage
    // severity bands: the expected interval from the anchor, or the policy's
    // configured severity reference interval when every note is simultaneous
    // (expected interval zero - i.e. block chords).
    var maxInterval = 0;
    for (final observation in prescribed) {
      final interval = (observation.expectedOnsetOffsetMs! - anchorExpected)
          .abs();
      if (interval > maxInterval) {
        maxInterval = interval;
      }
    }
    final referenceInterval = maxInterval == 0
        ? policy.timing.severityReferenceIntervalMs
        : maxInterval;

    final deviations = <(TimingObservation, int, SeverityTier)>[];
    for (final observation in prescribed) {
      final deviation =
          (observation.observedOnsetTimestampMs! - anchorObserved) -
          (observation.expectedOnsetOffsetMs! - anchorExpected);
      final interval = (observation.expectedOnsetOffsetMs! - anchorExpected)
          .abs();
      final classifyInterval = interval == 0
          ? policy.timing.severityReferenceIntervalMs
          : interval;
      final severity = policy.timing.classifySeverity(
        deviationMs: deviation.abs(),
        expectedIntervalMs: classifyInterval,
      );
      if (deviation != 0) {
        deviations.add((observation, deviation, severity));
      }
    }

    var dimensionSeverity = SeverityTier.none;
    for (final entry in deviations) {
      if (entry.$3.rank > dimensionSeverity.rank) {
        dimensionSeverity = entry.$3;
      }
    }

    final errors = <ErrorVectorEntry>[];
    for (final reason in const <ErrorVectorReasonCode>[
      ErrorVectorReasonCode.timingEarly,
      ErrorVectorReasonCode.timingLate,
    ]) {
      final isLate = reason == ErrorVectorReasonCode.timingLate;
      final bucket = <(TimingObservation, int, SeverityTier)>[
        for (final entry in deviations)
          if (isLate ? entry.$2 > 0 : entry.$2 < 0) entry,
      ];
      if (bucket.isEmpty) {
        continue;
      }
      final worst = _worstTimingDeviation(bucket);
      final byIndex = [...bucket]
        ..sort(
          (a, b) => a.$1.expectedNoteIndex!.compareTo(b.$1.expectedNoteIndex!),
        );
      errors.add(
        ErrorVectorEntry(
          dimension: EvaluationDimension.timing,
          severity: worst.$3,
          reasonCode: reason,
          expectedValue: worst.$1.expectedOnsetOffsetMs,
          observedValue: worst.$1.observedOnsetTimestampMs,
          signedDelta: worst.$2,
          count: bucket.length,
          context: <String, Object?>{
            'expected_note_indices': <Object?>[
              for (final entry in byIndex) entry.$1.expectedNoteIndex,
            ],
          },
        ),
      );
    }

    return DimensionResult(
      dimension: EvaluationDimension.timing,
      state: EvaluationDimensionState.enabled,
      dataAvailability: DataAvailability.available,
      severity: dimensionSeverity,
      metrics: <String, num>{
        'evaluated_note_count': prescribed.length,
        'anchor_note_index': anchorIndex,
        'reference_interval_ms': referenceInterval,
        'reference_tolerance_ms': policy.timing.toleranceRatio.toleranceMs(
          referenceInterval,
        ),
        'deviating_note_count': deviations.length,
      },
      errors: errors,
    );
  }

  DimensionResult _evaluateOrder(
    OrderEvaluationInput input,
    EvaluationPolicyProfile policy,
  ) {
    if (input.dimensionState == EvaluationDimensionState.notApplicable) {
      return _inactive(
        EvaluationDimension.order,
        EvaluationDimensionState.notApplicable,
        input.dataAvailability,
      );
    }
    if (input.dataAvailability == DataAvailability.unavailable) {
      return _inactive(
        EvaluationDimension.order,
        EvaluationDimensionState.enabled,
        DataAvailability.unavailable,
      );
    }

    final pairs = [...input.order.associatedPairs]
      ..sort((a, b) {
        final byPosition = a.expectedSequencePosition.compareTo(
          b.expectedSequencePosition,
        );
        if (byPosition != 0) {
          return byPosition;
        }
        return a.expectedNoteIndex.compareTo(b.expectedNoteIndex);
      });

    final count = pairs.length;
    var inversions = 0;
    for (var i = 0; i < count; i++) {
      for (var j = i + 1; j < count; j++) {
        if (pairs[i].observedSequencePosition >
            pairs[j].observedSequencePosition) {
          inversions++;
        }
      }
    }

    final orderPolicy = policy.order;
    var severity = SeverityTier.none;
    ErrorVectorReasonCode? reasonCode;
    if (count >= 2) {
      // A full reversal inverts every pair; with two notes a single swap is
      // both an adjacent inversion and a full reversal, and full reversal is
      // the exact match so it wins deterministically.
      final fullReversalCount = count * (count - 1) ~/ 2;
      if (inversions == 0) {
        severity = SeverityTier.none;
      } else if (inversions == fullReversalCount) {
        severity = orderPolicy.fullReversalSeverity;
        reasonCode = ErrorVectorReasonCode.orderFullReversal;
      } else if (inversions == 1) {
        severity = orderPolicy.adjacentInversionSeverity;
        reasonCode = ErrorVectorReasonCode.orderAdjacentInversion;
      } else {
        severity = orderPolicy.partialInversionSeverity;
        reasonCode = ErrorVectorReasonCode.orderPartialInversion;
      }
    }

    final errors = <ErrorVectorEntry>[];
    if (reasonCode != null) {
      errors.add(
        ErrorVectorEntry(
          dimension: EvaluationDimension.order,
          severity: severity,
          reasonCode: reasonCode,
          expectedValue: <Object?>[
            for (final pair in pairs) pair.expectedNoteIndex,
          ],
          observedValue: <Object?>[
            for (final pair in pairs) pair.observedSequencePosition,
          ],
          count: inversions,
          context: <String, Object?>{'associated_pair_count': count},
        ),
      );
    }

    return DimensionResult(
      dimension: EvaluationDimension.order,
      state: EvaluationDimensionState.enabled,
      dataAvailability: DataAvailability.available,
      severity: severity,
      metrics: <String, num>{
        'associated_note_count': count,
        'inversion_count': inversions,
      },
      errors: errors,
    );
  }

  DimensionResult _evaluateIoi(
    IoiEvaluationInput input,
    EvaluationPolicyProfile policy,
  ) {
    if (input.dimensionState == EvaluationDimensionState.notApplicable) {
      return _inactive(
        EvaluationDimension.ioi,
        EvaluationDimensionState.notApplicable,
        input.dataAvailability,
      );
    }
    if (input.dataAvailability == DataAvailability.unavailable) {
      return _inactive(
        EvaluationDimension.ioi,
        EvaluationDimensionState.enabled,
        DataAvailability.unavailable,
      );
    }

    final observed = <IoiEntry>[
      for (final entry in input.observed)
        if (entry.ioiMs != null) entry,
    ];
    observed.sort((a, b) {
      final byFrom = a.fromEventIndex.compareTo(b.fromEventIndex);
      if (byFrom != 0) {
        return byFrom;
      }
      return a.toEventIndex.compareTo(b.toEventIndex);
    });

    var total = 0;
    for (final entry in observed) {
      total += entry.ioiMs!;
    }
    final mean = observed.isEmpty ? null : total / observed.length;

    // Intervals are compared against the learner's own mean interval. A zero
    // mean affords no scale, so no inconsistency can be classified from it.
    final deviations = <(IoiEntry, num, SeverityTier)>[];
    if (mean != null && mean != 0) {
      for (final entry in observed) {
        final deviation = entry.ioiMs! - mean;
        final percent = (deviation.abs() / mean) * 100;
        final severity = policy.ioi.severityBands.classify(percent);
        if (deviation != 0 && severity != SeverityTier.none) {
          deviations.add((entry, deviation, severity));
        }
      }
    }

    var dimensionSeverity = SeverityTier.none;
    for (final entry in deviations) {
      if (entry.$3.rank > dimensionSeverity.rank) {
        dimensionSeverity = entry.$3;
      }
    }

    final errors = <ErrorVectorEntry>[];
    if (deviations.isNotEmpty) {
      final worst = _worstIoiDeviation(deviations);
      errors.add(
        ErrorVectorEntry(
          dimension: EvaluationDimension.ioi,
          severity: worst.$3,
          reasonCode: ErrorVectorReasonCode.ioiInconsistent,
          expectedValue: mean,
          observedValue: worst.$1.ioiMs,
          signedDelta: worst.$2,
          count: deviations.length,
          context: <String, Object?>{
            'interval_details': <Object?>[
              for (final entry in deviations)
                <String, Object?>{
                  'from_event_index': entry.$1.fromEventIndex,
                  'to_event_index': entry.$1.toEventIndex,
                  'ioi_ms': entry.$1.ioiMs,
                  'deviation_ms': entry.$2,
                },
            ],
          },
        ),
      );
    }

    return DimensionResult(
      dimension: EvaluationDimension.ioi,
      state: EvaluationDimensionState.enabled,
      dataAvailability: DataAvailability.available,
      severity: dimensionSeverity,
      metrics: <String, num>{
        'expected_interval_count': input.expected.length,
        'observed_interval_count': input.observed.length,
        'mean_interval_ms': ?mean,
      },
      errors: errors,
    );
  }

  DimensionResult _evaluateSimultaneity(
    SimultaneityEvaluationInput input,
    EvaluationPolicyProfile policy,
    PolicyResolutionContext context,
  ) {
    if (input.dimensionState == EvaluationDimensionState.notApplicable) {
      return _inactive(
        EvaluationDimension.simultaneity,
        EvaluationDimensionState.notApplicable,
        input.dataAvailability,
      );
    }
    if (input.dataAvailability == DataAvailability.unavailable) {
      return _inactive(
        EvaluationDimension.simultaneity,
        EvaluationDimensionState.enabled,
        DataAvailability.unavailable,
      );
    }

    final level = context.learnerLevel;
    if (level == null) {
      throw const FormatException(
        'EvaluationEngine: simultaneity evaluation requires a learner level '
        'in the policy resolution context; none was supplied.',
      );
    }

    final groups = [...input.groups]
      ..sort((a, b) => a.expectedGroupIndex.compareTo(b.expectedGroupIndex));

    final spreads = <(SimultaneityGroup, int, SeverityTier)>[];
    for (final group in groups) {
      final spread = group.observedSpanMs;
      if (spread == null) {
        continue;
      }
      final severity = policy.simultaneity.classifySeverity(level, spread);
      if (severity != SeverityTier.none) {
        spreads.add((group, spread, severity));
      }
    }

    var dimensionSeverity = SeverityTier.none;
    for (final entry in spreads) {
      if (entry.$3.rank > dimensionSeverity.rank) {
        dimensionSeverity = entry.$3;
      }
    }

    final errors = <ErrorVectorEntry>[];
    if (spreads.isNotEmpty) {
      final worst = _worstSimultaneitySpread(spreads);
      errors.add(
        ErrorVectorEntry(
          dimension: EvaluationDimension.simultaneity,
          severity: worst.$3,
          reasonCode: ErrorVectorReasonCode.simultaneitySpread,
          expectedValue: 0,
          observedValue: worst.$2,
          signedDelta: worst.$2,
          count: spreads.length,
          context: <String, Object?>{
            'group_details': <Object?>[
              for (final entry in spreads)
                <String, Object?>{
                  'expected_group_index': entry.$1.expectedGroupIndex,
                  'observed_span_ms': entry.$2,
                  'unmatched_expected_member_count':
                      entry.$1.unmatchedExpectedMemberIndices.length,
                },
            ],
          },
        ),
      );
    }

    return DimensionResult(
      dimension: EvaluationDimension.simultaneity,
      state: EvaluationDimensionState.enabled,
      dataAvailability: DataAvailability.available,
      severity: dimensionSeverity,
      metrics: <String, num>{
        'group_count': groups.length,
        'spread_group_count': spreads.length,
      },
      errors: errors,
    );
  }

  DimensionResult _evaluateRetrievalLatency(
    RetrievalLatencyEvaluationInput input,
    EvaluationPolicyProfile policy,
  ) {
    if (input.dataAvailability == DataAvailability.available) {
      return _inactive(
        EvaluationDimension.retrievalLatency,
        EvaluationDimensionState.enabled,
        DataAvailability.available,
      );
    }
    final retrieval = policy.retrievalLatency;
    final errors = <ErrorVectorEntry>[
      ErrorVectorEntry(
        dimension: EvaluationDimension.retrievalLatency,
        severity: SeverityTier.none,
        reasonCode: retrieval.unavailableReasonCode,
        observedValue: input.observation.reason,
        count: 1,
        context: <String, Object?>{
          'reason': input.observation.reason,
          'performance_anchor_absent': true,
        },
      ),
    ];
    return DimensionResult(
      dimension: EvaluationDimension.retrievalLatency,
      state: EvaluationDimensionState.enabled,
      dataAvailability: DataAvailability.unavailable,
      severity: SeverityTier.none,
      errors: errors,
    );
  }

  // -------------------------------------------------------------------------
  // Star aggregation
  // -------------------------------------------------------------------------

  int _aggregateStars(
    EvaluationPolicyProfile policy,
    List<DimensionResult> dimensions,
  ) {
    final stars = policy.stars;

    // Ordered severity sources: the enabled-and-available dimensions in enum
    // order, followed by the extra-note severity when extras exist. Missing
    // notes carry no severity; they act only as a final ceiling.
    final sources = <(EvaluationDimension?, SeverityTier)>[];
    for (final dimension in dimensions) {
      if (dimension.state == EvaluationDimensionState.enabled &&
          dimension.dataAvailability == DataAvailability.available) {
        sources.add((dimension.dimension, dimension.severity));
      }
    }
    final pitch = dimensions.firstWhere(
      (dimension) => dimension.dimension == EvaluationDimension.pitch,
    );
    final extraCount = pitch.metrics['extra_note_count']?.toInt() ?? 0;
    if (extraCount > 0) {
      sources.add((null, stars.extraNote.severityByCount.classify(extraCount)));
    }

    var worst = SeverityTier.none;
    for (final source in sources) {
      if (source.$2.rank > worst.rank) {
        worst = source.$2;
      }
    }
    final base = stars.baseStars[worst]!;

    // The worst source establishes the base and is never itself trimmed. Every
    // other source at or above the configured minimum trim severity contributes
    // one whole-star trim, up to the configured maximum.
    var trimCount = 0;
    var worstCounted = false;
    for (final source in sources) {
      if (!worstCounted && source.$2 == worst) {
        worstCounted = true;
        continue;
      }
      if (source.$2.atLeast(stars.minimumTrimSeverity)) {
        trimCount++;
      }
    }
    final maxTrims = stars.minorTrimCount ?? 0;
    if (trimCount > maxTrims) {
      trimCount = maxTrims;
    }

    var quality = base - trimCount;

    // Missing-note ceiling is applied after base and trims and can only reduce
    // (or leave unchanged) the result.
    final missingCount = pitch.metrics['missing_note_count']?.toInt() ?? 0;
    final missingCap = stars.missingNote.capTable.capForCount(missingCount);
    if (missingCap != null && missingCap < quality) {
      quality = missingCap;
    }

    return quality
        .clamp(
          policy.resultState.evaluatedMinStars,
          policy.resultState.evaluatedMaxStars,
        )
        .toInt();
  }

  List<ErrorVectorEntry> _flattenErrorVector(List<DimensionResult> dimensions) {
    final entries = <ErrorVectorEntry>[];
    for (final dimension in dimensions) {
      entries.addAll(dimension.errors);
    }
    return entries;
  }

  // -------------------------------------------------------------------------
  // Identity / applicability boundary
  // -------------------------------------------------------------------------

  void _assertApplicable(
    EvaluationInput input,
    EvaluationPolicyProfile policy,
    PolicyResolutionContext context,
  ) {
    if (policy.profileIdValue != input.evaluationProfileId) {
      throw FormatException(
        'EvaluationEngine: input references profile '
        "'${input.evaluationProfileId}' but the policy evaluates "
        "'${policy.profileIdValue}'.",
      );
    }
    if (policy.contractVersionValue != input.evaluationProfileVersion) {
      throw FormatException(
        'EvaluationEngine: input references profile version '
        "'${input.evaluationProfileVersion}' but the policy serves contract "
        "version '${policy.contractVersionValue}'.",
      );
    }
    if (context.profileId != input.evaluationProfileId) {
      throw FormatException(
        'EvaluationEngine: resolution context references profile '
        "'${context.profileId}' but the input references '${input.evaluationProfileId}'.",
      );
    }
    if (context.profileVersion != input.evaluationProfileVersion) {
      throw FormatException(
        "EvaluationEngine: resolution context references profile version "
        "'${context.profileVersion}' but the input references "
        "'${input.evaluationProfileVersion}'.",
      );
    }
    if (context.mode != input.mode) {
      throw FormatException(
        'EvaluationEngine: resolution context mode ${context.mode.name} does '
        'not match input mode ${input.mode.name}.',
      );
    }

    final declared = <(EvaluationDimension, EvaluationDimensionState)>[
      (EvaluationDimension.pitch, input.pitch.dimensionState),
      (EvaluationDimension.timing, input.timing.dimensionState),
      (EvaluationDimension.order, input.order.dimensionState),
      (EvaluationDimension.simultaneity, input.simultaneity.dimensionState),
      (EvaluationDimension.ioi, input.ioi.dimensionState),
      (
        EvaluationDimension.retrievalLatency,
        input.retrievalLatency.dimensionState,
      ),
    ];
    for (final entry in declared) {
      final expected = policy.applicability.stateFor(context.mode, entry.$1);
      if (entry.$2 != expected) {
        throw FormatException(
          'EvaluationEngine: input declares ${entry.$1.name} as '
          '${entry.$2.serialName} but the resolved policy for '
          '${context.mode.name} declares it as ${expected.serialName}.',
        );
      }
    }
  }

  // -------------------------------------------------------------------------
  // Shared helpers
  // -------------------------------------------------------------------------

  static DimensionResult _inactive(
    EvaluationDimension dimension,
    EvaluationDimensionState state,
    DataAvailability availability,
  ) {
    return DimensionResult(
      dimension: dimension,
      state: state,
      dataAvailability: availability,
      severity: SeverityTier.none,
    );
  }

  static int _associationCount(EvaluationInput input) {
    final pitch = input.pitch;
    if (pitch.dimensionState != EvaluationDimensionState.enabled ||
        pitch.dataAvailability != DataAvailability.available) {
      return 0;
    }
    var count = 0;
    for (final observation in pitch.observations) {
      if (observation.associationState == AssociationState.associated) {
        count++;
      }
    }
    return count;
  }

  static (TimingObservation, int, SeverityTier) _worstTimingDeviation(
    List<(TimingObservation, int, SeverityTier)> bucket,
  ) {
    var worst = bucket.first;
    for (final entry in bucket) {
      final rankIsWorse = entry.$3.rank > worst.$3.rank;
      final magnitudeIsWorse =
          entry.$3.rank == worst.$3.rank && entry.$2.abs() > worst.$2.abs();
      final indexIsEarlier =
          entry.$3.rank == worst.$3.rank &&
          entry.$2.abs() == worst.$2.abs() &&
          entry.$1.expectedNoteIndex! < worst.$1.expectedNoteIndex!;
      if (rankIsWorse || magnitudeIsWorse || indexIsEarlier) {
        worst = entry;
      }
    }
    return worst;
  }

  static (IoiEntry, num, SeverityTier) _worstIoiDeviation(
    List<(IoiEntry, num, SeverityTier)> deviations,
  ) {
    var worst = deviations.first;
    for (final entry in deviations) {
      final rankIsWorse = entry.$3.rank > worst.$3.rank;
      final magnitudeIsWorse =
          entry.$3.rank == worst.$3.rank && entry.$2.abs() > worst.$2.abs();
      final positiveIsWorse =
          entry.$3.rank == worst.$3.rank &&
          entry.$2.abs() == worst.$2.abs() &&
          entry.$2 > worst.$2;
      final intervalIsLater =
          entry.$3.rank == worst.$3.rank &&
          entry.$2.abs() == worst.$2.abs() &&
          entry.$2 == worst.$2 &&
          (entry.$1.fromEventIndex > worst.$1.fromEventIndex ||
              (entry.$1.fromEventIndex == worst.$1.fromEventIndex &&
                  entry.$1.toEventIndex > worst.$1.toEventIndex));
      if (rankIsWorse ||
          magnitudeIsWorse ||
          positiveIsWorse ||
          intervalIsLater) {
        worst = entry;
      }
    }
    return worst;
  }

  static (SimultaneityGroup, int, SeverityTier) _worstSimultaneitySpread(
    List<(SimultaneityGroup, int, SeverityTier)> spreads,
  ) {
    var worst = spreads.first;
    for (final entry in spreads) {
      final rankIsWorse = entry.$3.rank > worst.$3.rank;
      final spreadIsWorse =
          entry.$3.rank == worst.$3.rank && entry.$2 > worst.$2;
      final groupIsEarlier =
          entry.$3.rank == worst.$3.rank &&
          entry.$2 == worst.$2 &&
          entry.$1.expectedGroupIndex < worst.$1.expectedGroupIndex;
      if (rankIsWorse || spreadIsWorse || groupIsEarlier) {
        worst = entry;
      }
    }
    return worst;
  }
}
