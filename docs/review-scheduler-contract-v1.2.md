# Review Scheduler Contract v1.2

Status: **LOCKED (v1.2)** — production contract, not a decision matrix.
Scope: contract definition only. Implements no scheduler code, no Review Hub,
no Review Session. This document is the authoritative definition of review
scheduling that H2.9 will implement without inventing scheduler behavior.

The repository previously contained **no** Review Scheduler Contract v1.2 and
**no** scheduler persistence. This phase fills that archiving gap. It is
written to sit beside the frozen boundaries it consumes (see §22):

- Evaluation Contract v1.1 (`lib/midi/domain/evaluation_result.dart`,
  `lib/midi/domain/evaluation_policy.dart`)
- Practice Runtime v1.1 (`docs/practice-runtime-contract-v1.1.md`,
  `lib/practice/domain/attempt.dart`, `lib/practice/domain/practice_interaction.dart`,
  `lib/practice/domain/practice_clock.dart`)
- Learning Curriculum & Lesson Architecture v1.0 (`docs/learning-curriculum-architecture-v1.0.md`,
  `docs/learning-curriculum-lesson-architecture-v1.0.md`)
- Learning UX Contract v1.0 (`docs/learning-ux-contract-v1.0.md`)
- Evidence Aggregation v1.1 (`docs/evidence-aggregation-contract-v1.1-decision-matrix.md`)
- Mastery v1.2.1 (boundary, `docs/contract-consolidation-audit-v1.1.md`)
- Practice Sequence MVP H2.8 (`lib/practice/domain/practice_exercise.dart`)
- MVP Product v1.1 (`docs/mvp-product-contract-v1.1.md`)

---

## 1. Purpose

Define, precisely and deterministically, the product-specific MVP review
scheduler so that H2.9 can build the Review Hub and Review Session **without
inventing scheduler behavior**. The scheduler is the **sole owner** of:

```text
review eligibility
review scheduling
review response interpretation
next review timing
```

The scheduler does NOT evaluate MIDI, does NOT own LessonProgress, and does NOT
own Mastery. It never writes evidence. It is deliberately small and
un-anthropomorphic: no FSRS, no SM-2, no machine learning, no retention
prediction, no parameter fitting.

Review is "Anki-like *only* in its spaced-repetition recall scheduling" (§3.1
of the phase brief). Nothing else about Anki is adopted.

---

## 2. Scope

In-scope for v1.2:

```text
skill identity and scope
review eligibility (single establishment channel)
per-skill scheduler state
initial scheduling
Review response model (three responses)
Evaluation → scheduler response mapping
success / failure / I Already Know interval transitions
Skip for Now semantics (zero mutation)
retry semantics (one item → one response)
Review Session independence (per-skill, never aggregated)
Start All (a UI iteration over independent items)
time semantics (application clock)
persistence semantics
determinism and testability
application-facing API boundary
```

Out-of-scope (explicitly refused, §18–§19, §22):

```text
scheduler code / implementation (this phase)
Review Hub / Review Session / Review UI (H2.9)
Mastery model, mastery score, mastery decay, mastery thresholds
LessonProgress mutation, lesson stars, lesson state
Teach / PracticeExercise completion state
evidence contribution / evidence groups
priority aggregation, session composition ordering policy
adaptive tempo, personalization, parameter fitting
```

---

## 3. Terminology

