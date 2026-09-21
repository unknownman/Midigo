# Evaluation Contract v1.1 — Decision Matrix (H2.9B)

Status of every Evaluation Contract decision required to implement the
Deterministic Evaluation Engine (H2.9).

- Precursor: H2.9A materialized the partial contract at
  `lib/midi/domain/evaluation_contract.dart` (commit `37df35f`).
- This document does NOT invent policy. It only records what the repository
  establishes and which decisions remain open.
- H1 hardware-validation values, H2.2 diagnostic values (60 ms simultaneity
  window, 5 ms duplicate threshold), and H2.5 sample arpeggio offsets are
  NOT Evaluation policy and MUST NOT be promoted.
- A status of `DECISION REQUIRED` means the repository (all commits reachable
  from `main`) contains no rule resolving the decision. No value is proposed.

Guardrails reproduced from the materialized contract (H2.9A):

```text
no verdict vocabulary
no evaluation metrics
no thresholds / tolerances
no boundary rules
no Error Vector
no aggregate rule
```

| ID | Decision Area | Current Locked Fact | Required Policy Decision | Repository Source | Status |
| -- | ------------- | ------------------- | ------------------------ | ----------------- | ------ |
| EV-001 | Verdict vocabulary | No evaluation verdict vocabulary exists. `INVALID` exists only as a platform error code name (`INVALID_REQUEST`) in the device layer; `UNAVAILABLE` and `NOT_APPLICABLE` exist only as H2.8 observation-layer state vocabulary, not verdicts. | What verdict states exist; is PASS/FAIL defined; is SUCCESS/MARGINAL/FAILURE defined; is INVALID a verdict or a separate result state; is UNAVAILABLE a verdict; is NOT_APPLICABLE a verdict; is partial correctness supported. | `lib/midi/domain/evaluation_input.dart` (`EvaluationDimensionState`, `DataAvailability`); `lib/midi/domain/structural_alignment.dart` ("carries NO correctness verdict"); `lib/midi/domain/evaluation_dimension_observations.dart` ("no correctness, pass/fail, score, grade, tolerance, error vector"); `lib/midi/domain/midi_connection_error.dart` (`INVALID_REQUEST`, device layer) | DECISION REQUIRED |
| EV-002 | Pitch | Numeric expected/observed MIDI pitches are carried per association state (associated / expected-unmatched / observed-unmatched) with no comparison rule, no tolerance ("No tolerance is stored"), no enharmonic treatment, no duplicate rule. | Comparison unit; matching semantics; unmatched expected handling; unmatched observed handling; duplicate handling; metric; threshold; boundary; unavailable behavior; aggregate contribution. | `lib/midi/domain/evaluation_dimension_observations.dart` (`PitchObservation`); `lib/midi/domain/expected_musical_target.dart` ("No tolerance is stored"); H2.6 `AssociationState` | DECISION REQUIRED |
| EV-003 | Timing | Raw `expectedOnsetOffsetMs` (relative to target start) and `observedOnsetTimestampMs` (observed-stream time base) are carried; no comparable deviation is precomputed; no metric, tolerance, boundary, or per-event-vs-aggregate rule exists. H2.2 diagnostic windows are excluded. | Timing metric; reference timestamp; absolute/relative semantics; per-event vs aggregate evaluation; tolerance; boundary inclusion; missing-event handling; extra-event handling; unavailable behavior. | `lib/midi/domain/evaluation_dimension_observations.dart` (`TimingObservation`); `lib/midi/diagnostics/diagnostic_analysis.dart` (draft 60 ms / 5 ms values are diagnostic only) | DECISION REQUIRED |
| EV-004 | Order | `expectedOrder`, `observedOrder` (never re-sorted), and `associatedPairs` are carried as supplied; no order verdict is produced by any layer ("no order verdict"). | Correct-order definition; sequence comparison; missing events; extra events; duplicates; relationship to Pitch; metric; threshold; boundary; aggregate contribution. | `lib/midi/domain/evaluation_dimension_observations.dart` (`OrderObservation`, "no order verdict"); H2.6/H2.7 doc comments | DECISION REQUIRED |
| EV-005 | IOI | Raw signed `IoiEntry` intervals exist per side (expected and observed are uncoupled); `ioiMs == null` represents a missing interval explicitly; only `index >= 0` invariants exist. No comparison formula, tolerance, negative-value, first-event, or missing-interval rule. | Expected IOI; observed IOI; comparison formula; absolute/relative error; negative IOI handling; missing intervals; tolerance; boundary; first-event semantics; unavailable behavior. | `lib/midi/domain/evaluation_dimension_observations.dart` (`IoiEntry`); `lib/midi/domain/evaluation_input.dart` (`IoiEvaluationInput` uncoupled expected/observed) | DECISION REQUIRED |
| EV-006 | Simultaneity | `SimultaneityGroup` exposes expected members, associated observed onsets, `unmatchedExpectedMemberIndices`, and raw `observedSpanMs`; "no simultaneity threshold exists" is recorded. The H2.2 60 ms diagnostic window is explicitly NOT evaluation policy and the target model "is NEVER derived from the H2.2 diagnostic 60 ms simultaneity window". | Group definition; simultaneity metric; tolerance; boundary; missing members; extra members; partial group behavior; aggregate contribution. | `lib/midi/domain/evaluation_dimension_observations.dart` (`SimultaneityGroup`, "no simultaneity threshold exists"); `lib/midi/domain/expected_musical_target.dart` (60 ms window exclusion); H2.2 `DiagnosticAnalysisConfig.simultaneityWindowMs` (diagnostic only) | DECISION REQUIRED |
| EV-007 | Retrieval Latency | `NO_RUNTIME_PERFORMANCE_ANCHOR`; anchor timestamp and latency duration are always null; no anchor is fabricated (session start, first event, target creation, capture start, wall clock are rejected); first observed note event index/timestamp are recorded. | Performance anchor; start event; end event; latency formula; threshold; boundary; unavailable behavior; aggregate contribution. | `lib/midi/domain/evaluation_dimension_observations.dart` (`RetrievalLatencyObservation`, rejected anchor list); `lib/midi/application/evaluation_dimension_observation_extractor.dart` (`NO_RUNTIME_PERFORMANCE_ANCHOR`); `lib/midi/application/evaluation_input_preparer.dart` | DECISION REQUIRED |
| EV-008 | ENABLED + UNAVAILABLE | H2.8 establishes that an enabled dimension may report unavailable data and that this state is never downgraded to NOT_APPLICABLE. No rule exists for what an evaluation must do with it (verdict, invalidation, no aggregate effect, UNKNOWN, Error Vector impact). | Does it produce a verdict; does it invalidate evaluation; does it have no aggregate effect; does it produce an UNKNOWN state; does it affect the Error Vector. | `lib/midi/domain/evaluation_input.dart` (`EvaluationDimensionInput` enabled + unavailable combo); H2.8 immutability/passthrough semantics | DECISION REQUIRED |
| EV-009 | NOT_APPLICABLE | H2.8 enforces that a NOT_APPLICABLE dimension carries no observations (FormatException invariants) and that Retrieval Latency is never NOT_APPLICABLE. No result-layer representation or aggregate/Error Vector participation rule exists. | Result representation; aggregate participation; Error Vector entry; whether it counts toward "all dimensions"; omitted vs explicit. | `lib/midi/domain/evaluation_input.dart` (per-dimension NOT_APPLICABLE invariants); `lib/midi/domain/evaluation_contract.dart` (DERIVED applicability for Block Order/IOI and Arpeggio Simultaneity) | DECISION REQUIRED |
| EV-010 | Error Vector | No Error Vector representation, fields, weights, symptom severity, or normalization exists. The only references are negative: the H2.5 leakage test forbids an `error_vector` key in the expected-target projection, and the canonical input documents "no ... Error Vector lives in this model". | Dimensions; representation; numeric/categorical form; sign; direction; normalization; severity; range; missing-data representation; aggregation. | `test/expected_musical_target_test.dart` (forbidden-key scan); `lib/midi/domain/evaluation_input.dart` (explicit absence) | DECISION REQUIRED |
| EV-011 | Aggregate Evaluation Result | No `EvaluationResult` model exists; the canonical input documents "No EvaluationResult, no verdict, no score, no threshold, no tolerance, and no Error Vector lives in this model". No vocabulary, participation, precedence, scoring, weighting, or aggregation function. | Overall result vocabulary; participating dimensions; NOT_APPLICABLE handling; UNAVAILABLE handling; failure precedence; partial success; scoring; weighting; aggregation function; deterministic precedence. | `lib/midi/domain/evaluation_input.dart` (explicit absence); `lib/midi/domain/evaluation_contract.dart` (aggregate_result UNRESOLVED) | DECISION REQUIRED |
| EV-012 | Result provenance | Every canonical layer result propagates identity and layer versions: `EvaluationDimensionObservations` carries `targetId`/`sessionId`/layer versions; `EvaluationInput` adds `evaluationProfileId`/`evaluationProfileVersion`/`mode` and three `<layer>AlgorithmVersion` fields. | Exact provenance a future EvaluationResult must contain. Mechanically follows the established propagation convention: input identity plus the engine's own algorithm version. | `lib/midi/domain/evaluation_dimension_observations.dart` (`EvaluationDimensionObservations` fields); `lib/midi/domain/evaluation_input.dart` (`EvaluationInput` fields); `lib/midi/domain/evaluation_contract.dart` (`provenance_requirement` DEFINED) | DERIVED |
| EV-013 | Determinism | Committed determinism invariants exist for the pipeline: "determinism identical input yields identical stable projection" and "immutability mutating source collections cannot mutate EvaluationInput"; the H2.9A contract materializes `determinism_requirement` as DEFINED. | Invariant `same EvaluationInput + same Evaluation Contract version + same Evaluation Profile version = same EvaluationResult` follows mechanically from the locked determinism convention; no policy choice involved. | `test/evaluation_input_preparer_test.dart` (determinism + immutability tests); `lib/midi/domain/evaluation_contract.dart` (`determinism_requirement` DEFINED) | DERIVED |
| EV-014 | Cross-dimension interaction | "Each dimension is independently inspectable" and the six canonical inputs are independent containers. No dependency, hierarchy, precedence, or interaction rule exists between dimensions. | Relationship model: independent / dependent / hierarchical / precedence-based; behavior for Pitch-failure-plus-Order-success, Pitch-failure-plus-Timing-success, missing/extra pitch with timing, Pitch-success-plus-Simultaneity-failure, musical-dimensions-available-with-Retrieval-Latency-unavailable. | `lib/midi/domain/evaluation_dimension_observations.dart` ("Each dimension is independently inspectable"); `lib/midi/domain/evaluation_input.dart` (six independent inputs) | DECISION REQUIRED |

## Decision Summary

```text
Total decisions: 14
Defined: 0
Derived: 2
Decision Required: 12
Not Applicable: 0
```

## Decisions Required Before H2.9

```text
DECISIONS REQUIRED BEFORE H2.9
──────────────────────────────
EV-001 verdict vocabulary not defined
EV-002 pitch evaluation semantics not defined
EV-003 timing evaluation semantics not defined
EV-004 order evaluation semantics not defined
EV-005 IOI evaluation semantics not defined
EV-006 simultaneity evaluation semantics not defined
EV-007 retrieval latency evaluation semantics not defined
EV-008 ENABLED + UNAVAILABLE result behavior not defined
EV-009 NOT_APPLICABLE result representation not defined
EV-010 Error Vector semantics not defined
EV-011 aggregate EvaluationResult semantics not defined
EV-014 cross-dimension interaction not defined
```

EV-012 (result provenance) and EV-013 (determinism) are DERIVED from committed
repository conventions and require no policy decision.