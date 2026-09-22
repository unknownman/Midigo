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
| EVG-005 | Practice Interaction | RESOLVED. A Practice Interaction is one coherent practice engagement with a set of Practice Items; identity is deterministic; it carries practice-domain `started_at`/`ended_at` and `end_reason`; it is the Evidence 15-minute-rule anchor; it is never derived from MIDI capture `app_monotonic_ts_ms` and is distinct from `MidiConnectionSession`. | H2.11 PR-015; `docs/practice-runtime-contract-v1.1.md` RT-002/RT-004/RT-011/RT-012; H2.10A brief (15-min rule anchor) | RESOLVED |
| EVG-006 | Attempt <-> Interaction | RESOLVED. Every Attempt belongs to exactly one Practice Item and therefore exactly one Practice Interaction (transitively). Attempt Identity ≠ Practice Interaction Identity. Attempts do not exist outside a Practice Interaction; the interaction identity is available to Evidence provenance. | `docs/practice-runtime-contract-v1.1.md` RT-007/RT-013; H2.10A brief (Attempt != evidence identity) | RESOLVED |
| EVG-007 | Evidence dependency semantics | Locked classification rule: contributions from the SAME Practice Interaction are DEPENDENT; contributions from DIFFERENT interactions whose gap is LESS THAN 15 minutes are DEPENDENT; contributions from DIFFERENT interactions whose gap is AT LEAST 15 minutes are INDEPENDENT. The rule is a product decision; its operands (gap, interaction boundary) are blocked by EVG-019/EVG-005. | H2.10A brief (explicit rule) | DEFINED |
| EVG-008 | 15-minute threshold | Locked typed policy: `threshold = 15 minutes`, **boundary inclusive** — a gap of exactly 15:00 classifies as INDEPENDENT. This is the only numeric Evidence policy of v1.1. | H2.10A brief (inclusive boundary explicit) | DEFINED |
| EVG-009 | Evidence group | RESOLVED. A group is the deterministic unit of contributions sharing Evidence Identity, delimited by independence boundaries from EVG-007/008. Because the gap operand now exists (EVG-019) and interaction boundaries are defined (EVG-005), group formation is implementable. | depends on EVG-005, EVG-007, EVG-010, EVG-019 (all resolved) | RESOLVED |
| EVG-010 | Group identity | RESOLVED. Group identity is determined (derived from Evidence Identity plus EVG-009's independence segmentation) using the now-resolved Practice Interaction boundary; never generated by random/clock/counter. | depends on EVG-009, EVG-019 (both resolved); H2.10A guardrail (deterministic identity) | RESOLVED |
| EVG-011 | Evidence dimension mapping | Evidence dimensions reuse the locked `EvaluationDimension` vocabulary **1:1** as the evidence-stream facade — the repository has exactly one dimension vocabulary, so no second vocabulary exists to conflate. An Evidence Stream exists for `(targetId, dimension)` when the dimension is ENABLED for the target's mode AND graded data is produced. Retrieval Latency is ENABLED but UNAVAILABLE (`NO_RUNTIME_PERFORMANCE_ANCHOR`): its stream is defined but receives no contributions in the MVP. | `lib/midi/domain/evaluation_input.dart` (`EvaluationDimension`, `enabledDimensions`); `lib/midi/domain/evaluation_contract.dart` (`retrieval_latency_runtime_state`); `lib/midi/application/evaluation_dimension_observation_extractor.dart` | DERIVED |
| EVG-012 | NEP behavior | A `NOT_ENOUGH_PERFORMANCE` result yields **no** EvidenceContribution. The attempt is accounted as an ungraded attempt (a non-evidence record), so downstream cannot manufacture evidence from it. Cross-contract: frozen policy `notEnoughPerformanceEqualsZeroStars: false` and `evaluation_result.dart` ("NEP carries no stars and no zero-star") — NEP is NOT 0-star and never enters evidence as zero stars. | `lib/midi/domain/evaluation_policy.dart` (`ResultStatePolicy.notEnoughPerformanceEqualsZeroStars: false`); `lib/midi/domain/evaluation_result.dart` (NEP has no stars) | DEFINED |
| EVG-013 | Zero-star behavior | An `EVALUATED` result with 0 stars IS a genuine, fully-graded performance and DOES produce evidence. Star value 0..5 is recorded as observed quality on the contribution. Zero stars are evidence, not absence of evidence; they are not collapsed into, or replaced by, NEP. | `lib/midi/domain/evaluation_result.dart` (`EvaluatedResult` stars in `0..5`); `lib/midi/domain/evaluation_policy.dart` (`evaluatedMinStars: 0`, `evaluatedMaxStars: 5`) | DEFINED |
| EVG-014 | Evidence provenance | Every contribution carries the provenance vocabulary already propagated by every locked layer result (EV-012 convention): `targetId`, `sessionId`, `mode`, `evaluationProfileId`, `evaluationProfileVersion`, engine algorithm versions; plus Evidence Identity, contribution kind, and (when resolved) the Practice Interaction reference. Composition of provenance follows the mechanical propagation convention; no new identity vocabulary is invented. | `lib/midi/domain/evaluation_input.dart` (identity + layer version fields); `docs/evaluation-contract-v1.1-decision-matrix.md` (EV-012 DERIVED) | DERIVED |
| EVG-015 | Retrieval Instance | NOT_APPLICABLE in v1.1: no review/retrieval mechanism exists in the locked architecture, and a Retrieval Instance is a scheduler-coupled concept. It must not be conflated with an Attempt or a Practice Interaction. | `lib/midi` (no scheduler/review artifact present) | NOT_APPLICABLE |
| EVG-016 | Retention | RESOLVED (deferred). The H2.11 Practice Runtime Contract defines NO retention model (RT-015); retention is a longitudinal, Scheduler/Mastery-coupled review concern with no mechanism in the locked architecture. It is explicitly out of Evidence v1.1 scope, consistent with EVG-022 (evidence carries no mastery). No elapsed-practice-time product model is invented. | `docs/practice-runtime-contract-v1.1.md` RT-015; EVG-022; H2.10A.1 audit | RESOLVED-DEFERRED |
| EVG-017 | Degradation | RESOLVED (deferred). Same basis as EVG-016: no degradation model exists in the locked architecture or the Practice Runtime contract; out of Evidence v1.1 scope; nothing invented. | `docs/practice-runtime-contract-v1.1.md` RT-015; EVG-022 | RESOLVED-DEFERRED |
| EVG-018 | Lapse | RESOLVED (deferred). Same basis as EVG-016: lapse requires a review/retrieval mechanism and elapsed-time semantics owned by Scheduler/Mastery; out of Evidence v1.1 scope; nothing invented. | `docs/practice-runtime-contract-v1.1.md` RT-015; EVG-022 | RESOLVED-DEFERRED |
| EVG-019 | Temporal semantics | RESOLVED. The independence gap is `laterInteraction.started_at − earlierInteraction.ended_at` in practice-domain time (RT-004/RT-012). Practice timestamps are NEVER derived from MIDI capture `app_monotonic_ts_ms`; the extractor's rejected-anchor rule is unchanged. Boundary inclusive: gap exactly 15:00 → INDEPENDENT (EVG-008). This is the operand formerly missing. | `docs/practice-runtime-contract-v1.1.md` RT-004/RT-012/RT-014; H2.10A brief EVG-008; `lib/midi/application/evaluation_dimension_observation_extractor.dart` (rejected anchor list) | RESOLVED |
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
Unresolved:         0
Resolved-Deferred:  3   (EVG-016, EVG-017, EVG-018 - out of Evidence v1.1 scope)
```

Superseded by the H2.11 resolution below: the eight UNRESOLVED decisions from
H2.10A.1 are all resolved through the new Practice Runtime Contract v1.1. Three
of them (Retention, Degradation, Lapse) are resolved as DEFINED exclusions from
Evidence v1.1 (they are Scheduler/Mastery-coupled review concepts with no locked
mechanism), not as absent decisions.

## Decisions Resolved After H2.10A.1 Audit (H2.11)

```text
UNRESOLVED BEFORE H2.11   →   RESOLVED BY PRACTICE RUNTIME CONTRACT v1.1
─────────────────────────────────────────────────────────────────────
EVG-005 practice interaction concept and temporal boundary   → RESOLVED (RT-002/004)
EVG-006 attempt <-> interaction mapping                      → RESOLVED (RT-007/013)
EVG-009 group formation rules                                → RESOLVED (EVG-007/008/019)
EVG-010 group identity segmentation                          → RESOLVED (EVG-009)
EVG-016 retention semantics                                  → RESOLVED-DEFERRED (out of scope)
EVG-017 degradation semantics                                → RESOLVED-DEFERRED (out of scope)
EVG-018 lapse semantics                                      → RESOLVED-DEFERRED (out of scope)
EVG-019 temporal semantics of evidence independence          → RESOLVED (RT-004/012/014)
```

All eight requirements are resolved by the H2.11 Practice Runtime Contract v1.1
(`docs/practice-runtime-contract-v1.1.md`). No replacement model is invented;
every resolution is grounded in the upstream contract.

## H2.11 Resolution — Upstream semantics now present

The H2.11 phase resolves the H2.10 blocker by supplying the authoritative
Practice Runtime Contract v1.1 (`docs/practice-runtime-contract-v1.1.md`),
which includes the MVP product decision PR-015 (Practice Interaction 1:1
Execution Session). The missing temporizational and attempt semantics for the
Evidence rules that follow are therefore established by a real upstream
contract rather than invented here.

Superseding source: `docs/practice-runtime-contract-v1.1.md` (RT-001..RT-015).

| Previously unresolved | Now resolved by | Resolution |
| --------------------- | --------------- | ---------- |
| EVG-005 (Practice Interaction) | RT-002, RT-004 (practice interaction purpose, lifecycle timestamps) | Resolved: a Practice Interaction is one coherent practice engagement; it carries `started_at`/`ended_at` and an `end_reason` in the practice domain; identity is deterministic; not MIDI-derived. |
| EVG-006 (Attempt ↔ Interaction) | RT-007, RT-013 (Attempt owned by Practice Item → Practice Interaction) | Resolved: every Attempt belongs to exactly one Practice Item and exactly one Practice Interaction (transitively); Attempt Identity ≠ Practice Interaction Identity distinctly. |
| EVG-009 (Evidence group) | RT-014 + EVG-007/008 | Resolved: evidence grouping uses the Practice Interaction boundary and its `started_at`/`ended_at` for the 15-minute independence gap (see EVG-019). |
| EVG-010 (Group identity) | DERIVED from the now-resolved EVG-009 | Resolved: group identity = Evidence Identity + independence segmentation; deterministic. |
| EVG-019 (Temporal semantics) | RT-004, RT-012, RT-014 | Resolved: independence gap = `laterInteraction.started_at − earlierInteraction.ended_at` computed in practice-domain time; the boundary is inclusive (gap exactly 15:00 → INDEPENDENT per EVG-008); practice timestamps are never derived from MIDI capture `app_monotonic_ts_ms`. |
| EVG-016 (Retention) | RT-015 | Resolved: NOT a Practice Runtime or Evidence v1.1 concept. Retention is a longitudinal signal tied to Scheduler/Mastery and a review mechanism that does not exist in the locked architecture. Deferred beyond Evidence v1.1 (EVG-022). |
| EVG-017 (Degradation) | RT-015 | Resolved: NOT a Practice Runtime or Evidence v1.1 concept. Deferred alongside Retention (EVG-022); its operational definition needs an elapsed-time model owned by Scheduler/Mastery. |
| EVG-018 (Lapse) | RT-015 | Resolved: NOT a Practice Runtime or Evidence v1.1 concept. Deferred alongside Retention (EVG-022). |

## Lock Verdict (per phase rule)

```text
LOCKED:    YES
Status:    LOCKED
H2.10A.1:  SUPERSEDED BY H2.11 - PRACTICE RUNTIME CONTRACT v1.1 MATERIALIZED
Reason:    The H2.11 phase provided the authoritative upstream Practice
           Runtime Contract v1.1 (docs/practice-runtime-contract-v1.1.md),
           resolving PR-015 (Practice Interaction 1:1 Execution Session)
           and the practice-interaction lifecycle timestamps. EVG-005,
           EVG-006, EVG-009, EVG-010, EVG-019 are now RESOLVED; EVG-016,
           EVG-017, EVG-018 are RESOLVED as deferred (Scheduler/Mastery-
           coupled, out of Evidence v1.1 scope). No EVG decision remains
           UNRESOLVED. Evidence v1.1 semantics are complete.
Supersedes: the earlier BLOCKED/DRAFT verdict of H2.10A/H2.10A.1.
```

Repeat of H2.10A's governing instruction, honored here: where a required
decision cannot be derived, it is marked UNRESOLVED with its exact missing
basis and the exact decisions required to unblock it — never guessed. In
H2.11 every such basis is now supplied by the upstream contract, so each
decision is resolved from an authoritative source rather than guessed.