| Term | Definition |
| ---- | ---------- |
| **Skill** | An atomic musical capability identified by its pinned target id (`targetId`) from the frozen curriculum catalog (e.g. `major-c-rh-block`). |
| **Skill in schedule scope** | A Skill that has an associated curriculum Lesson in the frozen catalog (MVP: the six C Major lesson targets). `skillId : targetId` 1:1 by `lesson.targetId == skillId`. |
| **Review Eligible** | The Skill has been explicitly established in the schedule (see §4). Established exactly once, never automatically. |
| **Ready / Due** | Eligible AND `nextReviewAt <= clock.now()`. This is the only state the Review Hub surfaces as an item. |
| **Scheduled Review response** | One of exactly three values that mutate the schedule: `successfulReview`, `unsuccessfulReview`, `iAlreadyKnow` (§7). |
| **No-transition event** | Anything that must not reach the scheduler: Skip for Now, Start practice, Lesson activity, abandoned/invalidated review attempt, NOT_ENOUGH_PERFORMANCE. Such events are structurally outside the scheduler (never passed to `recordReviewResponse` in §20). |
| **Committed review item** | A scheduled Review item that the learner has definitively advanced past (see §13). |
| **Lesson Completion** | The existing curriculum acquisition state: the associated lesson's `LessonProgress.isEmpty == false` and `LessonProgress.stars >= LessonProgress.starCapacity` (10/10, `LessonProgressState.completed`). Frozen in `lib/practice/application/lesson_progress.dart` (`starCapacity = 10`). |

Learner-facing copy NEVER uses scheduler terminology (`nextReviewAt`, interval,
due, retention, lapse). The UI contracts already reserve the learner
vocabulary: `Review | No reviews due | Ready` (Learning UX §15).

---

## 4. Review Eligibility

Eligibility has **exactly one establishment channel** in v1.2:

```text
A Skill becomes Review Eligible by explicit registration through
RegisterEligibleSkill(skillId), invoked exactly once, at the moment its
associated curriculum Lesson becomes Completed (10/10 lesson stars).
```

Rules:

1. **Initial eligibility requires Lesson Completion.** The transition that
   triggers `registerEligibleSkill` is the associated lesson reaching its
   frozen acquisition ceiling (`LessonProgress.stars >= 10`). This is the
   explicit LessonProgress→eligibility relationship requested by the phase
   brief (§4, §15 of the H2.9 brief); it is established here, not assumed.
2. **Lesson Completion is required.** A Skill with an uncompleted associated
   lesson is never eligible.
3. **Exercise Completion alone is not sufficient.** Both the exercise sequence
   and the acquisition ceiling belong to Curriculum Completion; but the single
   authoritative predicate for v1.2 eligibility is Lesson Completion at 10/10
   (which, in the current single-form lessons, already subsumes the sequence).
4. **Mastery is never required.** Mastery does not exist in v1.2 (§18).
5. **No previous Review is required** for first eligibility.
6. **The Scheduler never reads LessonProgress.** It does not poll, read, or
   reverse-derive acquisition state. It only receives `registerEligibleSkill`.
   LessonProgress remains the acquisition owner; the scheduler is the
   scheduling owner. (Reads by H2.9 orchestration to detect the completion
   transition are orchestration, not scheduler, activity.)
7. **Establishment is idempotent and sticky.** Calling `registerEligibleSkill`
   twice (or after H2.9 restart-loss) is a no-op when the record already exists
   and is eligible. Eligibility, once established, is never cleared in v1.2
   (acquisition stars are monotonic; the schedule is additive).
8. **A Skill with no associated lesson is never eligible** and never appears in
   Review. No fabricated eligibility for skills the curriculum does not teach.

The phase brief's preferred separation is therefore honored explicitly:

```text
Lesson Completion (10/10 stars)
        ↓   (orchestration calls registerEligibleSkill exactly once)
Skill becomes Review Eligible
        ↓
Review Scheduler owns everything from here (scheduling only)
```

---

## 5. Scheduler State

Authoritative, persisted, per-Skill state. Every field has a defined purpose;
nothing exists merely because Anki has it.

```text
skillId                        String        pinned target id; record key
reviewEligible                 bool          sticky true once established (§4)
nextReviewAt                   DateTime      when the skill is next due (§16)
currentIntervalDays            int           current interval, 1..21 (§8)
reviewCount                    int           committed successful+unsuccessful
                                             reviews (performances only)
successfulReviewCount          int           committed successfulReview count
unsuccessfulReviewCount        int           committed unsuccessfulReview count
lastResponse                   ReviewResponse?  last committed response; null
                                             before the first committed review
```

Field purpose:

- `skillId` — deterministic identity; record key (§17).
- `reviewEligible` — the single conjunct of "eligible" (§4/§16).
- `nextReviewAt` — the only due-determining timestamp (§16).
- `currentIntervalDays` — the only scheduling magnitude; inputs to the
  transition functions (§8).
