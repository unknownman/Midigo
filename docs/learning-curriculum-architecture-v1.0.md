# Learning Curriculum Architecture v1.0 (H2.6)

## 1. Purpose

This document defines the first **learning curriculum architecture** for Midigo
(the MIDI Tutor): the model, terminology, exercise design, guidance/scaffolding,
retrieval, completion semantics, and a concrete **near-term C Major curriculum**
(≈10 exercises) for the MVP's first skill (`chord.major.C.RH.block`).

It is an **architecture phase only**. It delivers this single document. It does
NOT:

```text
- implement production code, UI, lessons, or a curriculum engine
- create a new runtime, scheduler, mastery model, or evidence pipeline
- modify any locked contract or frozen source file
- redesign the existing Review Scheduler
```

It exists so that the future exercise-generation and curriculum implementation
steps have an authoritative, self-consistent specification to build against.

```text
CURRICULUM ARCHITECTURE STATUS: READY FOR IMPLEMENTATION
Blockers: none. Two forward-compatibility notes are staged (see §14), neither
blocks the near-term curriculum.
```

---

## 2. Product learning model

The product organizes learning in three layers, top to bottom.

```text
SKILL GRAPH                       (concept: WHAT exists to learn)
        │  atomic skills pinning frozen target forms (targetId vocabulary)
        ▼
LEARNING CURRICULUM               (substance: HOW the learner learns it)
        │  authored phases → lessons → exercises; consumed via Practice Runtime
        ▼
SPACED REVIEW                     (future: WHEN to return to it)
        │  Review Scheduler / Mastery / Priority Aggregator / Session Composer
```

### 2.1 Skill Graph (concept, not a module)

The Skill Graph is the set of learnable musical skills and their
prerequisite/related edges. It is intentionally a **concept**, not a code module.
Its structural realization today is the **pinned target-vocabulary catalog**: the
frozen `TargetQuality / TargetRoot / TargetHand / TargetMode` enums and the
deterministic `targetId` derived from them (`expected_musical_target.dart`,
`expected_musical_target_factory.dart`).

Each *node* (skill) is a capability whose evaluable essence is exactly one
frozen `ExpectedMusicalTarget` form. The MVP product's first skill:

```text
chord.major.C.RH.block  →  targetId `major-c-rh-block`
                           C4 E4 G4   = MIDI 60/64/67
                           right hand, block, fingers 1-3-5
```

A supporting node that the C Major curriculum legitimately reuses (already
frozen and already a pinned lesson target):

```text
chord.major.C.RH.arpeggio  →  targetId `major-c-rh-arpeggio`
                               C4 E4 G4 C5   = MIDI 60/64/67/72
                               right hand, arpeggio, fingers 1-2-3-5
```

Edges express "this skill supports / is a prerequisite of that skill". In the MVP
the edges are the ordered Learning Path catalog
(`learning_catalog.dart`: RH block → RH arpeggio → LH block → LH arpeggio →
both-unison block → both-unison arpeggio). This phase adds no new skill nodes; it
only exercises the existing first two nodes plus the already-canonical right-hand
fingering forms.

### 2.2 Learning Curriculum

