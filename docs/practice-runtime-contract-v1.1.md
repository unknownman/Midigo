# Practice Runtime Contract v1.1 (H2.10B / H2.11)

Status of the Practice Runtime decisions required to run learner practice and
feed the Evidence Aggregation Contract v1.1.

- This contract is **semantic only**: it defines identity, boundaries,
  lifecycle, and timestamp semantics. It does NOT define an executor, scheduler,
  session composer, or UI.
- This phase resolves PR-015 (the only previously unresolved Practice Runtime
  decision) as an explicit MVP product architecture decision, and materializes
  the previously-unwritten contract.
- Guardrails: no scheduler, no mastery, no evidence, no UI, no MIDI capture
  timestamps are invented here. Everything below is either an explicit product
  decision (status `DEFINED`) or a mechanical consequence of a locked fact
  (status `DERIVED`).

## Contract identity

```text
contract_name:    Practice Runtime Contract
contract_version: v1.1
profile era:      mvp_default_v1 / Evaluation Contract v1.1 (H2.9 generation)
resolves:         PR-015 (H2.10B)
```

## PR-015 — Execution Session ↔ Practice Interaction

Resolved for MVP as an explicit product architecture decision:

```text
Practice Interaction
        │
        └── exactly one Execution Session

Practice Interaction 1 : 1 Execution Session
```

Purpose of the Execution Session: the runtime execution context through which
the Practice Interaction's Practice Items are executed.

It remains distinct from `MidiConnectionSession`.

```text
Practice Interaction
        │
        └── Execution Session
                │
                ├── Practice Item
                │      └── Attempt
                │
                ├── Practice Item
                │      └── Attempt
                │
                └── ...
```

This is deliberately NOT generalized into a future multi-session orchestration
system. Future revisions may revise the cardinality through a deliberate
contract revision; for v1.1 the 1:1 relationship is the only established form.

| ID | Decision Area | Decision | Status |
| -- | ------------- | -------- | ------ |
| PR-015 | Execution Session ↔ Practice Interaction | 1:1. A Practice Interaction owns exactly one Execution Session, which is the runtime context executing its Practice Items. | DEFINED |

## Entities and semantics