- `reviewCount` / `successfulReviewCount` / `unsuccessfulReviewCount` /
  `lastResponse` — observational history for learner-facing summaries and
  auditing. **They never influence any transition**; determinism is preserved
  because scheduling is a pure function of `currentIntervalDays` and the
  response only.

`reviewCount == successfulReviewCount + unsuccessfulReviewCount` invariant.
`iAlreadyKnow` responses increment none of the counts (§11).

---

## 6. Initial Scheduling

The moment `registerEligibleSkill(skillId)` establishes a Skill, its initial
schedule is:

```text
initialIntervalDays  D0   = 1
nextReviewAt             = clock.now().add(Duration(days: D0))   (≈ tomorrow)
reviewCount              = 0
successfulReviewCount    = 0
unsuccessfulReviewCount  = 0
lastResponse             = null
```

Rationale for `D0 = 1` day: the MVP has no mastery model and no retrieval
science parameterization; a one-day first return is a small, honest recall
check that verifies the freshly-completed skill without letting it drift.
Every value below (D0, Dmin, Dmax) is a product constant with one authoritative
answer — H2.9 never re-derives it.

`nextReviewAt` is always an absolute application-clock timestamp produced via
`PracticeClock.now()` at the transition moment (§16), never an offset string.

---

## 7. Review Response Model

Exactly one closed response type with exactly three values:

```dart
enum ReviewResponse {
  successfulReview,
  unsuccessfulReview,
  iAlreadyKnow,
}
```

- `successfulReview` — a **committed**, real graded Review performance whose
  stars are in the success band (§9).
- `unsuccessfulReview` — a **committed**, real graded Review performance whose
  stars are in the failure band (§9).
- `iAlreadyKnow` — the learner's explicit "I already know this" assertion: **no
  MIDI attempt, no EvaluationResult, no LessonProgress, no Lesson stars, no
  evidence**; it is a first-class scheduling response but NEVER a performance,
  a success, mastery, or lesson completion (§11).

`recordReviewResponse(skillId, response)` (the signature of the API boundary,
§20) accepts **only** these three values. There is no four-value "skip-like"
response: Skip, Abandoned, Invalidated, NEP, Start, and Lesson are *not
responses* and are never passed to the scheduler. This is the explicit model
that prevents accidental mutation.

A scheduled Review item produces at most one response, exactly at commit
(§13).

---

## 8. Interval Model

Integer days. Deterministic integer arithmetic; no randomness; no hidden
state.

Constants:

```text
D0    initial interval              = 1 day
Dmin  minimum interval (floor)      = 1 day
Dmax  maximum interval (ceiling)    = 21 days
```

Transitions from `currentIntervalDays = i`, response applied at time `now`:

```text
successfulReview   → i' = min(i * 2, Dmax)          (later, doubling)
unsuccessfulReview → i' = max(i ~/ 2, Dmin)         (sooner, halving, floor)
iAlreadyKnow       → i' = max(i ~/ 2, Dmin)         (sooner, halving, floor)
```

`~/` is integer floor division (e.g. 21 → 10, 10 → 5, 5 → 2, 2 → 1); doubling
is exact. There is no rounding to a week grid, no ease factor, no randomness.

Then, atomically: `currentIntervalDays = i'` and
`nextReviewAt = now.add(Duration(days: i'))`.

Behavior at boundaries:

```text
at Dmin (1): unsuccessfulReview / iAlreadyKnow keep i' = 1.
at Dmax (21): successfulReview keeps i' = 21.
repeated successes:   1 → 2 → 4 → 8 → 16 → 21 → 21 → ...
repeated failures:    21 → 10 → 5 → 2 → 1 → 1 → ...
alternating:          success 5 → 10, failure → 5, success → 10 (no drift:
                      every step is a pure function of the current i).
```

`Dmax = 21 days` rationale: MVP scope with no mastery model; the ceiling stops a
short run of successes from pushing a skill into multi-month dormancy while the
product still lacks retrieval science. `Dmin = 1 day` keeps spaced checks from
collapsing below a human-comprehensible day granularity.

