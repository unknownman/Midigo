# MVP Product Contract v1.1 (H2.11 consolidation)

Curricular and product decisions establishing what the MVP product is. This is
an architectural contract artifact, not a UI spec.

## Product identity

```text
product:       pianolearning app (codename Midigo / MIDI Tutor)
primary input: MIDI via coreMIDI (USB) - the authoritative learner input for practice
platform:      macOS first; responsive to tablet/mobile without domain assumptions
```

## Target vocabulary (locked in code)

```text
TargetQuality: major, minor
TargetRoot:    c, fSharp, bFlat   (spelling preserved as metadata; MIDI is pitch-class based)
TargetHand:    right, left, bothUnison
TargetMode:    block, arpeggio
```

`ExpectedMusicalTargetFactory` (`lib/midi/application/expected_musical_target_factory.dart`)
derives targetId from the definition (`major-c-rh-block`), never generates an
Exercise Instance, and does not implement the curriculum.

## First available skill (H2.11 §27)

```text
chord.major.C.RH.block   ->  C Major, right hand, block
```

is the first available skill of the MVP.

## Curriculum governance

- Curriculum is the MVP Product Contract's domain, not the UX contract's, and
  not the expected-target factory's. The factory constructs only target FORMS.
- The learner-facing Learning Path (Phase → Lesson → Skill) is rendered state;
  the exact curriculum content is not hard-coded in UX code.

## Star + progress policy (frozen H2.9J)

```text
5 stars = highest; 0-5 stars per evaluation result
lesson star capacity = 10 (cumulative, capped, monotonic, no decay)
lesson stars are separate from mastery; NEP is not 0 stars
```

## Product principles (H2.11)

```text
learning loop: Learn -> Practice -> Evaluate -> Result -> Stars -> Continue
               -> Review Later -> Improve -> Master
No gamification overload (no streaks/coins/XP/leaderboards/lives/hearts/badges)
No visual cloning of Yousician / Duolingo Music / flowkey; independent identity
Stars are a learner progress signal; never reinterpreted as mastery/evidence/scheduler interval
```

## Boundary

No scheduler, mastery model, review engine, BLE, or full curriculum is required
by MVP scope beyond the locked contracts. Evidence v1.1 carries no mastery.

## Lock status

```text
LOCKED: YES
Status: LOCKED (v1.1)
```