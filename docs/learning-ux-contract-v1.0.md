# Learning UX Contract v1.0 (H2.11)

Learner-facing UX/DX principles and information hierarchy. This contract
specifies WHAT the learner must always be able to understand, in what order
information is presented, and the stable learner-facing terminology. It does
NOT specify colors, exact spacing, widget trees, frameworks, or pixel layouts.

## 1. Product learning philosophy

Expose the learning journey, not the machinery. The app is a structured
piano-learning application with MIDI as the primary interaction mechanism -
never a MIDI diagnostic tool and never a collection of isolated exercises.
The learner always knows:

```text
Where am I?
What am I learning?
What should I practice now?
What have I already completed?
How well did I perform?
What needs review?
What should I do next?
```

## 2. Learning Path

A Learning Path is a Coursed/phase-structured progression (e.g. Piano
Foundations → Major Chords → C Major ...). Each node renders exactly one of:

```text
locked | available (new) | in progress | completed | mastered | needs review
```

The path is NOT hard-coded into the UX contract; the MVP Product Contract
governs the curriculum. The UX only renders state.

## 3. Phase

A phase communicates: title, purpose, progress, completed lessons, available
lessons, locked lessons, review items. Progress is visible, persistent,
understandable, and non-destructive.

## 4. Lesson

A lesson is a coherent learning unit (Learn → Guided Practice → Repeat →
Result), not a raw exercise. Internal: Lesson → Practice Items → Exercise
Instances → Attempts. Learner-facing: Lesson → Practice → Result. Not every
Exercise Instance becomes a visible lesson.

## 5. Teach state

Explicit teaching stage before practice: chord name, root, quality, hand,
finger/hand guidance where applicable, visual keyboard, target notes, playback,
demonstration. MIDI remains the authoritative learner input for practice; H2 is
not an ear-training system.

## 6. Practice state

Practice provides a clear target: what to play, which hand, current progress,
what is expected, what was played. Optional runtime aids: visual keyboard,
highlighted target notes, played-note feedback, missed-note feedback, playback,
tempo controls. Never expose internal evaluation implementation.

## 7. Result state

After an attempt the learner receives a concise star-based result (e.g.
`★★★☆☆ 3/5 + pitch/timing feedback`). No binary PASS/FAIL learner-facing
result model. Feedback is honest and derived from real evaluation, never fake.

## 8. Stars

Persistent stars derived from the locked Evaluation Contract:
5 = highest, 0-5 per evaluation, lesson star capacity = 10. Learners see real
EvaluationResult stars (MIDI → Evaluation Engine → EvaluationResult → stars →
UI), never hard-coded or fabricated stars. No best-attempt-only, no automatic
decay, no destructive replacement.

## 9. Lesson progress

Cumulative, capped. Any attempt improves progress unless already at capacity:

```text
0/10, 3/10, 7/10, 10/10 stars
States: Not Started | In Progress | Completed | Mastered/Fully Completed | Needs Review
```

No new backend mastery concept is introduced for these UI labels; present
domain state is mapped to UX terminology.

## 10. Review UX

Review is a first-class destination showing what needs review, why, and what to
practice. If no real review item exists, show "No reviews due" - never fabricate
scheduler behavior.

## 11. Review-assembly terminology (New / Review / Relearning)

The UX visually distinguishes New | Review | Keep Practicing | Strengthen
without exposing scheduler terminology. The Session Composer remains the sole
authority for what to practice and in what order; presentation code never
recomputes priorities.

## 12. Continue Learning

The app remembers the learner's position; "Continue" resumes without manual
navigation. Uses existing domain services; UI never duplicates Session Composer
or Scheduler logic.

## 13. Session Composer presentation

User controls how long and when to practice; the system controls what and in
what order. Presented as a natural plan (e.g. "Practice for 10 minutes", "Today:
1. C Major - Review, ..."). Allocation weights, priority formulas, and scheduler
calculations are never exposed.

## 14. Home / dashboard

Home answers "what should I do now?" immediately: Continue Learning, Review,
Your Progress, Learning Path. The most important action is obvious; the screen
is not an analytics dashboard.

## 15. Learner-facing terminology (stable vocabulary)

Use: Phase, Lesson, Practice, Review, Stars, Mastered, Needs Review, Continue,
New, Keep Practicing. Avoid exposing: EvidenceContribution, EvidenceGroup,
EvaluationInput, EvaluationDimension, Practice Interaction, Execution Session,
Scheduler state — unless a technical/debug mode explicitly needs them.

## 16. Internal vs user-facing boundary

Internal concepts (lesson = Practice Items + Exercise Instances + Attempts;
stars = lesson-star accumulation, separate from mastery) remain internal. The
UX contract translates them into learner concepts; it does not leak the domain
model.

## 17. Accessibility / feedback principles

Clear, calm, observable feedback. Played/missed note feedback is deterministic
and derived from actual input. Color is never the only channel; text labels
accompany icons. Reduce cognitive load; one primary action per screen.

## 18. Responsive layout principles

The contract defines information hierarchy, not pixel layouts. Implementation
must render acceptably across desktop, tablet, and mobile. Do not encode the
desktop-heavy assumption as a domain constraint.

## 19. Implementation boundaries

No implementation in this phase. UI code must not directly manipulate
EvaluationEngine, Scheduler internals, Evidence internals, CoreMIDI, or
RawMidiEvent. UI consumes application-level interfaces only (Presentation →
Application Services → Domain → Infrastructure).

## 20. Lock status

```text
LOCKED: YES
Status: LOCKED (v1.0)
Colors / spacing / widget trees / framework: NOT specified here (H2.11 rule)
```