`iAlreadyKnow` deliberately uses the same *numerical* halving as failure but is
a **distinct response** that (a) does not count as a performance and (b) is
never a claim of correctness. The learner-facing meaning is "return and verify
soon"; the arithmetic is a deterministic reduction of exactly one step.
`lastResponse` distinguishes the two in state so downstream auditing can tell
them apart.

---

## 9. Success Definition

The Scheduler never evaluates MIDI. Evaluation stays owned by the frozen
EvaluationEngine (`EvaluationFlowService` → `EvaluationResult`). The mapping is
a narrow, deterministic translation at Review-orchestration time, defined on
the frozen result kinds only:

```text
EvaluationResult (frozen)                  Review Response
────────────────────────────────────────────────────────────
EvaluatedResult.stars >= 3  (3,4,5)    →   successfulReview
EvaluatedResult.stars <= 2  (0,1,2)    →   unsuccessfulReview
NotEnoughPerformanceResult              →   no response (no transition)
(none produced — abandoned/invalidated) →   no response (no transition)
```

The success band `stars >= 3` is chosen to equal the frozen exercise-completion
threshold of the Practice Sequence MVP
(`PracticeExercise.completionStarThreshold == 3`, H2.8): a successful Review
means the graded retest clears the same bar an exercise completion must clear.
An **EVALUATED** zero-, one-, or two-star performance is a real but
unsuccessful Review — it is NOT "no performance" and it is NOT NEP (frozen
`ResultStatePolicy.notEnoughPerformanceEqualsZeroStars: false`).

No new `EvaluationResult` subtype is invented. No score is reinterpreted as
mastery, evidence, or a lesson star.

---

## 10. Failure Transition

Defined by §8: `unsuccessfulReview → i' = max(i ~/ 2, Dmin)`, and
`nextReviewAt = now + i'`. An unsuccessful Review is a committed, graded
performance (stars 0..2). It always moves the next Review sooner.

---

## 11. I Already Know Transition

`iAlreadyKnow` is a first-class scheduled Review response with these exact
effects and non-effects:

```text
Effects:
  currentIntervalDays  → max(i ~/ 2, Dmin)          (one step sooner)
  nextReviewAt         → now.add(Duration(days: i'))
  lastResponse         → iAlreadyKnow

Non-effects (locked):
  no MIDI attempt, no Review performance
  no EvaluationResult, no evidence contribution
  no LessonProgress mutation, no lesson stars
  no Mastery evidence, no mastery transition
  reviewCount / successfulReviewCount / unsuccessfulReviewCount unchanged
```

There is no separate "snooze". The response is a pure schedule reduction.

---

## 12. Skip for Now Semantics

`Skip for Now` is a learner UI action with **zero scheduler mutation**:

```text
no MIDI attempt
no evaluation
no evidence
no response to the scheduler
nextReviewAt unchanged
currentIntervalDays unchanged
record unchanged
```

The Skill remains eligible and ready/due. Returning to the Review Hub shows it
again (unless an independent eligibility/time rule — none of which v1.2 defines
beyond §16 — would change it). Skip is not a postpone, a snooze, a failure, or
a success. Orchestration must never translate Skip into any `ReviewResponse`
value.

---

## 13. Retry Semantics

The critical invariant:

```text
one scheduled Review item  →  possibly multiple UI attempts  →  at most one
scheduled Review response, committed exactly once.
```

Precise rules (scheduler-semantic; the Practice Runtime lifecycle is not
touched):

1. A **Review attempt** is a run of the existing single-target evaluated
   pipeline against the Review item's frozen target. The frozen `Attempt`
   lifecycle applies (`armed → active → … → completed | abandoned |
   invalidated`, RT-011). A completed `Attempt` carries exactly one frozen
   `EvaluationResult`; abandoned/invalidated attempts carry none.
2. A **Review response candidate** is the `EvaluationResult` of the *most
   recently completed* attempt on the item while it is open.