The Learning Curriculum is the **authored, deterministic, per-phase** ordering of
lessons and their internal exercise sequences, which produces practice through
the Practice Runtime. It is governed by the MVP Product Contract (curriculum is
the product contract's domain, not the UX contract's, not the target factory's).
The `ExpectedMusicalTargetFactory` "does not implement the curriculum"; the
`Slice1Catalog` is a fixed boundary catalog, not a full Exercise Generator.

### 2.3 Spaced Review

Spaced Review is the future scheduler-led layer (Review Scheduler, Mastery,
Priority Aggregator, Session Composer — all boundary-locked in the contract
consolidation audit; no separate files). This phase does **not** design or
remediate it. The only interaction the curriculum has with review is that lesson
completion feeds acquirable-practice history (stars), which the future scheduler
will read — exactly as the locked contracts already promise.

---

## 3. Terminology

Stable, learner-facing and internal vocabulary. Uses the Learning UX Contract
§15 vocabulary (`Phase`, `Lesson`, `Practice`, `Review`, `Stars`, `Mastered`,
`Needs Review`, `Continue`, `New`, `Keep Practicing`).

| Term | Definition |
| ---- | ---------- |
| **Phase** | Curated top-level group of the Learning Path (e.g. "Piano Foundations"). A phase communicates title, purpose, progress, available/locked lessons, review items (Learning UX §3). |
| **Learning Unit (Lesson)** | Existing Learning UX `Lesson` (§4): a *coherent learning unit teaching one primary skill through a designed sequence of exercises* (internal: Lesson → Practice Items → Exercise Instances → Attempts; learner-facing: Lesson → Practice → Result). No new redundant concept is introduced. |
| **Skill** | An atomic musical capability in the Skill Graph, identified by its pinned target form (`targetId`). Answers "what to learn". MVP first: `chord.major.C.RH.block`. |
| **Exercise** | A designed learner-facing activity with **one explicit objective** inside a lesson. It presents a target context, a guidance level, and a completion condition. An exercise executes one or more frozen target forms through one or more Practice Items (RT-005). Structured by the Exercise Model (§4). |
| **Pattern** | A musically meaningful ordering of one or more target forms within an exercise (e.g. block→broken→block), executed as a single Practice Interaction via multiple Practice Items. |
| **Phrase** | A short musical statement whose material is expressible with current frozen target forms (e.g. a rising broken chord ending on a block). Broader melodies (C-D-E-G-E-D-C) require a future target-form vocabulary extension (§6). |
| **Mini Piece** | A short beginner piece with explicit learning objectives tied to the unit's skills. Requires the future vocabulary extension (or is presented as non-evaluated demonstration) in the MVP target set. |
| **Attempt** | Unchanged (Practice Runtime RT-007): the runtime record of one learner performance against one Practice Item; evaluated by the Evaluation Contract. Never an EvaluationResult, evidence, Exercise Instance, or Practice Interaction. |
| **Retrieval** | An **exercise kind** that re-presents an already-acquired skill with minimal guidance, same frozen target, unchanged evaluation. Not ear training. |
| **Curriculum Completion** | The lesson's designed exercise sequence has been fully performed to its per-exercise completion conditions **and** the primary skill has reached the frozen acquisition ceiling (10/10 stars). For today's single-form lessons this reduces to the acquisition rule → no behavior change (§10). |
| **Mastery** | The (future, deferred) Midigo mastery model. Curriculum Completion ≠ Mastery. No mastery vocabulary is introduced by evidence or stars (EVG-022, RT-015). |
| **Review Eligibility / Scheduled Review** | Owned by the future Review Scheduler. Curriculum Completion ≠ review eligibility ≠ scheduled review. Reproduced here only to keep the distinctions explicit (§9 of Lesson Progress; RT-015). |

---

## 4. Exercise Model

An **Exercise** is the core unit of curriculum substance. Schema:

```text
exercise {
  id            deterministic, e.g. `ex-c-major-01-see-and-hear`
  lesson        owning Learning Unit (primary skill targetId)
  objective     one explicit learner-facing sentence ("why this step")
  context       the musical material: one or more frozen target forms
                in an ordered "gesture" (single Exercise Instance ≡ single
                form; a gesture = one Practice Interaction executing multiple
                Practice Items over those Forms, RT-005)
  guidance      guidance level G1..G5 (§8)
  evaluation    NONE (demonstration) | EVALUATED (frozen target form, real stars)
  completion    when this step counts as done (§10, §11)
  expected_skill  the shaped capability ("see the C E G shape", "play C-E-G
                together", "extend to the octave")
}
```

Semantic rules (all consistent with locked contracts):

```text
- ONE evaluation, ONE frozen target. An evaluated exercise plays exactly one
  frozen ExpectedMusicalTarget form; multiple forms in one exercise appear only
  as sequential Practice Items in one gesture, never as a re-embedded "semi"
  target. (ExpectedMusicalTarget is the only evaluable unit.)
- Honest evaluation. Stars are the real frozen EvaluationResult stars (§8 UX);
  NEP yields no stars and never completes the step; a zero-star evaluated
  attempt is genuine evidence (EVG-013) and never completes the step.
- Deterministic identity. Exercise ids are pinned and stable, derived from
  content; no random, no clock, no counters. (Same discipline as every locked
  id.)
- Exercises are internal to the lesson. Not every Exercise Instance becomes a
  visible lesson (Learning UX §4); the lesson screen renders the sequence.
- Repetition is allowed within vocabulary. An exercise may repeat the block
  form N times (the same frozen target form, N Practice Items) — the classic
  blocked-practice acquisition shape, and fully within RT-005.
```

---

## 5. Exercise progression

A lesson moves through stages, in this order, and **applies a stage only when it
is appropriate** (never rotely):

| Stage | Purpose | When applicable | Example exercise kinds |
| ----- | ------- | --------------- | ---------------------- |
| **Introduce** | First encounter: hear + see the skill, no production required | Always the first step of a unit | See & Hear demonstration |
| **Guided** | First production with strong support | When a learner has no prior evidence of the form | "Try it" guided play |
| **Practice** | Isolated repetition to stabilize the motor shape | When a form has been produced at least once successfully | Repeat the block 3× |
| **Context** | Place the form in a musical/movement context to build transfer | After isolated acquisition of a form | Block→broken pattern; octave extension |
| **Application** | Use the forms in a short musical gesture | When context exercises complete | Broken-chord phrase ending on the chord |
| **Retrieval** | Re-produce the skill with minimal guidance; the LAST exercise of the unit | When acquisition is reached; always final | "Play C Major" (minimal guidance) |

Rationale (evidence basis in §13): Introduce→Guided→Practice is the
five-finger → blocked/broken acquisition path common to elementary piano
technique books; **Practice before Context** avoids asking beginners to produce
complex motor skills under variability before the shape is stable (high
contextual interference slows acquisition for complex motor tasks); **Retrieval
last** consolidates the unit and directly feeds review eligibility later.

---

## 6. Musical application model

The product teaches musicianship, not isolated test patterns. Every unit
therefore contains at least one "musical" exercise: the forms arranged as a
real listening/playing gesture (see & hear, patterns, a phrase), not merely
statistics.

```text
NEAR-TERM (this curriculum, frozen vocabulary only):
  musical material = combinations of the existing frozen RH target forms
    - solid chord gesture:  block (C E G together)
    - movement gesture:     arpeggio (C E G C, crossing the octave)
    - mixed gesture:        block → broken, or broken → block → broken,
                            as a short Practice-Interaction sequence

STAGED (future, documented, NOT a contract change):
  true Melodies:  C-D-E-G-E-D-C, A-G-F, ... — require an ordered-note /
                  sequential-onset target-form vocabulary beyond
                  TargetMode.block|arpeggio. The evaluation pipeline consumes
                  only ExpectedMusicalTarget; arbitrary melodic sequences are
                  not expressible through the frozen factory today.
  Mini Pieces:    short melodies + accompaniment — same vocabulary dependency.
  Future material may ALSO be offered as non-evaluated demonstration (playing
  a phrase for the learner to hear with no attempt/evaluation), which is
  explicitly compatible with the frozen pipeline ("evaluation when
  appropriate" is honored; a demo never fakes a lesson result).
```

The C Major curriculum realizes the intent of the classic
"block → broken chord → phrase → mini piece" model within the frozen vocabulary,
and the architecture hosts the future melody/minist-piece step.

---

## 7. Always-On MIDI Playback Principle

```text
Whenever a musical target is presented (see-&-hear, teach, guidance, exercise
context, result), the app PLAYS ALOUD, by default, what the learner should hear.
Playback requires no learner input and is independent of evaluation.
```

Rules:

```text
1. Default on. Presentation is aural-first: the learner hears the target before
   and during practice (teach state supports playback; Practice state supports
   playback; UX §5/§6 list playback as an explicit aid).
2. Presentation-layer only. MIDI playback is infrastructure/presentation; it
   must never write a note into an evaluation input and never change an
   evaluation result (honesty rule: played feedback ≠ learner performance).
3. Never fabricate. Playback is clearly the EXPECTED audio, distinct from
   any played-note feedback channel; it never masquerades as the learner's
   performance.
4. Timeline safe. Target audio is generated on demand and is unrelated to the
   Practice Interaction timestamps (RT-012): it never becomes a source of
   practice time or evidence-anchored time.
5. Repo reality. Today the repository has MIDI input (CoreMIDI/USB) and NO
   audio-synthesis engine. This principle is therefore a REQUIREMENT for a
   future implementation step, not a current capability and not a contract
   change. The near-term curriculum documents it now so the exercise/UI phases
   do not forget it.
```

Research note: studies of digital scaffolding for instrument learners found the
combination of model (playback) + visual support + immediate evaluation produced
the largest performance improvement; audible models are a recognized first-class
scaffold, not a garnish (§13).

---

## 8. Guidance / scaffolding model

Guidance is expressed on four channels, plus instruction granularity. They
correspond to the presentation aids the UX contract already lists (teach/practice:
visual keyboard, highlighted target notes, fingering/hand guidance, playback, clear
target — UX §5/§6).

```text
GUIDANCE CHANNELS
  A. identity   — show/say the name and shape: "C Major", root C, RH, block
  B. spatial    — keyboard highlight of the expected notes
  C. procedural — finger numbers / hand position (FingeringCatalog 1-3-5 etc.)
  D. audio      — always-on playback (§7, present at every level)
  E. prompt     — instruction granularity: "play all three notes together"
                  down to "play C Major"
```

Guidance ladder (fades across the lesson):

```text
G1  FULL     A+B+C+E explicit     (see-&-hear, first guided play)
G2  HIGH     A+B+C, E less spoken (isolated repetition)
G3  MEDIUM   B+C, A minimal       (patterns)
G4  REDUCED  B only + E           (reduced-guidance practice)
G5  MINIMAL  none of A/B/C        ("Play C Major" — retrieval)
```

Contingency: research describes scaffolding as *contingent* — support is faded
according to learner readiness, not a fixed script. The near-term exercises use a
**fixed, authored fade** (every learner follows G1→G5), and the *contingent /
performance-adaptive* fade is explicitly deferred to the future exercise/adaptive
layer as an algorithm decision (§15). Fixed fade is deterministic and honest and
is the conservative first realization.

---

## 9. Retrieval model

A **Retrieval** is an exercise kind, not a new engine:

```text
- same frozen target form as the practiced skill (e.g. major-c-rh-block)
- unchanged evaluation (real EvaluationResult stars; NEP honest)
- presentation at G5 (minimal guidance): the learner must reproduce from memory
- produces a normal practiceAttempt evidence stream (EVG-004: no
  ACQUISITION/RETRIEVAL kinds are invented)
- NOT ear training (Learning UX §5: this is not an ear-training system;
  retrieval is memory re-production of a known target, not audio recognition)
- the LAST exercise of a curriculum unit is always a retrieval
```

Retrieval is what makes a completed lesson persistable: the final retrieval is
the evidence that the learner can independently re-produce the skill, and is the
natural input for the future scheduler's review eligibility. It does not itself
decide review eligibility (that stays the Scheduler's domain).

---

## 10. Completion semantics

Five distinct things must never be conflated:

```text
ACQUISITION          the frozen lesson-star rule: stars >= 10 on the primary
                     skill target (LessonProgress.isCompleted; capacity 10,
                     cumulative, capped, monotonic, no decay) → "Completed"
                     lesson-progress state.

CURRICULUM COMPLETION  this architecture: the lesson's designed exercise
                     sequence has been fully performed (each exercise met its
                     completion condition) AND acquisition is reached.

MASTERY              the future mastery model (deferred). Not evidenced by
                     stars or curriculum progress (EVG-022).

REVIEW ELIGIBILITY   future Scheduler-owned: whether a skill is due for review.
                     Not computed here.

SCHEDULED REVIEW     the future Anki-like return pass. Not designed here.
```

Per-exercise completion conditions (this phase):

```text
- Demonstration exercise: completes after the demonstration is presented
  (listen/observe); produces no attempt and no stars.
- Evaluated exercise: completes on an EVALUATED attempt with stars >= 3 on
  that exercise's frozen form. NEP and zero-star evaluations therefore never
  complete a step (they never add stars — frozen) — the learner simply tries
  again. Exercise thresholds do NOT partition, subtract, or re-map lesson
  stars: stars remain one cumulative lesson signal per frozen H2.9J policy;
  the exercise completion is a separate "step done" flag the future exercise
  layer persists.
- Sequence/pattern exercise: every Practice Item in the gesture must satisfy
  the >= 3-star rule before the step completes.
```

Mapping to the existing product:

```text
- TODAY: every lesson is single-form (one lesson == one pinned target == one
  exercise). The exercise sequence is degenerate: curriculum completion
  reduces to acquisition (10/10 stars). ZERO behavior change; LessonProgress
  still derives New / In Progress / Completed exactly as today.
- FUTURE multi-exercise units (a lesson teaching one primary skill through a
  sequence): the lesson's "completed" presentation maps to curriculum
  completion while stars remain the frozen progress datum. This is a
  presentation-semantics evolution of Learning UX §9, explicitly staged in
  §14; it is NOT a change to stars acquisition policy or any frozen file.
```

---

## 11. C Major curriculum (near-term, ≈10 exercises)

Primary skill: `chord.major.C.RH.block` (C4 E4 G4 = 60/64/67, RH, 1-3-5).
Supporting frozen form: `chord.major.C.RH.arpeggio` (C4 E4 G4 C5 =
60/64/67/72, RH, 1-2-3-5). All evaluated exercises use only these two forms.
The unit is realized as the internal exercise sequence of the first Learning
Path lesson (`lesson-major-c-rh-block`); the later arpeggio lesson stays a
distinct path node.

| # | Exercise | Objective | Context | Guidance | Expected Skill |
| - | -------- | --------- | ------- | -------- | -------------- |
| 1 | See & Hear C Major | Hear and see the chord before playing | `major-c-rh-block` demo (auto playback, highlight, name, fingers) | G1; demo, no attempt | Recognize the sound and the C-E-G shape |
| 2 | Guided Play: C-E-G | First correct production with full support | `major-c-rh-block` (single block) | G1 | Play the block together with support |
| 3 | Isolated Repetition | Stabilize the hand shape | `major-c-rh-block` ×3 (three Practice Items) | G2 | Play the block 3× accurately |
| 4 | Broken Chord Intro | Discover chord notes in sequence | `major-c-rh-arpeggio` (C-E-G-C, octave) | G2 | Play the broken chord; learn 1-2-3-5 |
| 5 | Pattern: Solid-Broken | Musical movement between two forms | gesture `block → broken` (one interaction) | G3 | Move solid↔broken in one gesture |
| 6 | Pattern Variation | Strengthen the octave-extension movement | gesture `broken → block` | G3 | Re-produce both forms in sequence |
| 7 | Reduced Guidance: Block | Practice with spatial help only | `major-c-rh-block` | G4 | Play block from memory of position |
| 8 | Reduced Guidance: Movement | Practice the octave run with spatial help only | `major-c-rh-arpeggio` | G4 | Play broken chord with minimal prompts |
| 9 | Application: Chords to Phrase | Perform a short chord-based musical gesture | gesture `broken → broken → block` (a cadence-like ending) | G3-G4 | Play a short musical phrase |
| 10 | Retrieval: Play C Major | Independent reproduction, no support text | `major-c-rh-block` (minimal prompt) | G5 | Reproduce C Major independently |

Notes on the table:

```text
- Exercises 3-8 each require an EVALUATED attempt >= 3 stars on the stated
  frozen form (NEP/zero-star retry) — §10.
- Exercise 9 is the unit's "application": musical gesture within vocabulary; a
  non-evaluated §6 demonstration is optional at #1 only.
- Curriculum Completion = exercises 1-10 all satisfied AND stars on
  major-c-rh-block become 10/10 (§10). Since 10-star acquisition can be reached
  before exercise 10, acquisition saturates the signal while the sequence still
  requires completion, and "Completed" on the path will show curriculum
  completion for this unit in the future (§10 mapping) — today's single-form
  behavior is unchanged.
- Star thresholds (>= 3) are pedagogic calibration for the implementation
  phase, not research claims; they honor the frozen star semantics (NEP never
  completes). Adjusting them is an implementation-step decision, not a contract
  change.
```

---

## 12. Pedagogical rationale

The curriculum is intentionally conservative and sequence-shaped:

1. **Blocked → broken.** The universal elementary-piano acquisition path:
   five-finger position / solid triad before broken triads and octave movement
   (technique-method literature). The block comes first; the broken chord is
   introduced only as a movement of the same notes.
2. **Practice before variability.** Contextual-interference research shows high
   variability slows acquisition of complex motor skills; blocked practice
   stabilizes first, and variability/the musical gestures come later (exercises
   4-9). Variety never precedes a stable first production.
3. **Guided → reduced → retrieval.** Scaffolding is faded across the unit
   (G1→G5); the final step is retrieval so the skill survives without the
   scaffold — the pattern of contingent fading and retrieval practice.
4. **Make music from day one.** The very first exercise is a see-&-hear
   musical moment; by exercise 9 the learner plays a short phrase. The product
   remains a structured piano-learning app, never a MIDI diagnostic tool
   (Learning UX §1).
5. **One primary skill per lesson.** The unit teaches C Major block as its
   one acquired skill; the broken form is supporting material. This keeps the
   lesson-star contract (per target) exact and prevents conflation.
6. **Honesty.** No fabricated results, no fake playback, NEP stays honest,
   demonstration exercises are clearly demonstration. Star = real evaluation.

---

## 13. Research basis

Every claim is labeled so no authority is overstated. Four classes:

```text
[LOCKED]   Existing Midigo decisions (frozen contracts/code) — authoritative
           for this repo, not "external" evidence.
[RESEARCH] External academic literature — generalizable, but not repo rules.
[MUSESCORE] Observations of MuseScore's public educational/course material —
           commercial sequencing observations only, not a standard to copy.
[DESIGN]   Inferred design decision made in THIS phase.
```

| # | Claim used above | Source | Label |
| - | ---------------- | ------ | ----- |
| 1 | One lesson = one primary skill pinned to a frozen expected target (`major-c-rh-block`), capacity-10 capped monotonic stars, NEP ≠ 0-stars, curriculum not implemented by the factory | MVP Product v1.1; H2.9J star policy; `expected_musical_target_factory.dart`; `slice1_catalog.dart`; `lesson_progress.dart` | LOCKED |
| 2 | Star = real EvaluationResult; evaluated attempt 0..5; NEP yields no evidence/no stars; evidence kind is only `practiceAttempt` | Evaluation v1.1; Evidence v1.1 (EVG-012/013/004) | LOCKED |
| 3 | Practice Interaction executes one or more Practice Items (RT-005); Practice Item consumes an Exercise Instance (RT-006); Attempt lifecycle RT-007/008 | Practice Runtime v1.1 | LOCKED |
| 4 | Lesson = coherent unit, internal Practice Items → Exercise Instances → Attempts; not every exercise becomes a visible lesson; teach/practice support playback & aids | Learning UX v1.0 §4-6 | LOCKED |
| 5 | Practice should not restructure the review scheduler; Review/retrieval display never fabricates | Learning UX §10; consolidation audit (Scheduler boundary) | LOCKED |
| 6 | Blocked acquisition before variability; contextual interference slows complex-motor learning, benefits appear at retention/transfer; simplest transfer for short sequences | Contextual-interference / variability-of-practice literature (e.g. PLOS ONE 2018, Frontiers in Psychology 2014, Psychological Research 2021 lines) | RESEARCH |
| 7 | Short-lag spacing shows limited benefit for piano motor skills; long-term scheduling (not intra-lesson) is where retrieval spacing pays | PLOS ONE 2017 "Lack of spacing effects during piano learning" | RESEARCH |
| 8 | Scaffolding: contingent support, faded with readiness, transfer of responsibility; audible model + visual + immediate evaluation gave largest improvement for instrument learners | Scaffolding-in-music-education studies (one-to-one piano; string-instrument digital scaffolds) | RESEARCH |
| 9 | Retrieval practice consolidates and improves retention; retrieval after instruction is a desirable difficulty | Retrieval-practice / learning-science body (Roediger & Karpicke line; music-classroom retrieval practice articles) | RESEARCH |
| 10 | Beginner piano method sequencing: five-finger position → blocked & broken triads → scales/arpeggios → chords/progressions → simple repertoire | Elementary piano technique/pedagogy publications | RESEARCH |
| 11 | Beginner course sequencing: notes → scales → melodies → chords → progressions → application/style → final musical project; ear-first | MuseScore.com public education courses (beginner piano course; chords & progressions course) | MUSESCORE |
| 12 | C Major is the correct first unit; fixed fade G1→G5; 3★ per-step threshold; blocked-3× repetition; broken→block phrase ending; 10-exercise shape | Consistent with the method/learning-science constraints above | DESIGN |

Claims 1-5 are non-negotiable (repo truths). 6-11 inform and corroborate the
[DESIGN] decisions; the curriculum never claims an external source overrides a
locked rule.

---

## 14. Compatibility with existing contracts

Every locked contract is left **untouched and honored**:

| Contract | Compatibility |
| -------- | ------------- |
| **Evaluation v1.1** (frozen engine; NEP ≠ 0 stars) | Exercises evaluate the exact frozen forms through the exact engine; no new targets built; star semantics unchanged. |
| **Evidence v1.1** | Only `practiceAttempt` evidence kind is touched; retrieval exercises are ordinary evaluated attempts (no ACQUISITION/RETRIEVAL kinds, EVG-004); NEP contributes nothing (EVG-012). |
| **Practice Runtime v1.1** | Exercises map to Practice Items (RT-005) consuming frozen Exercise Instances (RT-006); attempts use the locked lifecycle (RT-007/008); gestures are one interaction, several items. |
| **Learning UX v1.0** | Vocabulary reused (`Lesson` ≡ Learning Unit; `Exercise` is internal, §4). See staged note (a) below. |
| **MVP Product v1.1** | First skill unchanged (`chord.major.C.RH.block`); curriculum is authored content in the product-contract domain, not a factory or UX change. |
| **Evaluation / Evidence decisions** | Honest stars; demo exercises are non-evaluated (no fake lesson result); exercise thresholds never touch the star accumulation policy. |
| **Mastery (boundary) / Review Scheduler (boundary) / Priority Aggregator / Session Composer / Exercise Generator (boundary)** | No scheduler, mastery, interval, or priority behavior is introduced; curriculum structure is named as authored content the future Exercise Generator will realize — no boundary violated. |
| **Architecture v1.1** | Document-layer only; no layers, models, or runtimes changed. |

Staged forward-compatibility notes (documented here, **not** applied now):

```text
(a) Learning UX §9 "Completed" mapping: once the first lesson becomes a
    multi-exercise unit, presenting path "Completed" as curriculum completion
    (sequence done + 10/10) is a presentation-semantics evolution of §9 that
    will be raised when that unit is implemented. Today, all lessons are
    single-form, so §9 is exactly correct and untouched.
(b) Melody / mini-piece target forms (C-D-E-G-E-D-C, ...): these need an
    ordered-sequential target-form vocabulary beyond TargetMode.block|arpeggio
    (a future ExpectedMusicalTarget / factory extension). Staged behind that
    extension; the near-term curriculum stays fully within the frozen set.
```

Neither (a) nor (b) blocks the C Major curriculum; both are explicit revision
points for future phases. No frozen contract file is modified by this phase.

---

## 15. Open questions

Genuinely unresolvable at this phase (kept intentionally short):

1. **Contingent vs fixed fading.** Whether guidance should fade dynamically
   per-learner (performance-based) or stay authored-fixed. This is an algorithm
   decision for the future exercise/adaptive layer; the curriculum specifies the
   fixed ladder today. No locked evidence defines it.
2. **Melody vocabulary timing.** When and under what semantic rules the target
   vocabulary extends to sequential melodic forms (world of C-D-E-G-E-D-C and
   mini pieces). Out of scope until that contract is opened; the model hosts it.
3. **Lesson-progress of multi-exercise units.** The precise persisted
   representation of per-exercise "step done" state for future multi-exercise
   units (distinct from stars). This belongs to the future Exercise/mastery
   implementation, deferred; not needed for the near-term degenerate case.

---

## Lock status

```text
LOCKED:    NO (this is a specification document, not a frozen contract)
Status:    READY FOR IMPLEMENTATION (CURRICULUM ARCHITECTURE STATUS)
Files:     docs/learning-curriculum-architecture-v1.0.md (only)
Produces:  the specification for the future Exercise Generator / curriculum
           implementation slices; no code, no UI, no contract modification.
```