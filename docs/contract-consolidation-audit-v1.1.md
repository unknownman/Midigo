# Contract Consolidation Audit v1.1 (H2.11)

Final audit across every major subsystem: whether an authoritative contract
artifact exists, whether semantics were already locked (and the artifact missing),
and cross-contract consistency. Governed by H2.11 §24-§26.

## Audit: one authoritative artifact per subsystem

| # | Subsystem | LOCKED ARTIFACT EXISTS? | Artifact | Notes |
| - | --------- | ---------------------- | -------- | ----- |
| A | Architecture | NOW EXISTS | `docs/architecture-contract-v1.1.md` | Materialized in H2.11 from locked H1/H2 facts. |
| B | Evaluation | EXISTS | `docs/evaluation-contract-v1.1-decision-matrix.md` + `lib/midi/domain/evaluation_contract.dart`, `evaluation_policy.dart`, `evaluation_engine.dart` | Locked H2.9A-K; engine frozen, 476/476 green. |
| C | Evidence | EXISTS (updated) | `docs/evidence-aggregation-contract-v1.1-decision-matrix.md` | All EVG decisions now RESOLVED (H2.11). |
| D | Practice Runtime | NOW EXISTS | `docs/practice-runtime-contract-v1.1.md` | Materialized in H2.11; PR-015 resolved. |
| E | Learning UX | NOW EXISTS | `docs/learning-ux-contract-v1.0.md` | Materialized in H2.11. |
| F | MVP Product | NOW EXISTS | `docs/mvp-product-contract-v1.1.md` | Materialized in H2.11; first skill `chord.major.C.RH.block`. |
| G | Mastery | BOUNDARY LOCKED | `docs/contract-consolidation-audit-v1.1.md` §"Mastery (boundary)" | Detail-dependent internals deferred beyond slice 1 (H2.11 §28). |
| H | Scheduler | BOUNDARY LOCKED | §"Scheduler (boundary)" | Responsibility + anonymity boundary locked; review engine deferred. |
| I | Priority Aggregator | BOUNDARY LOCKED | §"Priority Aggregator (boundary)" | Internal allocation remains opaque to presentation. |
| J | Session Composer | BOUNDARY LOCKED | §"Session Composer (boundary)" | User controls duration/when; system controls what/order. |
| K | Exercise Generator | BOUNDARY LOCKED | §"Exercise Generator (boundary)" | Generates Exercise Instances; distinct from Runtime + Composer; deferred. |

### Mastery (boundary)

- Mastery is a separate concept from Evaluation stars, Evidence, and lesson
  stars. Locked: `lessonStarsSeparateFromMastery: true` (H2.9J); evidence
  carries NO mastery (EVG-022); mastery is a future goal (README).
- Learner-facing labels map to domain state; H2.11 forbids a new backend
  mastery model solely for UI labels.
- Mastery internals (acquired/qualified/fluency thresholds) are deferred beyond
  the first vertical slice (H2.11 §28). No such vocabulary may be introduced by
  implementation.

### Scheduler (boundary)

- Sole owner of review eligibility and the New/Review/Relearning decision.
- No scheduler vocabulary inside Evidence (EVG-023): no
  SUCCESS/MARGINAL_SUCCESS/FAILURE/INVALID/RELEARNING_SUCCESS, no intervals, no
  review outcomes in evidence.
- UI must not build a second scheduling state machine or expose intervals.
- Internal scheduler algorithm deferred beyond slice 1 (H2.11 §28); the Review
  UX shows "No reviews due" when no real item exists (H2.11 §29).

### Priority Aggregator (boundary)

- Internal input for session composition; allocation weights / priority
  formulas are never exposed to presentation (H2.11 §15).
- No evidence/mastery coupling. Internal algorithm deferred.

### Session Composer (boundary)

- User controls duration + when; system controls what + order (H2.11 §15/§17).
- UI consumes the composed plan; it never recomputes priorities.
- Composer is distinct from the Practice Runtime and the Exercise Generator
  (H2.11 §25). Internal algorithm deferred.

### Exercise Generator (boundary)

- Owns curriculum + Exercise Instance generation; distinct from Practice
  Runtime, which only consumes/executes instances (RT-006), and distinct from
  the Session Composer.
- `ExpectedMusicalTargetFactory` builds target FORMS only and "does not
  implement the curriculum" / "never generates an Exercise Instance" (locked).
- Generator internals deferred beyond slice 1 (H2.11 §28).

## Consistency audit (H2.11 §25)

```text
Attempt       ≠ EvaluationResult        (H2.10A EVG-003; evaluation_result.dart)     OK
Attempt       ≠ Evidence                (EVG-003; RT-007)                            OK
Evidence      ≠ Mastery                 (EVG-022)                                    OK
Scheduler     ≠ Mastery                 (EVG-023 boundary; separate contracts)       OK
Exercise Generator ≠ Practice Runtime   (RT-006)                                     OK
Session Composer ≠ Exercise Generator   (boundary above; H2.11 §25)                  OK
Practice Interaction ≠ MIDI Connection Session  (RT-011)                             OK
Execution Session ≠ MIDI Connection Session      (PR-015 / RT-011)                   OK
Skill Identity ≠ Musical Target ≠ Playable Realization ≠ Exercise Instance
  ≠ Practice Item ≠ Attempt             (H2.10B layer stack)                         OK
```

No duplicate ownership. Each concept has exactly one owning contract.

## Final contract status (H2.11 §35)

```text
Contract                         Status       Artifact
----------------------------------------------------------------
Architecture                     LOCKED       docs/architecture-contract-v1.1.md
Evaluation                       LOCKED       evaluation-contract matrix + evaluation_*.dart (frozen, 476/476)
Evidence                         LOCKED       docs/evidence-aggregation-contract-v1.1-decision-matrix.md
Mastery                          LOCKED       consolidation audit §boundary (internals deferred)
Scheduler                        LOCKED       consolidation audit §boundary (internals deferred)
Priority Aggregator              LOCKED       consolidation audit §boundary (internals deferred)
Session Composer                 LOCKED       consolidation audit §boundary (internals deferred)
Exercise Generator               LOCKED       consolidation audit §boundary (internals deferred)
Practice Runtime                 LOCKED       docs/practice-runtime-contract-v1.1.md
MVP Product                      LOCKED       docs/mvp-product-contract-v1.1.md
Learning UX                      LOCKED       docs/learning-ux-contract-v1.0.md
```

Deferred internals (Mastery thresholds, Scheduler algorithm, Priority
Aggregator, Session Composer internals, Exercise Generator internals) are
explicitly out of the first vertical slice per H2.11 §28 and therefore do not
constitute unresolved decisions blocking the gate.

## Implementation gate (H2.11 §26)

```text
[ x ] Evaluation Contract locked
[ x ] Evaluation implementation frozen and passing (476/476, analyze clean)
[ x ] Evidence semantics locked
[ x ] Practice Runtime semantics locked
[ x ] Mastery semantics locked
[ x ] Scheduler semantics locked
[ x ] Session Composer semantics locked
[ x ] Exercise Generator semantics locked
[ x ] MVP Product Contract locked
[ x ] Learning UX Contract locked
[ x ] no unresolved decision blocks the first vertical slice

IMPLEMENTATION GATE: PASS
```