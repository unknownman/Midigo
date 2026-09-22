# Implementation Roadmap v1 (H2.11)

First implementation slices only. The gate has passed; no further broad
contract phases. The next phase is software implementation.

## Vertical Slice 1 — C Major / RH / Block

End-to-end, learner-facing, small.

### Scope (IN)

```text
Learner home
Learning path
Lesson screen
Teaching state
Practice state
MIDI connection
Exercise Instance consumption
Practice Interaction
Attempt lifecycle
Evaluation
Result screen
Star accumulation
Basic lesson progress
Review UI concept (empty state = "No reviews due")
```

### Explicitly NOT in slice 1 (H2.11 §28)

full mastery, full scheduler, full review engine, all curriculum, all chord
qualities, all roots, all hands, all modes, adaptive tempo, BLE.

### End-to-end path (slice 1)

```text
Learning Path
   ↓
C Major lesson (chord.major.C.RH.block)
   ↓
Teach (C Major, right hand, block, visual keyboard, target notes)
   ↓
Practice (MIDI input)
   ↓
Raw/normalized/semantic pipeline (H2.1-H2.7)
   ↓
ExpectedMusicalTarget (H2.5 factory)
   ↓
EvaluationInput (H2.8)
   ↓
EvaluationEngine (H2.9) → EvaluationResult.stars
   ↓
Stars (real, 0-5) + lesson progress (capped cumulative, capacity 10)
   ↓
Result screen → Continue
```

### Contract dependencies (already locked)

- Practice Runtime v1.1 (RT-007 Attempt lifecycle; RT-006 Exercise Instance consumption)
- Evaluation v1.1 frozen engine
- Learning UX v1.0
- MVP Product v1.1 (first skill chord.major.C.RH.block)
- Architecture v1.1 (Presentation → Application Services → Domain → Infrastructure)

### Boundary

UI consumes application-level interfaces only. No direct
EvaluationEngine/Scheduler/Evidence/CoreMIDI/RawMidiEvent manipulation from UI.

```text
NEXT STEP:
Begin implementation of Vertical Slice 1:
C Major / RH / Block.

Do not create another broad contract phase.
```