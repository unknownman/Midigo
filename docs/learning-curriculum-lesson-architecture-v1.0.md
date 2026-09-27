# Learning Curriculum & Lesson Architecture v1.0

## 1. Purpose

This document defines the **Learning Curriculum & Lesson Architecture** for
Midigo: how a skill is taught, practiced, applied, and later reviewed. It is an
architecture phase only and produces this single document.

It answers:

```text
WHAT   the learner needs to learn          →  Skill Graph
HOW    the learner is taught/practices     →  Learning Curriculum + Lesson
WHEN   the learner encounters it again     →  Spaced Review (future)
```

It does NOT implement production UI, lesson logic, scheduling, mastery, or
audio systems, and it does NOT modify any locked contract (see §17).

---

## 2. Product learning model

Midigo distinguishes three layers that must never be conflated:

```text
SKILL GRAPH            WHAT to learn         (atomic skills, frozen targets)
    ↓
LEARNING CURRICULUM    HOW it is taught      (Phase → Learning Unit → Lesson)
    ↓
SPACED REVIEW          WHEN to review        (Anki-like, future scheduler)
```

### 2.1 Skill Graph (WHAT)

A **Skill** is an atomic musical capability. The Skill Graph is the set of such
skills and their prerequisite/related edges. It is a **concept**, not a code
module; its structural realization is the pinned target-vocabulary catalog
(`TargetQuality / TargetRoot / TargetHand / TargetMode` and the deterministic
`targetId` in `expected_musical_target.dart` / `expected_musical_target_factory.dart`).

MVP first skill:

```text
chord.major.C.RH.block  →  `major-c-rh-block`   C4 E4 G4 = 60/64/67, RH, block
```

Supporting sky-level node reused by the C Major curriculum:

```text
chord.major.C.RH.arpeggio → `major-c-rh-arpeggio`  C4 E4 G4 C5 = 60/64/67/72, RH
```

Only these frozen forms can be evaluated. This constraint shapes everything in
§13-14 and is honored, never bypassed.

### 2.2 Learning Curriculum (HOW)

