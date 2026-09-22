# Evidence Aggregation Contract v1.1 — Decision Matrix (H2.10A)

Status of every Evidence Aggregation decision required to define Evidence
Aggregation Contract v1.1. This phase establishes the contract **semantically
only**: no Evidence models, no aggregation executor, no tests.

- This document is the authoritative written form of the contract decisions
  that are determinable from the locked repository plus the decisions
  explicitly made by the H2.10A phase brief.
- It does NOT invent policy. Every rule introduced here is an explicit product
  decision (status `DEFINED`) or a fact that follows mechanically from locked
  facts (status `DERIVED`).
- `UNRESOLVED` means the rule cannot be derived safely: either the repository
  contains no basis, or the phase brief forbids the inference. No value is
  proposed for unresolved rules.
- `NOT_APPLICABLE` means the concept is out of scope of Evidence v1.1 and must
  be addressed by a later contract.

## Contract identity

```text
contract_name:    Evidence Aggregation Contract
contract_version: v1.1
profile era:      mvp_default_v1 / Evaluation Contract v1.1 (H2.9 generation)
```

## Frozen contracts this phase may NOT modify

```text
H2.6  expected_musical_target.dart              (frozen)
H2.7  evaluation_dimension_observations.dart     (frozen)
H2.8  evaluation_input.dart                      (frozen)
H2.9  evaluation_engine.dart             (frozen, NEP != EVALUATED 0..5 stars)
H2.9A evaluation_contract.dart                   (frozen)
H2.9B evaluation-contract-v1.1-decision-matrix.md
H2.9H evaluation_policy.dart                     (frozen star policy, stable)
H2.9I evaluation_policy_conformance_test.dart    (frozen)
H2.9J lesson star policy                         (frozen: capacity 10)
H2.9K engine conformance audit tests             (frozen: 476/476 green)
```

## Guardrails reproduced for this phase

```text
no mastery decisions in evidence
no scheduler decisions in evidence
no SUCCESS / MARGINAL_SUCCESS / FAILURE / INVALID / RELEARNING_SUCCESS
no attempt == evidence-identity conflation
no NEP == 0-star conflation
no reuse of MIDI capture app_monotonic_ts_ms as practice-interaction time
no random ids / wall-clock-now / global mutable state / process-local counters
evidence is immutable
contributions are explicit, never implicit
```

## Evidence semantic pipeline (decided boundary)

```text
Attempt + EvaluationResult
      |  (one evaluated practice attempt of one target)
      v
EvidenceContribution (per target+dimension evidence stream; kind = practiceAttempt)
      |  (deterministic grouping; independence boundaries)
      v
EvidenceGroup
      |
      v
(future) Mastery  -- NOT part of Evidence v1.1
```

## H2.10A.1 Authoritative Search Audit (evidence of absence)

Phase H2.10A.1 was tasked with resolving EVG-005/006/009/010/019 from an
already-locked Practice Interaction / Practice Runtime contract. The required
exhaustive search was performed and found NO such contract in the repository.

Searched:
- working tree `lib/`, `test/`, `docs/`
- full git history via `git grep` across every reachable revision
- all tracked branches (only `main` / `origin/main` exist) and the stash stack

Findings (all negative or non-authoritative):

```text
- No Practice Interaction / PracticeItem / ExerciseInstance / ExecutionSession
  / started_at / ended_at / end_reason / practice_item_id / ready_timestamp
  appears in any committed source except this decision matrix.
- ExpectedMusicalTarget (H2.6) names "Attempt" and "Exercise Instance" ONLY as
  things the target is NOT; no model for either exists.
- ExpectedMusicalTargetFactory (H2.5) states it "never generates an Exercise
  Instance" and "does not implement the curriculum".
- The only "session" entity is MidiConnectionSession (H1.2): a device capture
  session carrying sessionId / deviceId / connectionType with NO timestamps and
  NO practice semantics.
- Evaluation policy references an attempt only via
  UnavailableHandling.invalidatesAttempt; no Attempt model or lifecycle exists.
- Retrieval Latency is contractually NO_RUNTIME_PERFORMANCE_ANCHOR; the
  extractor rejects session start, first event, target creation time, and wall
  clock as an anchor. No ready_timestamp exists anywhere.
- The only time data is MIDI capture app_monotonic_ts_ms and observed-stream
  onset/end timestamps (MIDI time bases). DateTime.now() has zero hits in lib/.
- README.md lists "practice runtime" as a LATER / planned phase.
```

Conclusion: the authoritative Practice Interaction contract is NOT available
in the repository. Per the H2.10A.1 operating rule, its semantics may not be
invented here. EVG-005/006/009/010/016/017/018/019 therefore remain
UNRESOLVED.