3. **Retry** arms a fresh attempt and **discards the previous candidate**: the
   earlier result is never separately recorded by the scheduler. The candidate
   is replaced by the new completed attempt's result when it completes.
4. **Commit** happens when the learner advances past the item's Review Result
   (session "Next"/"Continue"/completion path). At commit the scheduler records
   **exactly one** response derived from the current candidate via §9, and
   applies §8 exactly once. If the candidate is `NotEnoughPerformanceResult`,
   or if no candidate exists, **no response is recorded** (the item produces no
   transition and remains as it was — it stays ready).
5. **Abandonment**: navigating away from a Review result screen without
   advancing, or abandoning the session, commits nothing. No fabricated
   success, no automatic failure, no scheduler mutation (§14).
6. Therefore the scheduler never mutates "per try". Retry can never update the
   schedule twice for one item; only the final, committed, graded outcome
   contributes — or nothing does.

This is the explicit "one item → one response" model the phase brief requires.
UI may show every attempt's result; the schedule sees only the committed one.

---

## 14. Review Session Semantics

A Review Session groups **independent** Review Items. There is no session-level
interval and no combined schedule.

```text
Review Session ≠ one scheduler item
```

- Each item is a separate skill with its own `ReviewScheduleState`.
- Each committed item receives its own §8 transition from its own response.
- Leaving a session commits only the items already advanced past (§8, §13).
  Unplayed items are never marked completed and are never reported as
  scheduled — they remain ready.
- Session completion is a UI/session concept. It does not exist in scheduler
  state.

---

## 15. Start All Semantics

`Start All` is a UI operation that begins a Review Session over all currently
ready items, in deterministic order (§16 determinism / §20 ready ordering). It
introduces no scheduler concept:

- It selects items; it does not schedule anything.
- Each selected item runs independently and commits independently.
- Example (from the phase brief): three ready items commit
  `A → successfulReview`, `B → unsuccessfulReview`, `C → iAlreadyKnow`;
  the scheduler applies `A: longer`, `B: shorter`, `C: shorter`
  independently. No aggregation, no combined interval.
- If the learner selected `Start All` but then left before processing some
  items, those items commit nothing (§13/§14).

---

## 16. Time Semantics

```text
Time source: PracticeClock.now()  (lib/practice/domain/practice_clock.dart)
```

- The Scheduler uses the application's existing practice-clock abstraction
  (`abstract interface class PracticeClock { DateTime now(); }`,
  `SystemPracticeClock` in production, deterministic fakes in tests). It never
  calls `DateTime.now()` directly, never embeds wall-clock time in identity
  (identity is `skillId` only), and never reads MIDI/capture timestamps for
  scheduling.
- `nextReviewAt` semantics:
  - Absolute application-clock instant of the *next* due boundary.
  - **due/ready** ⇔ `eligible && nextReviewAt <= clock.now()` (inclusive: an
    instant exactly equal to `nextReviewAt` is due).
  - **eligible-not-due (future)** ⇔ `eligible && nextReviewAt > clock.now()`.
  - **not eligible** ⇔ no established record (§4).
- All arithmetic uses whole calendar days via `Duration(days: n)`; DST/time-zone
  normalization is the platform `Duration` semantics — the contract defines no
  additional rule.
- These terms are internal. Learner-facing copy uses `Review / No reviews due /
  ready` (Learning UX §15) and never exposes `nextReviewAt`, interval, ease,
  retention, lapse, scheduler state, or evaluation dimensions.

---

## 17. Persistence Semantics

The Contract defines the semantic requirement; storage technology follows the
application's existing approach (interface + in-memory/store implementations,
JSON-map serialization as in `LessonProgress.toMap/fromMap`). No database is
introduced.