| ID | Decision Area | Decision | Source / Basis | Status |
| -- | ------------- | -------- | -------------- | ------ |
| RT-001 | Practice Runtime | The Practice Runtime is the domain authority that owns the Practice Interaction lifecycle and mediates between curriculum/session-composition (upstream) and Evidence (downstream). It is a domain concept, not a UI concept and not a MIDI concept. v1.1 materializes its boundary, not an executor. | H2.11 brief; README `practice runtime` (later phase) | DEFINED |
| RT-002 | Practice Interaction purpose | One Practice Interaction = one learner-facing practice engagement with a coherent set of Practice Items. It is the unit Evidence aggregation's 15-minute rule is anchored on. | H2.10A (EVG-005/007); H2.11 | DEFINED |
| RT-003 | Practice Interaction identity | Practice Interaction identity is deterministic (content/supplied), never random and never wall-clock-based. The identifier is carried by Evidence provenance when evidence is produced. | H2.10A guardrail (EVG-020); H2.11 | DERIVED |
| RT-004 | Practice Interaction lifecycle timestamps | A Practice Interaction carries `started_at` and `ended_at`. These belong to the practice domain and MUST NOT be synthesized from MIDI capture `app_monotonic_ts_ms`, first-note time, target-creation time, or wall-clock inference in the evaluation layer. `end_reason` is part of the interaction record. | H2.10A (EVG-011/019 rejections); H2.11 §22 | DEFINED |
| RT-005 | Practice Item | A Practice Interaction executes one or more Practice Items. A Practice Item is one executable practice unit referencing an Exercise Instance (see RT-006). Practice Items are owned by the Practice Interaction. | H2.10B layer stack (`Exercise Instance ≠ Practice Item`); H2.11 §21 diagram | DEFINED |
| RT-006 | Exercise Instance relationship | A Practice Item consumes/executes an Exercise Instance. An Exercise Instance is the concrete instantiation selected by the Exercise Generator; the Practice Runtime does not generate curriculum or Exercise Instances (that is Exercise Generator's responsibility, a separate contract). | H2.10B; `expected_musical_target_factory.dart` ("does not implement the curriculum", "never generates an Exercise Instance"); H2.11 §25 | DERIVED |
| RT-007 | Attempt | An Attempt is the runtime record of one learner performance against one Practice Item. Each Attempt is evaluated by the Evaluation Contract. An Attempt is NOT an EvaluationResult, NOT an EvidenceContribution, NOT an Exercise Instance, NOT a Practice Interaction. | H2.10A (EVG-003/006); `expected_musical_target.dart` (negative identity); H2.11 §25 | DEFINED |
| RT-008 | Attempt lifecycle | Locked vocabulary: `ARMED → ACTIVE ↕ PAUSED → COMPLETED`. Terminal non-completion states: `ABANDONED`, `INVALIDATED`. `FAILED` is NOT a runtime lifecycle state (see PR/RT-010). | H2.11 §22; `evaluation_policy.dart` `lifecycleStatesOutsideResult` | DEFINED |
| RT-009 | ABANDONED ≠ FAILED | `ABANDONED` is a deliberate learner-initiated stop before completion; it is a runtime lifecycle outcome. `FAILED` is not a runtime lifecycle state at all. The two are never merged. | H2.11 §22, §25; `result_state.lifecycle_states_outside_result` contains `FAILED` only as evidence/evaluation vocabulary | DEFINED |
| RT-010 | FAILED exclusion | FAILED must NOT be added to the runtime lifecycle vocabulary unless an explicit higher-authority artifact requires it. No such artifact exists. Evaluation keeps FAILED outside the EvaluationResult (it is lifecycle vocabulary outside the result, per H2.9 policy), but it is not a runtime state. | H2.11 §22; `evaluation_policy.dart` `ResultStatePolicy.lifecycleStatesOutsideResult` | DEFINED |
| RT-011 | Execution Session identity | An Execution Session is the runtime execution context of exactly one Practice Interaction. It MUST NOT be conflated with `MidiConnectionSession` (H1.2 device capture session: sessionId/deviceId/connectionType, no timestamps, no practice semantics). | H2.11 §21; `lib/midi/domain/midi_connection_session.dart` | DEFINED |
| RT-012 | Timestamp domains | Three distinct temporal domains are NEVER conflated: (a) practice lifecycle timestamps (`started_at`/`ended_at` of Practice Interaction), (b) MIDI capture `app_monotonic_ts_ms` (device-session time base), (c) observed-stream onset/end timestamps (MIDI time base). Practice timestamps are not derived from MIDI; MIDI timestamps are not promoted to practice time. | H2.10A (EVG-019); H1.3; H2.6/H2.7 docs | DEFINED |
| RT-013 | Ownership boundaries | Exactly-one ownership per concept: Attempt owned by Practice Item (and transitively its Practice Interaction); Practice Item owned by Practice Interaction; Execution Session owned 1:1 by Practice Interaction; Practice Interaction ≠ Execution Session ≠ MidiConnectionSession; Exercise Generator ≠ Practice Runtime; Session Composer consumes Practice Runtime output but is not part of it. | H2.11 §25; PR-015 | DEFINED |
| RT-014 | Evidence handoff | Practice Runtime provides Evidence with: evaluated Attempt outcome (EvaluationResult), the owning Practice Interaction identity, and interaction lifecycle timestamps needed for the 15-minute independence rule (EVG-007/008/019). Evidence semantics are the Evidence Contract's, not the Runtime's. | H2.10A; H2.11 §23 | DERIVED |
| RT-015 | No implementation vocabulary | The contract does not invent scheduler intervals, review eligibility, mastery levels, intervals, or prioritization. Retaining/review scheduling is the Scheduler's domain; "review-ready" status is determined by the Session Composer/Scheduler, not exposed as evidence or mastery. | H2.10A (EVG-022/023); H2.11 §11-12 | DEFINED |

## Explicit non-goals in v1.1

```text
No PracticeRuntime executor implementation
No PracticeInteraction / PracticeItem / Attempt / ExecutionSession models in code
No scheduler, no review engine, no interval computation
No mastery updates
No MIDI capture semantics
```

## Lock status

```text
LOCKED:    YES
Status:    LOCKED (v1.1)
PR-015:    RESOLVED - Practice Interaction 1:1 Execution Session (MVP decision)
Blockers:  none remaining for Practice Runtime semantics
```

Consistency: Practice Runtime is compatible with the Evidence Contract (15-minute
rule now has temporal operands), the Evaluation Contract (Attempt → EvaluationResult,
FAILED stays outside runtime lifecycle), the MVPR Product Contract (first skill
C Major/RH/Block), and the Learning UX Contract (Lesson → Practice → Result).
Execution Session stays distinct from MIDI Connection Session.