| ID | Decision Area | Decision | Repository / Policy Source | Status |
| -- | ------------- | -------- | -------------------------- | ------ |
| EVG-001 | Contract identity & version | Evidence Aggregation Contract, v1.1; associated with the locked `mvp_default_v1` / Evaluation Contract v1.1 profile era. No runtime profile is introduced by this contract. | H2.10A brief; `lib/midi/domain/evaluation_contract.dart` (identity convention) | DEFINED |
| EVG-002 | Evidence identity | Evidence Identity is the deterministic tuple `(targetId, evaluation dimension)`; it identifies one Evidence Stream. Identity is **determined from content**, never generated by random/clock. targetId is `ExpectedMusicalTarget.targetId`; dimension uses the locked `EvaluationDimension` vocabulary. | `lib/midi/domain/expected_musical_target.dart` (targetId); `lib/midi/domain/evaluation_input.dart` (`EvaluationDimension`, `MvpDefaultEvaluationProfile`) | DEFINED |
| EVG-003 | Evidence contribution | One evaluated Attempt produces exactly one EvidenceContribution per Evidence Stream on which it produced graded data (see EVG-011). Contributions are explicit and immutable; no implicit or magic contributions exist. An Attempt is NOT an EvidenceContribution and NOT its own evidence identity. | H2.10A brief (explicit contributions; attempt != evidence identity) | DEFINED |
| EVG-004 | Contribution kind | v1.1 defines exactly one contribution kind: `practiceAttempt` (evidence derived from a graded practice attempt of a target). `ACQUISITION` / `RETRIEVAL` / `RETENTION` / `DEGRADATION` / `LAPSE` are NOT contribution kinds in v1.1: no acquisition/retrieval/review mechanism exists in the locked architecture, and temporal kinds require a temporal model (EVG-019). | `lib/midi` (single practice/drill mechanism; no review path) | DEFINED |
| EVG-005 | Practice Interaction | UNRESOLVED. The H2.10A.1 audit conclusively found NO Practice Interaction entity or Practice Runtime contract anywhere (working tree, all git history, both branches, no stash): no identity rule, no boundary, no `started_at`/`ended_at`, no timestamp, no queue/practice-item vocabulary. The 15-minute rule is anchored on it, but its temporal instantiation (when a practice interaction begins, ends, and how the gap is measured) cannot be defined without inventing a new model, which is forbidden. MIDI `app_monotonic_ts_ms` is a device-capture time base and is excluded by the phase brief. | H2.10A.1 audit section above; `lib/midi/domain/midi_connection_session.dart` (only session entity, no timestamps); `README.md` ("practice runtime" = later phase) | UNRESOLVED |
| EVG-006 | Attempt <-> Interaction | UNRESOLVED. No Attempt model or lifecycle exists in the repository (only `ExpectedMusicalTarget` naming Attempt/Exercise Instance as NON-identities and `UnavailableHandling.invalidatesAttempt` as an evaluation policy value). Whether every attempt belongs to exactly one Practice Interaction, whether attempts may exist outside one, and whether the interaction identity is available to Evidence therefore cannot be determined. Invariant `Attempt Identity != Practice Interaction Identity` is recorded but has no operands. | H2.10A.1 audit section above; `lib/midi/domain/expected_musical_target.dart`; `lib/midi/domain/evaluation_policy.dart` (`UnavailableHandling.invalidatesAttempt`) | UNRESOLVED |
| EVG-007 | Evidence dependency semantics | Locked classification rule: contributions from the SAME Practice Interaction are DEPENDENT; contributions from DIFFERENT interactions whose gap is LESS THAN 15 minutes are DEPENDENT; contributions from DIFFERENT interactions whose gap is AT LEAST 15 minutes are INDEPENDENT. The rule is a product decision; its operands (gap, interaction boundary) are blocked by EVG-019/EVG-005. | H2.10A brief (explicit rule) | DEFINED |
| EVG-008 | 15-minute threshold | Locked typed policy: `threshold = 15 minutes`, **boundary inclusive** — a gap of exactly 15:00 classifies as INDEPENDENT. This is the only numeric Evidence policy of v1.1. | H2.10A brief (inclusive boundary explicit) | DEFINED |
| EVG-009 | Evidence group | UNRESOLVED. Group semantics are determinable in form (a group is the deterministic unit of contributions sharing Evidence Identity, delimited by independence boundaries), but group formation requires the independence classification of EVG-007, whose gap operand requires Practice Interaction lifecycle timestamps that do not exist (EVG-005/EVG-019). Grouping is not implementable yet. | depends on EVG-005, EVG-007, EVG-010, EVG-019 | UNRESOLVED |
| EVG-010 | Group identity | UNRESOLVED. Group identity is **determined** (derived from Evidence Identity plus the independence segmentation), never generated — no `UUID.randomUUID()`, timestamp-id, or process/counter id is introduced. But the segmentation derives from EVG-009 -> depends on the missing Practice Interaction temporal model. | depends on EVG-009, EVG-019 | UNRESOLVED |
| EVG-011 | Evidence dimension mapping | Evidence dimensions reuse the locked `EvaluationDimension` vocabulary **1:1** as the evidence-stream facade — the repository has exactly one dimension vocabulary, so no second vocabulary exists to conflate. An Evidence Stream exists for `(targetId, dimension)` when the dimension is ENABLED for the target's mode AND graded data is produced. Retrieval Latency is ENABLED but UNAVAILABLE (`NO_RUNTIME_PERFORMANCE_ANCHOR`): its stream is defined but receives no contributions in the MVP. | `lib/midi/domain/evaluation_input.dart` (`EvaluationDimension`, `enabledDimensions`); `lib/midi/domain/evaluation_contract.dart` (`retrieval_latency_runtime_state`); `lib/midi/application/evaluation_dimension_observation_extractor.dart` | DERIVED |
| EVG-012 | NEP behavior | A `NOT_ENOUGH_PERFORMANCE` result yields **no** EvidenceContribution. The attempt is accounted as an ungraded attempt (a non-evidence record), so downstream cannot manufacture evidence from it. Cross-contract: frozen policy `notEnoughPerformanceEqualsZeroStars: false` and `evaluation_result.dart` ("NEP carries no stars and no zero-star") — NEP is NOT 0-star and never enters evidence as zero stars. | `lib/midi/domain/evaluation_policy.dart` (`ResultStatePolicy.notEnoughPerformanceEqualsZeroStars: false`); `lib/midi/domain/evaluation_result.dart` (NEP has no stars) | DEFINED |
| EVG-013 | Zero-star behavior | An `EVALUATED` result with 0 stars IS a genuine, fully-graded performance and DOES produce evidence. Star value 0..5 is recorded as observed quality on the contribution. Zero stars are evidence, not absence of evidence; they are not collapsed into, or replaced by, NEP. | `lib/midi/domain/evaluation_result.dart` (`EvaluatedResult` stars in `0..5`); `lib/midi/domain/evaluation_policy.dart` (`evaluatedMinStars: 0`, `evaluatedMaxStars: 5`) | DEFINED |
| EVG-014 | Evidence provenance | Every contribution carries the provenance vocabulary already propagated by every locked layer result (EV-012 convention): `targetId`, `sessionId`, `mode`, `evaluationProfileId`, `evaluationProfileVersion`, engine algorithm versions; plus Evidence Identity, contribution kind, and (when resolved) the Practice Interaction reference. Composition of provenance follows the mechanical propagation convention; no new identity vocabulary is invented. | `lib/midi/domain/evaluation_input.dart` (identity + layer version fields); `docs/evaluation-contract-v1.1-decision-matrix.md` (EV-012 DERIVED) | DERIVED |
| EVG-015 | Retrieval Instance | NOT_APPLICABLE in v1.1: no review/retrieval mechanism exists in the locked architecture, and a Retrieval Instance is a scheduler-coupled concept. It must not be conflated with an Attempt or a Practice Interaction. | `lib/midi` (no scheduler/review artifact present) | NOT_APPLICABLE |
| EVG-016 | Retention | UNRESOLVED. The H2.10A.1 re-audit found NO existing definition anywhere (working tree, history, branches, docs) that establishes Retention as an Evidence state, Evidence Group property, derived longitudinal signal, Mastery concept, or Scheduler concept. The phase rule allows `NOT_APPLICABLE`/`DEFERRED` only when justified by an existing contract; no such contract exists. A vocabulary-only gloss requires an elapsed-practice-time model that does not exist (EVG-019), and manufacturing semantics is forbidden. | H2.10A.1 audit section above; depends on EVG-019 | UNRESOLVED |
| EVG-017 | Degradation | UNRESOLVED. Same as EVG-016: no existing source defines Degradation; no existing contract justifies classifying it NOT_APPLICABLE/DEFERRED; its semantics need elapsed-time data that do not exist. | H2.10A.1 audit section above; depends on EVG-019 | UNRESOLVED |
| EVG-018 | Lapse | UNRESOLVED. Same as EVG-016: no existing source defines Lapse; no existing contract justifies classifying it NOT_APPLICABLE/DEFERRED; its semantics need elapsed-time data that do not exist. | H2.10A.1 audit section above; depends on EVG-019 | UNRESOLVED |
| EVG-019 | Temporal semantics | UNRESOLVED. The audit confirmed the locked architecture contains NO practice-interaction timestamp, NO wall-clock source, and NO `ready_timestamp`; `DateTime.now()` has zero hits in `lib/`. The only time data is MIDI capture `app_monotonic_ts_ms` (device-session time base) and observed-stream onset/end timestamps; `evaluation_dimension_observation_extractor` explicitly rejects session start, first event, target creation, and wall clock as an anchor, and the phase brief excludes reusing capture monotonic time for interaction-level semantics. Because no Practice Interaction lifecycle timestamps exist, the EVG-007/008 gap cannot be computed as `laterInteraction.started_at - earlierInteraction.ended_at` or any other form. This is the primary blocker of H2.10A. | H2.10A.1 audit section above; `lib/midi/diagnostics` (`app_monotonic_ts_ms`); `lib/midi/application/evaluation_dimension_observation_extractor.dart` (rejected anchor list) | UNRESOLVED |
| EVG-020 | Deterministic identity | All Evidence identity (stream, contribution, group) is DERIVED deterministically from content (target identity, dimension, attempt, algorithm/profile versions). Random ids, wall-clock-now, global mutable state, and process-local counters are forbidden as semantic identity sources. | H2.10A brief guardrail | DEFINED |
| EVG-021 | Immutability | Evidence contributions and groups are immutable: versioned, never mutated in place, following the locked pipeline immutability convention ("mutating source collections cannot mutate ..."). | `test/evaluation_input_preparer_test.dart` (immutability invariant); H2.10A brief guardrail | DEFINED |
| EVG-022 | Evidence <-> Mastery | Evidence carries NO mastery. No mastery thresholds, levels, `acquired`/`qualified`/`fluency` vocabulary may be inferred from or encoded into evidence. Mastery is deferred beyond Evidence v1.1. | `README.md` (mastery is a future goal); `lib/midi` (no mastery artifact present) | DEFINED |
| EVG-023 | Evidence <-> Scheduler | Evidence carries NO scheduler vocabulary: no `SUCCESS`/`MARGINAL_SUCCESS`/`FAILURE`/`INVALID`/`RELEARNING_SUCCESS`, no intervals, no review outcomes. Those are scheduler-contract decisions and exist nowhere in the locked code. | `lib/midi` (no scheduler vocabulary present) | DEFINED |
| EVG-024 | Evidence <-> Lesson Star | Evaluation stars recorded on a contribution are INPUT DATA describing observed performance quality. They are NOT lesson-star accumulation. Lesson stars are a separate, frozen H2.9J policy domain (`lessonStarCapacity: 10`, `lessonStarsMonotonic: true`, `lessonStarsDecay: false`, `lessonStarsSeparateFromMastery: true`) and must never be conflated with per-attempt evidence stars. | `lib/midi/domain/evaluation_policy.dart` (frozen H2.9J star policy) | DEFINED |