```text
Persisted:  one record per eligible Skill (reviewEligible true), stored under
            key skillId (the pinned target id).
Schema:     ReviewScheduleState { skillId, reviewEligible, nextReviewAt,
            currentIntervalDays, reviewCount, successfulReviewCount,
            unsuccessfulReviewCount, lastResponse }.
Serialization: camelCase map keys following the application convention
            (e.g. LessonProgress.toMap uses 'targetId', 'stars', 'attemptCount').
Written:    atomically on every scheduler mutation — Skill establishment (§6)
            and each committed response (§8/§13). Read-only operations never
            write.
Read on boot: load all records. A Skill with no record is reported as not
            eligible (and not ready). Establishment is explicit (§4); the
            scheduler never lazily materializes records from LessonProgress.
Restart:    a record that was established and committed is reconstructed
            verbatim; a `nextReviewAt` in the past reloads as immediately
            due/ready.
Migration:  none. No previous scheduler persistence exists anywhere in the
            repository (verified: no scheduler domain/application code, no
            scheduler store). v1.2 is the initial schema.
```

---

## 18. Determinism

Scheduling is a pure, closed function:

```text
state × (clock.now(), ReviewResponse) → state'
```

- Identical initial state + identical injected clock instant + identical
  committed response ⇒ identical resulting state. Always.
- No randomness, no `uuid`, no process-local counters, no hidden global state,
  no dependence on the wall clock outside `clock.now()`.
- `registerEligibleSkill` idempotent (§4.7); `getReadyReviews` ordering is
  deterministic (catalog order — see §20).

---

## 19. Clock / Testability

- The Scheduler depends on an injected `PracticeClock`. Tests inject a fake
  clock (`FakeClock`) exactly as the practice-session tests already do.
- No test may depend on the machine's real wall clock.
- Worked examples (§21) and the decision table (§23) are the canonical
  deterministic fixtures H2.9 tests will assert against.

---

## 20. API Boundary

Conceptual application-facing surface (H2.9 will implement something equal to
or a thin adapter of this). UI never calculates scheduling; the Practice
Runtime never calculates scheduling; EvaluationEngine never calculates
scheduling; the scheduler owns it.

```dart
/// The only three mutating schedule responses (see §7).
enum ReviewResponse { successfulReview, unsuccessfulReview, iAlreadyKnow }

/// Immutable, persisted per-skill schedule record (§5/§17).
final class ReviewScheduleState {
  final String skillId;
  final bool reviewEligible;
  final DateTime nextReviewAt;
  final int currentIntervalDays;
  final int reviewCount;
  final int successfulReviewCount;
  final int unsuccessfulReviewCount;
  final ReviewResponse? lastResponse;
}

/// One ready (due) item surfaced to the Review Hub: a skill plus its schedule.
final class ReviewItem {
  final String skillId;
  final ReviewScheduleState schedule;
}

/// Sole owner of review eligibility & scheduling (§1/§4/§8).
abstract interface class ReviewScheduler {
  /// The authoritative state for a skill; a skill with no established record
  /// reports not-eligible (§4, §17) — never auto-materialized.
  ReviewScheduleState getState(String skillId);

  /// Every currently ready (eligible AND due) Review item, in deterministic
  /// catalog order (frozen curriculum order — never arbitrary, never
  /// time-sorted).
  List<ReviewItem> getReadyReviews();

  /// Establishes a skill exactly once, at the Lesson-completion transition
  /// (§4/§6). Idempotent.
  void registerEligibleSkill(String skillId);

  /// Applies one committed Review response exactly once per item (§7/§9/
  /// §13). Rejects unknown values. No-performance and no-transition events
  /// are structurally never passed here.
  void recordReviewResponse(String skillId, ReviewResponse response);
}
```

Eligibility is orchestration-delivered, scheduler-owned once established ($4).
The evaluator applies the frozen `EvaluationResult → ReviewResponse` mapping
($9) at commit time; the scheduler only ever sees a `ReviewResponse`.

---

## 21. Worked Examples

Fixed deterministic clock `FakeClock(DateTime(2025,1,1,09,00,00))`;
`now(t)` = `clock` advanced to calendar date `t` 09:00.

### Example 1 — C Major (`major-c-rh-block`)