The Learning Curriculum is the authored, deterministic, per-phase ordering of
Learning Units and their Lessons. It is governed by the MVP Product Contract
(curriculum is the product-contract domain — not the factory's, not the UX
contract's). Structure:

```text
Phase → Learning Unit → Lesson → Teach + Practice
```

### 2.3 Spaced Review (WHEN)

The future scheduler-led layer (Review Scheduler, Mastery, Priority Aggregator,
Session Composer — boundary-locked). This phase does not design or remediate it.
The lesson simply leaves behind ordinary practice evidence (`practiceAttempt`)
that the future scheduler will consume.

---

## 3. Core terminology

Stable vocabulary. Reuses Learning UX §15 (`Phase`, `Lesson`, `Practice`,
`Review`, `Stars`, `Mastered`, `Needs Review`, `Continue`, `New`, `Keep
Practicing`) and Practice Runtime / Evaluation terminology where it already
exists (Attempt, Exercise Instance, Practice Item).

| Term | Definition |
| ---- | ---------- |
| **Phase** | Curated top-level group of the Learning Path (e.g. "Piano Foundations"). Communicates title, purpose, progress, available/locked lessons, review items (Learning UX §3). |
| **Learning Unit** | The authored, state-free curriculum unit: the skills it teaches, its Teach outline, and its Practice sequence. The unit is the *content* container; it carries no learner state. |
| **Lesson** | The stateful, learner-facing run of a Learning Unit: Teach stage → Practice stage → Result stage, with star accumulation and completion. In the MVP, one Learning Unit is delivered as exactly one Lesson. |
| **Skill** | An atomic capability in the Skill Graph, identified by its pinned target form (`targetId`). Answers "what to learn". |
| **Teach** | The **first-class first stage of every Lesson**: an ordered sequence of Teach Steps that introduce/explain the concept needed for the lesson before any evaluated practice. |
| **Teach Step** | One coherent conceptual chunk of Teach. Completion = the learner indicates readiness to continue. It is NOT an evaluation attempt and NOT mastery (§5 of the mission, §12 here). |
| **Exercise** | A learner-facing practice activity with one explicit pedagogical purpose, inside the Practice stage. Structured by the Exercise Model (§7). Executes one or more frozen target forms as Practice Items (RT-005). |
| **Pattern** | A musically meaningful ordering of target forms (e.g. block → broken), executed as a short gesture. |
| **Phrase** | A short musical statement built from learned material with a musical contour and ending (e.g. broken → broken → block = a cadence-like gesture). Has an explicit learning objective. |
| **Mini Piece** | A short standalone playable work used as a **learning vehicle** (reinforces the skill, hand position, fingering, and controlled movement). It is not decorative repertoire (Skill-Graph-first is preserved; this is not a song-first app). |
| **Attempt** | Unchanged (Practice Runtime RT-007): the runtime record of one learner performance against one Practice Item, evaluated by the Evaluation Contract. |
| **Retrieval** | An exercise kind: same frozen target, deliberately reduced guidance, unchanged evaluation. Not ear training. Feeds future review eligibility. |
| **Lesson Completion** | The learner finished the Lesson flow: Teach complete + Practice sequence fully performed + Result seen ($12). |
| **Curriculum Completion** | Acquisition (the frozen 10/10 star ceiling on the skill's target) AND the lesson's designed exercise sequence fully completed. For today's single-form lessons this reduces to the acquisition rule → no behavior change ($12). |
| **Mastery** | Governed by the existing **Midigo Mastery Contract** (future). Curriculum Completion ≠ Mastery. |
| **Review** | The spaced, scheduled return to a skill, Anki-like, owned by the future Review Scheduler. Review is NEVER inside the Lesson. |

---

## 4. Lesson architecture

```text
LESSON
│
├── TEACH
│   ├── Step 1          (general concept)
│   ├── Step 2
│   ├── ...
│   └── Step N          (practice readiness)
│
└── PRACTICE
    ├── Exercise 1      (guided)
    ├── Exercise 2      (repetition)
    ├── ...
    └── Exercise N      (retrieval)

After practice:  Result  →  Lesson Complete
                               ↓
                    Future Review Eligibility (scheduler-owned, future)
```

Rules:

```text
- Every Lesson starts with Teach (LOCKED architectural requirement).
- Teach always precedes the main Practice sequence.
- Practice is a rich, ordered exercise sequence — never "the exact thing that
  was just explained, repeated" (§11 of the mission).
- Review is never placed inside the Lesson.
```

### 4.1 Repository base that already exists

The repo already has the outer skeleton this architecture refines (`lesson_screen.dart`):

```text
enum _Stage { teach, practice, result }
LessonScreen → TeachView → PracticeView → ResultView
```

`TeachView` today is a **single static instructional view** (title, subtitle,
hand/mode chips, target notes, press instruction, fingering, keyboard, "Start
Practice"). This architecture extends Teach from a single view into an
**ordered step flow** (§5) without touching the frozen Evaluation, star, or
runtime contracts. `ResultView` already renders real stars and the derived
`New | In Progress | Completed` lesson state; that stays.

---

## 5. Teach architecture

Teach is a sequential, learner-advanced instructional wizard.

```text
Teach Step 1 → Step 2 → ... → Step N → Teach Complete → Practice
```

State (simple, per the mission's guidance to avoid complex state machinery):

```text
- orderedSteps:  the N instructions (authored, deterministic)
- currentIndex:  0-based index of the step being shown
- isStepComplete per step: only reached steps may be completed; future steps
  are NEVER presented as completed
- canGoPrevious: true when currentIndex > 0
- canAdvance:    true always (learner-authored advance) unless locked
- teachComplete: reached only when currentIndex == N - 1 and learner advances
```

Semantics:

```text
- The learner explicitly advances ("I've learned this / Continue").
- The learner may move backward where appropriate.
- Current step is always known and rendered ("Step 3 of 8").
- Advancing marks the current step complete for THIS session (transient,
  session-scoped state — not persisted, not mastery).
```

### 5.1 Teach Step completion is NOT mastery

```text
Teach Step Completion =  the learner indicates they went through this
                         instructional step and are ready to continue.

It does NOT mean:  skill mastered | skill evaluated | practice successful
                   mastery achieved | scheduler updated
```

---

## 6. Instructional content model

MVP is **TEXT-FIRST**, but the model is media-extensible so future audio,
image, animation, and interactive demonstrations are not architecture-blocked.

```text
InstructionalContent
├── Text        ← MVP (one coherent idea per chunk)
├── Audio       ← future
├── Image       ← future
├── Animation   ← future
└── InteractiveDemo (e.g., playback of the target) ← future
```

Rules:

```text
- The content union type is designed open (sum of kinds), so adding a media
  kind later is additive, not a rewrite of the model.
- No audio production system, no media pipeline is added in this phase.
- Each Teach Step follows the chunking discipline of §5: one concept, one
  explanation, one (future) demonstration, one learner action.
- No textbook chapters inside a single step.
```

Repository note: the repo today has **no audio/MIDI output path at all** (input
capture + MIDI event stream + evaluation only). Audio is therefore specified as
a principle and future requirement (§11), never claimed as existing.

---

## 7. Practice architecture

Practice is a separate learning layer that progressively transforms the taught
concept into usable motor and musical skill:

```text
Guided → Repetition → Variation → Contextual → Phrase → Application
         → Reduced Guidance → Retrieval
```

Not every Lesson uses every stage as a separate exercise; the C Major Lesson
uses most of them (§14).

### 7.1 The Exercise

Every exercise proposal must specify (Exercise Model):

```text
objective            one explicit pedagogical purpose
skill(s)             skills reinforced (pinned targetId)
prior knowledge      required prior knowledge (prior Teach steps / exercises)
musical context      the frozen target form(s) and gesture
guidance             scaffold level (§8)
learner action       what the learner physically does
feedback             auditory + visual (§7.2, §11)
completion condition when this step counts as done (§12)
```

Semantic rules (consistent with locked contracts):

```text
- ONE evaluation, ONE frozen target. An evaluated exercise plays exactly one
  frozen ExpectedMusicalTarget per Practice Item; a multi-form gesture is one
  Practice Interaction executing several Practice Items (RT-005), never a
  re-embedded "semi" target.
- Honest evaluation. Stars are the real frozen EvaluationResult stars; NEP
  yields no stars and never completes an exercise; a zero-star evaluated
  attempt is genuine evidence (EVG-013) but also never completes an exercise.
- Deterministic identity. Exercise ids are pinned content-derived ids, no
  random, no clock.
- Exercises are internal to the Lesson; not every Exercise Instance becomes a
  visible path node (Learning UX §4).
- Repetition is allowed and deliberate (blocked practice for acquisition),
  but the sequence as a whole must move beyond isolated repetition (§7.3).
```

### 7.2 Feedback model

Per exercise, both channels are defined and mandatory where applicable:

```text
Auditory:  Always-On MIDI Playback (§11) — learner hears their own input
           immediately; independent of evaluation.
Visual:    PianoKeyboardView (existing): target highlight (hand color),
           fingering numbers, note letters, arpeggio step badges, and a
           neutral pressed wash (never correctness-colored). ResultView shows
           real stars + lesson progress.
```

### 7.3 Progression quality

Practice must develop **transfer**: the newly acquired skill appears in
different meaningful musical contexts before the sequence is complete. Varied,
purposeful exercises replace arbitrary permutations. Research basis in §16.

---

## 8. Scaffolding model

Guidance progressively decreases across the Lesson. Dimensions (any may be
present or absent per exercise):

```text
- full keyboard highlight
- partial/note-name-only labels
- note names (letters / pitch names)
- fingering numbers
- reduced labels (target name only)
- retrieval (minimal guidance)
```

Authored scaffold levels (deterministic, not adaptive in MVP):

```text
S0  FULL    target highlight + note names + fingering + full instruction
S1  HIGH    target highlight + note names + fingering, less prose
S2  MEDIUM  target highlight + note names (no fingering)
S3  LOW     target highlight only
S4  RETRIEVAL  target name only ("Play C Major.")
```

Not every Lesson traverses all levels; the C Major Lesson fades S0 → S2/S3 →
S4. Contingent (performance-adaptive) fading is an explicitly deferred
algorithm decision (§19).

---

## 9. Musical application model

| Term | Definition | Differs from |
| ---- | ---------- | ------------ |
| **Pattern** | Fixed ordering of one or more learned target forms (block → broken; broken → block), executed as a gesture. Develops sequencing and movement. | Repetition: adds multiple related forms in order; musical shape, not one form restated. |
| **Phrase** | Short musical statement with a contour and an ending, built from learned material (e.g. broken → broken → block as a cadence-like gesture). First real melodic unit. | Pattern: longer, goal-directed, "says something" and resolves; has a beginning-middle-end. |
| **Mini Piece** | A short standalone playable work used as a learning vehicle with explicit objectives (reinforces skill, position, fingering, controlled movement). | Phrase: complete piece-like artifact, repeatable, "performance-ready" at beginner level. |

Mini Piece keeps Midigo **Skill-Graph-first**: the piece exists to exercise a
skill, never to make the product song-first.

> Honesty note: real diatonic melodies (C–D–E–G–E–D–C) and true mini pieces
> with melody notes require a future sequential target-form vocabulary —
> the frozen factory only builds `block`/`arpeggio` forms. The near-term C
> Major Lesson realizes the *same intent* (movement, contour, resolution)
> within the frozen forms; the melody-capable material is staged behind that
> future vocabulary (documented in §17, not a contract change).

---

## 10. Retrieval model

A **Retrieval** is an exercise kind, not a new engine:

```text
- same frozen target form as the practiced skill (e.g. major-c-rh-block)
- unchanged evaluation (real stars)
- guidance at S4 (target name only / "Play C Major.")
- normal practiceAttempt evidence (EVG-004 — no ACQUISITION/RETRIEVAL kinds)
- NOT ear training (Learning UX §5)
- always the LAST exercise of a Lesson's practice sequence
```

Retrieval is the boundary of the Lesson: it is the last learning act before
Lesson Completion and the natural evidence for future review eligibility (the
future Scheduler owns eligibility, never the Lesson).

---

## 11. MIDI audio learning principle

```text
During ELIGIBLE interactive practice, every learner-generated MIDI note
produces IMMEDIATE audible musical feedback.
```

Definitions:

```text
- "Eligible interactive practice" = the Practice stage (and future Teach
  demonstration steps that play the target); listener-only or passive steps
  are not eligible.
- "Immediate" = as the captured note-on is received by the event stream;
  latency is a presentation concern, NOT gated on any EvaluationResult.
- "Every note" = correct and incorrect notes both sound. Success is not the
  audio trigger, evaluation is not the audio trigger.
- Audible feedback is presentation-layer only: it never writes into an
  evaluation input, never changes an EvaluationResult, and never becomes a
  practice clock source (RT-012 discipline is preserved).
```

Model:

```text
MIDI Keyboard → MIDI Event → Capture
                                 ├──→ Visual Feedback (pressed wash, highlight)
                                 └──→ Instrument Playback → Learner hears
```

This is NOT an ear-training curriculum (no "identify this note/chord",
"sing this note", quiz). It is the learner hearing their own performance.

> Repo reality: no audio engine or MIDI-output path exists today. This is a
> **requirement for a future implementation step**, documented now so the
> UI/lesson phases do not forget it. The architecture stays honest.

---

## 12. Completion semantics

Seven distinct states, never interchangeable:

```text
TEACH STEP COMPLETION   learner readies past one instructional step.
                        Transient, session-scoped. Not mastered, not evaluated.

PRACTICE COMPLETION     one exercise met its condition:
                        - demonstration exercise: presented (no attempt/stars)
                        - evaluated exercise: an EVALUATED attempt with
                          stars >= 3 on that exercise's frozen form; NEP /
                          zero-star never completes (frozen NEP ≠ 0 rule)
                        Exercise "step done" is a per-step flag, NOT star
                        accumulation (stars stay one cumulative lesson signal,
                        frozen H2.9J policy).

LESSON COMPLETION       learner finished the flow: Teach complete + Practice
                        sequence fully performed + Result seen. Rendered from
                        the existing ProgressSignal (today: LessonProgress
                        derived "Completed" at 10/10 stars).

CURRICULUM COMPLETION   ACQUISITION (stars >= 10 → LessonProgress.isCompleted)
                        AND the lesson's designed exercise sequence complete.
                        For current single-form lessons the sequence is
                        degenerate, so Curriculum Completion == acquisition
                        == today's "Completed": ZERO behavior change.

MASTERY                 the future Midigo Mastery Contract governs. Never
                        derived from stars or this architecture (EVG-022).

REVIEW ELIGIBILITY      future Scheduler/Priority-Aggregator decision. Never
                        computed by the Lesson.

SCHEDULED REVIEW        the future Anki-like return pass. Never inside the
                        Lesson.
```

Forward note (documented, not applied): when the first Lesson becomes a
multi-exercise unit, presenting path "Completed" as Curriculum Completion
(sequence done + 10/10) is a presentation-semantics evolution of Learning UX §9
that will be raised at that implementation. Today §9 is exactly correct.

---

## 13. C Major Teach sequence (actual proposal)

Lesson: **C Major** (`chord.major.C.RH.block`). Ten steps, ordered
general → specific → concrete keyboard → physical → auditory → readiness.

| Step | Title | Purpose | Instructional content (text-first) | Learner action | Why it exists | Prerequisite it establishes |
| ---- | ----- | ------- | ----------------------------------- | -------------- | ------------- | --------------------------- |
| 1 | What is a chord? | Establish the foundational concept | "A chord is three or more notes heard together. It is one 'harmony sound'." | Read; Continue | The lesson is about a chord; the concept must exist before details. | General concept: chord |
| 2 | What is a Major chord? | Introduce the chord quality | "A Major chord is a bright, stable chord type, built from three specific notes." | Read; Continue | Distinguish quality from the abstract 'chord'. | Major chord exists as a type |
| 3 | How is a Major chord built? | Construction rule | "A Major chord uses the 1st, 3rd and 5th notes of its scale." | Read; Continue | Gives the *rule*, so the learner can build rather than memorize blindly. | Construction principle |
| 4 | What is C, the root? | Name the root note | "C is the bottom note of our chord. Names come from the bottom note (the root)." | Read; Continue | Locks note naming and the root concept. | Root concept |
| 5 | C Major = C, E, G | Instantiate the rule in C | "Starting on C, the 1st, 3rd and 5th notes are C, E and G." | Read; Continue | Concrete instance of the abstract rule. | The actual chord notes |
| 6 | Where are C, E and G on the keyboard? | Spatial representation | "C is the white key left of the two black keys; E and G are the next white keys to its right." | See the highlighted keys (PianoKeyboardView) | Translates symbols into the physical instrument. | Keyboard locations |
| 7 | Right-hand fingering | Physical production recipe | "Put thumb (1) on C, middle finger (3) on E, pinky (5) on G. Play all three together." | See fingering labels; place hand | Defines the exact physical gesture (FingeringCatalog 1-3-5). | Fingering + hand position |
| 8 | Hear C Major | Auditory representation | "C Major sounds bright and complete when all three notes ring together." (Audio playback is a future media step.) | Listen if audio present; else read | Adds the aural dimension so practice feedback is recognizable. | Expected sound |
| 9 | Your first goal | Practice expectation setting | "You will play C, E and G together, as a block, with your right hand." | Read; Continue | Explicitly bridges Teach to the first exercise (§10 mission). | Readiness for Practice |
| 10 | Ready to practice | Transition to Practice | "Tap Continue to move from Teach to Practice." | Continue → Practice | Explicit handoff from instructional layer to practice layer. | Teach complete |

Justification: steps 1-3 build the concept from general to specific (chord →
Major → construction rule); steps 4-6 instantiate (root → notes → keyboard
locations); step 7 adds the physical recipe; step 8 the aural target; steps
9-10 establish readiness and handoff. This follows the mandated arc and the
chunking discipline (one concept per step). No step evaluates the learner.

---

## 14. C Major practice sequence (actual proposal)

Primary target: `major-c-rh-block` (C4 E4 G4 = 60/64/67, RH, fingers 1-3-5).
Supporting frozen form: `major-c-rh-arpeggio` (C4 E4 G4 C5 = 60/64/67/72, RH,
fingers 1-2-3-5). All evaluated exercises use only these two forms. Stage
progression: Guided → Repetition → Reduced guidance → Pattern → Movement →
Phrase → Melody context → Application → Reduced guidance → Retrieval.

### Table (mission §28.14)

| # | Exercise | Objective | Context | Guidance | Learner action | Feedback | Transfer |
| - | -------- | --------- | ------- | -------- | -------------- | -------- | -------- |
| 1 | Fully Guided C Major | First correct production with full support | `major-c-rh-block` (single) | S0 full | Play C-E-G together | immediate audio + highlight + stars | Establishing the core gesture |
| 2 | Repeated C Major | Stabilize the motor pattern | `major-c-rh-block` ×3 (three Practice Items) | S0 | Play the block 3× | audio + highlight + stars | Motor chunking / fluency |
| 3 | Reduced Visual Guidance | Start independence | `major-c-rh-block` | S3 highlight only | Play block with keys highlighted, no labels/fingering | audio + highlight + stars | Removes scaffolds one at a time |
| 4 | Pattern: Solid → Broken | Chord as ordered notes | gesture block → broken | S2 names + highlight | Play C-E-G, then C-E-G-C | audio + step badges + stars | Same notes, new order = movement |
| 5 | Controlled Movement | Movement facility + octave extension | `major-c-rh-arpeggio` ×2 | S2 | Play the broken chord to the octave, twice | audio + step badges + stars | 1-2-3-5 association, finger independence |
| 6 | C Major Phrase | Phrase-shape unit | gesture broken → broken → block | S2 | Play a short "question-answer" gesture ending on the chord | audio + stars | Musical contour + resolution |
| 7 | Melody Context | Melodic movement over the chord | gesture arpeggio → arpeggio → block (melodic figuration) | S2 | Play the broken figure as a little melody line | audio + stars | First melodic gesture over harmony |
| 8 | Short Musical Application | "Piece-like" performance | gesture (block ×2) then (broken ×2 → block) | S1 | Perform a two-part mini unit | audio + stars | Performance-length unit; application |
| 9 | Reduced Guidance | Near-independent production | `major-c-rh-block` | S3 | Play block with highlight only | audio + stars | Fades all but spatial cue |
| 10 | Retrieval | Independent recall | `major-c-rh-block` | S4 "Play C Major." | Play from memory, no cues | audio + stars | Retrieval practice → future review |

### Per-exercise design details (mission §23)

Each exercise specifies every §23 field; the "why different" chain explains
how each moves beyond the frame established by its predecessor.

1. **Fully Guided C Major** — Skill: `major-c-rh-block`. Audio: immediate note
   sound (Always-On). Visual: full highlight + letters + fingering (S0).
   Evaluation: evaluated, block. Completion: evaluated attempt stars ≥ 3.
   Why different: first evaluated production (no prior frame — it establishes
   the core gesture). Transfer: core gesture established.

2. **Repeated C Major** — Skill: `major-c-rh-block`. Audio: immediate. Visual:
   full (S0). Evaluation: evaluated, 3 Practice Items. Completion: each item
   stars ≥ 3. Why different: single gesture → stabilized repetition (blocked
   practice). Transfer: fluency / motor chunking before any variation.

3. **Reduced Visual Guidance** — Skill: `major-c-rh-block`. Audio: immediate.
   Visual: highlight only (S3) — labels and fingering removed. Evaluation:
   evaluated. Completion: stars ≥ 3. Why different: first scaffold fade from
   the full frame. Transfer: forces recall of finger numbers and key positions.

4. **Pattern: Solid → Broken** — Skills: `major-c-rh-block` → `major-c-rh-arpeggio`.
   Audio: immediate. Visual: highlight + arpeggio step badges (S2). Evaluation:
   evaluated, 2-item gesture. Completion: both items ≥ 3. Why different: two
   forms in one gesture — the same notes appear as order/movement. Transfer:
   chord reorganizes into ordered notes.

5. **Controlled Movement** — Skill: `major-c-rh-arpeggio`. Audio: immediate.
   Visual: highlight + step badges (S2). Evaluation: evaluated, 2 items.
   Completion: both ≥ 3. Why different: isolates and drills the movement form
   (octave extension) itself. Transfer: 1-2-3-5 finger independence, larger span.

6. **C Major Phrase** — Skills: `arpeggio → arpeggio → block`. Audio: immediate.
   Visual: highlight (S2). Evaluation: evaluated, 3-item gesture. Completion:
   all ≥ 3. Why different: adds musical contour + resolution — a phrase, not a
   drill. Transfer: phrasing and goal-directed endings.

7. **Melody Context** — Skills: `arpeggio → arpeggio → block` as a melodic
   figuration. Audio: immediate. Visual: highlight (S2). Evaluation: evaluated,
   gesture. Completion: all ≥ 3. Why different: the broken figure becomes a
   *melody line* — the first melodic gesture over harmony. Transfer: chord
   tones as melodic material; the seed of future melody-target exercises
   (staged vocabulary).

8. **Short Musical Application** — Skills: `block ×2` then `broken ×2 → block`.
   Audio: immediate. Visual: highlight (S1). Evaluation: evaluated, two-part
   gesture. Completion: all ≥ 3. Why different: piece-like length and
   structure — an application, not a drill. Transfer: performance-length unit;
   the Mini-Piece seed (learning vehicle).

9. **Reduced Guidance** — Skill: `major-c-rh-block`. Audio: immediate. Visual:
   highlight only (S3). Evaluation: evaluated. Completion: stars ≥ 3. Why
   different: all textual scaffolds gone; only spatial cue remains. Transfer:
   near-independent production.

10. **Retrieval** — Skill: `major-c-rh-block`. Audio: immediate. Visual: none
    beyond the prompt (S4, "Play C Major."). Evaluation: evaluated. Completion:
    stars ≥ 3. Why different: no guidance at all — pure recall. Transfer:
    retrieval practice; natural input to future review eligibility. Curriculum
    Completion is acquisition (10/10 stars) AND this full sequence complete.

Star thresholds (≥ 3) are pedagogic calibration for the implementation phase,
not research claims; they honor the frozen star semantics (NEP never completes
an exercise). Adjusting thresholds is an implementation-step decision, not a
contract change.

---

## 15. Pedagogical rationale

1. **Blocked → broken.** Universal elementary-piano path (five-finger position /
   solid triad before broken triads and octave movement). Block first; broken
   as movement of the same notes (technique-literature cluster).
2. **Practice before variability.** Contextual-interference research shows high
   variability slows complex-motor acquisition; blocked repetition first, then
   patterns/phrases (exercises 4-6), then application (7-8), then fade (9-10).
3. **Chunked, one-concept Teach.** Chunking supports beginner acquisition
   (method-book analysis; group-piano studies); each Teach Step is one chunk,
   with explicit practice/feedback after.
4. **Guided → reduced → retrieval.** Scaffolding fades S0→S4; final step is
   retrieval so the skill survives without scaffolding — the pattern of
   contingent fading and retrieval practice.
5. **Make music from day one.** First practice exercise is a real chord; by
   exercise 6 there is a phrase and by 8 a piece-like unit. Structured piano
   learning, never a MIDI diagnostic tool (Learning UX §1).
6. **Transfer is explicit.** Technical exercises do not automatically transfer
   to musical contexts (technique-to-repertoire literature); the C Major
   sequence progressively recontextualizes the skill into patterns, phrases,
   and applications.
7. **One primary skill per Lesson.** C Major block is the one acquired skill;
   the arpeggio is supporting material. Keeps the frozen per-target star
   contract exact. No isolated success = mastery; a fixed exercise count is
   never presented as scientifically certified.

---

## 16. Research basis

Every claim is labeled; no source is overclaimed.

```text
[LOCKED]    Existing Midigo decisions (frozen contracts/code).
[RESEARCH]  External academic / professional literature.
[MUSESCORE] Observations of MuseScore's public educational material.
[DESIGN]    Architectural inference made in this phase.
```

| # | Claim used | Source | Label |
| - | ---------- | ------ | ----- |
| 1 | One lesson = one skill pinned to a frozen target; capacity-10 capped monotonic stars; NEP ≠ 0 stars; curriculum not implemented by the factory | MVP Product v1.1; star policy H2.9J; `expected_musical_target_factory.dart`; `slice1_catalog.dart`; `lesson_progress.dart` | LOCKED |
| 2 | Star = real EvaluationResult; evaluated attempt 0..5; NEP yields no evidence/no stars; only `practiceAttempt` kind | Evaluation v1.1; Evidence v1.1 (EVG-012/013/004) | LOCKED |
| 3 | Practice Interaction executes one or more Practice Items (RT-005); Item consumes Exercise Instance (RT-006); Attempt lifecycle RT-007/008 | Practice Runtime v1.1 | LOCKED |
| 4 | Lesson = coherent unit, internal Practice Items → Exercise Instances → Attempts; not every exercise becomes a visible lesson; star "Completed" at 10/10 | Learning UX v1.0 §4/§9 | LOCKED |
| 5 | One easy key (C Major) to start; pentascales → blocked & broken triads → scales/arpeggios → cadences; step/skip patterns first | Kjos "Step-by-Step: A Guide to Technique Development"; beginner piano method literature | RESEARCH |
| 6 | Chunking small, one-concept segments with practice after each improves acquisition for beginner piano; notes → chunks builds reading and recall | uOttawa 2023 analysis of beginner method books (progressive chunking); Pike & Carter (2010) group-piano sight-reading chunking drills | RESEARCH |
| 7 | Blocked practice first; variability/contextual-interference slows complex-motor acquisition (benefits show at retention/transfer) | Contextual-interference / variability-of-practice literature cluster | RESEARCH |
| 8 | Spacing: long-term spaced learning beats massing for music (melody/song memory), but short-lag spacing shows little benefit for piano motor tasks → spacing belongs to a future inter-session scheduler, not intra-lesson | York University spaced-melody/song studies (2021/2025); PLOS ONE 2017 piano spacing study | RESEARCH |
| 9 | Retrieval practice improves long-term retention and transfer; low-stakes retrieval, repeated (≥ 3-4 sessions), best spaced ≥ 24h → supports final retrieval exercise + future Anki-like layer | Retrieval-practice literature; Telesco et al. (piano melodies) | RESEARCH |
| 10 | Technical exercises do not automatically transfer to repertoire; each exercise needs a target, a magnified variable, and a transfer test; musical application must be explicit | Technique-to-repertoire transfer criticism (e.g., "Do Hanon/Czerny transfer?"); piano practice literature | RESEARCH |
| 11 | Scaffolding: contingent support, faded with readiness, transfer of responsibility; audible model + visual + immediate evaluation gave largest improvement for instrument learners | Scaffolding-in-music-education studies (one-to-one piano; digital scaffolds for string players) | RESEARCH |
| 12 | Beginner course flow: notes → tones/semitones → scales → melodies → chords (extracted from key) → progressions → comping → melody+harmony → final song project; ear-first, "make music from day one"; starts in C major/minor | MuseScore.com public courses ("Piano Concepts for Absolute Beginners"; "Chords and Chord Progressions 101") | MUSESCORE |
| 13 | Teach as ordered one-concept steps with explicit learner advance; general→specific→keyboard→fingering→auditory→readiness arc | Consistent with chunking, scaffolding, and pedagogy inputs; an integration decision for this product | DESIGN |
| 14 | Ten-exercise shape, S0→S4 fade, ≥3★ threshold, phrases/applications within frozen forms; Mini Piece = learning vehicle (skill-first) | Consistent with claims 5-12; an integration for Midigo's frozen vocabulary | DESIGN |

Claims 1-4 are repo truths. Claims 12 informs direction only — Midigo keeps
its own identity (no copying of MuseScore's or any product's curriculum/UI).

---

## 17. Contract compatibility

| Contract | Compatibility |
| -------- | ------------- |
| **Evaluation v1.1** (frozen engine; NEP ≠ 0 stars) | Exercises evaluate the exact frozen forms through the exact engine; no new targets, no new rules. |
| **Evidence v1.1** | Only `practiceAttempt` is emitted; retrieval/exercises are ordinary evaluated attempts (no ACQUISITION/RETRIEVAL kinds, EVG-004); NEP contributes nothing (EVG-012). |
| **Practice Runtime v1.1** | Exercises map to Practice Items (RT-005) consuming frozen Exercise Instances (RT-006); attempts use the locked lifecycle (RT-007/008); one Teach/exercise never alters runtime semantics. |
| **Learning UX v1.0** | Terminology reused (`Lesson` ≡ learner-facing unit); Teach becomes an ordered flow *inside* the existing teach stage (`_Stage.teach`); stars + `New/In Progress/Completed` rendering unchanged. Forward note re §9 in §12 (staged). |
| **MVP Product v1.1** | First skill unchanged (`chord.major.C.RH.block`); curriculum is authored content in the product-contract domain, not a factory/UX change. |
| **Mastery v1.2.1 (boundary)** | Curriculum Completion ≠ Mastery; no mastery vocabulary introduced (EVG-022; RT-015). |
| **Review Scheduler v1.2 / Priority Aggregator v1.3** | Untouched. Review never enters the Lesson; eligibility stays scheduler-owned. |
| **Session Composer v1.0 / Exercise Generator v1.0** | Untouched. Exercises are authored content the future Generator realizes; this phase defines content structure only. |
| **Architecture v1.1** | Document-layer only; no layers/models/runtimes changed. |

Staged forward notes (documented, not applied here):

```text
(a) Melody / mini-piece target forms (C-D-E-G-E-D-C, ...) need a future
    sequential target-form vocabulary beyond TargetMode.block|arpeggio.
    Staged behind that extension; the C Major Lesson stays fully within the
    frozen set.
(b) Multi-exercise-unit "Completed" presentation mapping (Learning UX §9) will
    be raised when such a unit is implemented (§12).
(c) Always-On MIDI Playback requires a future audio synthesis / MIDI-output
    path (no audio engine exists today) — documented as a requirement.
```

No locked contract file is modified by this phase. This document is the
curriculum-level refinement of the earlier `learning-curriculum-
architecture-v1.0.md`; both are consistent (same skill-first model, same
terminology, same completion semantics).

---

## 18. Implementation boundary (next phase)

The next implementation phase SHOULD implement:

```text
- Teach step flow: ordered steps, currentIndex, back/next, "Step X of N",
  text-first content, session-scoped step completion, Teach → Practice
- Practice exercise sequencing: multiple exercises (not just one), including
  multi-Practice-Item gestures within one Practice Interaction (RT-005)
- reduced-guidance presentation toggles (labels/fingering/highlight per S0-S4)
- retrieval exercise presentation (target name only)
- Result per the existing ResultView; Lesson Completion rendered from the
  existing ProgressSignal
- the Always-On MIDI Playback audio path (immediate note→sound), presentation-
  layer, never feeding evaluation
```

The next phase SHOULD NOT implement:

```text
scheduler / mastery behavior   ear-training exercises    song-first architecture
adaptive tempo                 BLE                        automatic reconnect
new MIDI protocol abstractions JSONL export changes       new evaluation rules
third-party music-learning SDKs                           sight-reading/notation
```

---

## 19. Open questions

Genuine, unresolved architectural questions only:

1. **Audio delivery path for Always-On MIDI Playback.** The repo has no audio
   layer. Two viable architectures exist (internal synthesized instrument vs.
   MIDI-out to the learner's device/DAW). The choice affects future media
   steps in Teach ("Hear C Major") and the Practice feedback path, and is a
   genuine decision for the implementation phase.
2. **Contingent vs. fixed scaffold fading.** Research supports contingency,
   but the MVP fades on a fixed authored schedule (S0→S4). Whether/when the
   fade becomes performance-adaptive is an algorithm decision deferred to the
   future exercise/adaptive layer.
3. **Mini Piece realization date.** The Mini Piece requires the future
   sequential target-form vocabulary (melody notes). Its exact form (melody-
   based vs. figuration-based) is resolved in the extension that adds it.

---

## 20. Architectural check

Verified checks before declaring this document ready:

```text
[ X ] Every Lesson starts with Teach
[ X ] Teach is an ordered sequence of instructional steps
[ X ] Teach is text-first in MVP
[ X ] Teach is extensible to future audio/media
[ X ] Teach Step completion is not mastery
[ X ] Practice is separate from Teach
[ X ] Practice contains multiple meaningful exercises
[ X ] Exercises provide contextual variation
[ X ] Musical application is explicit
[ X ] Retrieval is explicit
[ X ] Guidance can progressively decrease
[ X ] MIDI performance produces immediate audible feedback
[ X ] Playback is independent of evaluation
[ X ] Review is separate from Lesson
[ X ] Scheduler remains unchanged
[ X ] Mastery remains unchanged
[ X ] Evaluation remains unchanged
[ X ] Skill Graph remains skill-first
[ X ] Curriculum does not become song-first
[ X ] C Major has a concrete Teach sequence
[ X ] C Major has a concrete Practice sequence
[ X ] No fixed exercise count is falsely presented as scientifically sufficient
```

---

## Lock status

```text
LOCKED:    NO (specification document, not a frozen contract)
Status:    CURRICULUM ARCHITECTURE STATUS: READY FOR IMPLEMENTATION
Files:     docs/learning-curriculum-lesson-architecture-v1.0.md (only)
Produces:  the specification for the next Teach/Practice implementation slice;
           no code, no UI, no audio, no contract modification.
```