## Decision Summary

```text
Total decisions:   24
Defined:           13
Derived:            2
Not Applicable:     1
Unresolved:         8
```

## Decisions Unresolved After H2.10A.1 Audit

```text
UNRESOLVED BEFORE H2.10B
────────────────────────
EVG-005 practice interaction concept and temporal boundary   (no entity / no contract)
EVG-006 attempt <-> interaction mapping                      (no Attempt model exists)
EVG-009 group formation rules                                (needs interaction timestamps)
EVG-010 group identity segmentation                          (depends on EVG-009)
EVG-016 retention semantics                                  (needs elapsed-time model; no existing definition)
EVG-017 degradation semantics                                (needs elapsed-time model; no existing definition)
EVG-018 lapse semantics                                      (needs elapsed-time model; no existing definition)
EVG-019 temporal semantics of evidence independence          (primary blocker)
```

These eight requirements cannot be resolved without an upstream
`Practice Runtime` / `Practice Interaction` contract that this repository does
not contain. Per the phase rule, no replacement model is invented here.

## Lock Verdict (per phase rule)

```text
LOCKED:    NO
Status:    DRAFT
H2.10A.1:  BLOCKED - UPSTREAM PRACTICE INTERACTION SEMANTICS MISSING
Reason:    The exhaustive H2.10A.1 audit (working tree, full git history,
           both branches, stash) found no authoritative Practice
           Interaction / Practice Runtime contract. EVG-005, EVG-006,
           EVG-009, EVG-010, EVG-016, EVG-017, EVG-018, EVG-019 remain
           UNRESOLVED. The primary blocker is EVG-019: no
           practice-interaction lifecycle timestamps exist. The exact
           missing upstream artifact is a Practice Runtime contract that
           defines Practice Interaction (started_at / ended_at / item
           queue / end_reason) and its Attempt relationship.
           Implementation (H2.10B) must not start until those semantics
           are provided by an upstream phase, not invented here.
```

Repeat of H2.10A's governing instruction, honored here: where a required
decision cannot be derived, it is marked UNRESOLVED with its exact missing
basis and the exact decisions required to unblock it — never guessed.