```text
2025-01-01 09:00  lesson becomes Completed (10/10 stars)
                  orchestration → registerEligibleSkill
                  state: eligible, i=1, next = 2025-01-02 09:00

2025-01-02 09:00  due (next <= now). Review performed → EvaluatedResult 5★
                  commit → successfulReview
                  i = min(1*2, 21) = 2, next = 2025-01-04 09:00

2025-01-04 09:00  due. Review → EvaluatedResult 5★ → successfulReview
                  i = 4, next = 2025-01-08 09:00

2025-01-08 09:00  due. Review → EvaluatedResult 1★ → unsuccessfulReview
                  i = max(4~/2,1) = 2, next = 2025-01-10 09:00

2025-01-10 09:00  due. learner chooses "I Already Know" → iAlreadyKnow
                  (no attempt, no evaluation)
                  i = max(2~/2,1) = 1, next = 2025-01-11 09:00
                  counts unchanged; lastResponse = iAlreadyKnow

2025-01-11 09:00  due. learner again "I Already Know"
                  i = max(1~/2,1) = 1, next = 2025-01-12 09:00   (floor)
```

### Example 2 — interval boundaries

```text
Interval 21 (after repeated success at the ceiling):
   successfulReview → i stays 21; next = now + 21 days.
   unsuccessfulReview → i = max(21~/2,1) = 10; next = now + 10 days.

Interval 1 (floor):
   unsuccessfulReview / iAlreadyKnow → i stays 1; next = now + 1 day.
   successfulReview → i = 2; next = now + 2 days.
```

### Example 3 — Start All independence (three ready items)

```text
ready: major-c-rh-block (i=2), major-c-rh-arpeggio (i=8),
       major-c-lh-block (i=1)

Start All →
  block: committed EvaluatedResult 5★  → successfulReview → i=4
  arpeggio: committed EvaluatedResult 1★ → unsuccessfulReview → i=4
  lh-block: committed "I Already Know" → iAlreadyKnow → i=1

Three independent new nextReviewAt values; no combined schedule.
```

### Example 4 — retry and abandonment

```text
item major-c-rh-block (i=4), due.

attempt 1 → finished → EvaluatedResult 1★ (candidate: unsuccessful)
Retry → fresh attempt → finished → EvaluatedResult 5★ (candidate: successful)
Commit → exactly one response: successfulReview → i=8. The 1★ is never recorded.

different item: learner begins attempt, then leaves the session without
committing → no completed candidate committed → zero mutation;
item remains ready.
```

---

## 22. Non-Goals / Boundary Alignment

The scheduler must not:

- evaluate MIDI (EvaluationEngine owns it; EV-003 series);
- own or mutate LessonProgress / lesson stars / lesson state
  (`lessonStarsSeparateFromMastery`, MVP Product v1.1);
- own Teach or PracticeExercise completion (H2.8 `completionStarThreshold`
  remains the exercise layer's);
- own Mastery (EVG-022; Mastery v1.2.1 boundary — internals deferred);
- write evidence or scheduler vocabulary into evidence (EVG-004, EVG-023);
- be exposed as UI vocabulary (Learning UX §15);
- be fused with the Session Composer / Priority Aggregator (contract
  consolidation boundaries J/I — self unaffected);
- implement FSRS/SM-2/ML/retention prediction/parameter fitting (§8).

Review (scheduler-led) is never inside the Lesson (Learning Curriculum &
Lesson Architecture §17, "Review never enters the Lesson").

---

## 23. Decision Table (locked §32 of the H2.9 brief)

| Situation                    | Performance?        | Evaluation?              | Scheduler mutation?                 |
| ---------------------------- | ------------------: | -----------------------: | ----------------------------------- |
| Successful Review            | Yes (graded)        | EVALUATED, stars 3–5     | Yes — `successfulReview`            |
| Unsuccessful Review          | Yes (graded)        | EVALUATED, stars 0–2     | Yes — `unsuccessfulReview`          |
| I Already Know               | No                  | No                       | Yes — `iAlreadyKnow` (§11)          |
| Skip for Now                 | No                  | No                       | No (§12)                            |
| Start (normal practice)      | Yes (practice)      | Yes (normal evaluation)  | No (never a response)               |
| Lesson                       | No Review           | No Review                | No (never a response)               |
| Abandoned Review             | Incomplete          | No valid result (no completed Attempt) | No (§13.5)                |
| Invalidated Review           | Invalid             | No valid result          | No (§13.5)                          |
| Not Enough Performance       | Insufficient        | NOT_ENOUGH_PERFORMANCE   | No — explicitly: NEP produces no response (§9) |

---

## 24. Contradiction Audit (phase §31)

| Check | Result | Evidence |
| ----- | ------ | -------- |
| Scheduler does not evaluate MIDI | OK | §9; Evaluation Contract v1.1 `evaluation_result.dart` frozen, untouched |
| Scheduler does not own LessonProgress | OK | §4.6/§22; `lesson_progress.dart` (starCapacity=10, monotonic) untouched; eligibility is read by orchestration, not by the scheduler |
| Scheduler does not own Mastery | OK | §18/§22; EVG-022; Mastery v1.2.1 boundary untouched |
| No mutation from Skip for Now | OK | §12 |
| I Already Know shortens next Review interval | OK | §11 (halving, floor at Dmin) |
| Normal Start practice does not mutate | OK | §15, §23 row "Start" |
| Abandoned/Invalidated never fabricate results | OK | §13.5; frozen Attempt lifecycle (no `failed` state) untouched |
| Multiple items independent | OK | §14/§15, Example 3 |
| No scheduler vocabulary in evidence | OK | EVG-023; scheduler writes only its own store (§17) |
| Review never enters the Lesson | OK | §22; Learning Curriculum & Lesson Architecture §17 |
| LessonProgress ≥ 10 not used implicitly | OK | rules made explicit in §4 (the only place acquisition enters) |
| NEP ≠ 0 stars preserved | OK | §9; `notEnoughPerformanceEqualsZeroStars: false` |
| PracticeExercise completion threshold unchanged | OK | §9 reuses `completionStarThreshold == 3` read-only |
| Evidence v1.1 practiceAttempt kind unchanged | OK | Review performances traverse the existing runtime; evidence pipeline untouched |

No contradiction found. No frozen contract is modified by this phase.

---

## 25. Acceptance Criteria

```text
[ ] Eligibility has exactly one explicit establishment channel (§4)
[ ] Eligibility requires Lesson Completion at 10/10 (explicit, §4)
[ ] No prior Review / no mastery / no exercise-only eligibility required (§4)
[ ] ready == eligible AND nextReviewAt <= clock.now() (§16)
[ ] Initial interval D0 = 1 day (§6)
[ ] Max interval 21 days; min 1 day (§8)
[ ] success → min(i*2, 21); failure → max(i~/2, 1); IAK → max(i~/2, 1) (§8)
[ ] Success band = EvaluatedResult.stars >= 3 (== H2.8 completion threshold, §9)
[ ] NEP → no scheduler mutation (§9, §23)
[ ] Abandoned/Invalidated → no scheduler mutation (§13.5, §23)
[ ] Skip for Now → zero mutation, item stays ready (§12)
[ ] Start / Lesson → never a response (§15, §23)
[ ] I Already Know → no attempt, no evaluation, no evidence, schedule reduced
    one step, counts unchanged (§11)
[ ] one item → one response, committed once (§13)
[ ] retry discards prior candidates; only the committed candidate records (§13)
[ ] session = independent per-skill items; Start All iterates, never
    aggregates (§14/§15)
[ ] scheduler uses PracticeClock.now() only (§16/§19)
[ ] per-skill persistence keyed by skillId; missing record = not eligible (§17)
[ ] serialization follows application camelCase map convention (§17)
[ ] no migration (no previous scheduler persistence) (§17)
[ ] full determinism: identical state+clock+response ⇒ identical next state (§18)
[ ] reviewer-facing copy exposes no scheduler vocabulary (§16/§22)
[ ] decision table locked as §23
[ ] worked examples locked and deterministic (§21)
```

---

## 26. Version and Lock Statement

```text
Review Scheduler Contract v1.2
Status: LOCKED
Previous scheduler persistence: none — no migration path exists or is invented.
```

This document is the sole authority for review scheduling until a newer
version of the contract explicitly supersedes it. H2.9 must implement against
this contract without modifying it.