# Implementation Plan — Slice 2.1: Hand, fingering & keyboard visualization

Implementation plan for the instructional follow-up to Slice 2: explicit hand
indication, canonical fingering for the six C Major lessons, and a compact
static piano keyboard visualization in Teach and Practice. This is a
planning/implementation-first artifact, NOT a new contract. No frozen contract
file is reopened, and no evaluation / runtime architecture changes.

## 1. Existing models reused

Everything derives from what Slice 1 + Slice 2 already built — nothing new is
invented at the musical layer:

- `ExpectedMusicalTarget` (`lib/midi/domain/expected_musical_target.dart`) —
  the single source of truth for hand (`TargetHand` right/left/bothUnison),
  mode (`TargetMode` block/arpeggio), root, quality, and the ordered expected
  note list. Fingering is attached to the exact MIDI pitches this target
  already uses; the pitch list is never modified by fingering.
- `ExpectedMusicalTargetFactory` (`lib/midi/application/…`) — targets are built
  through the unchanged factory: block = `C4 E4 G4` (60/64/67), arpeggio =
  `C4 E4 G4 C5` (60/64/67/72) for all six lessons, including the left-hand
  lessons (the earlier C3-register assumption was a spec example, not the
  actual target — the exact target pitches are preserved per the task rule).
- `LearningCatalog` / `LearningLesson` — lesson identity, order, and the pinned
  `targetId` are the key used to look up the canonical fingering data.
- `TargetPrompt` (`lib/practice/application/target_prompt.dart`) — extended with
  two pure helpers (`letterName`, `isBlack`) so note-letter and white/black-key
  derivation stays centralized next to the existing `pitchName`; no duplicated
  pitch-class tables.
- `PracticeSessionController` snapshot — Teach/Practice render the existing
  `playInstruction` string; the snapshot itself is unchanged.

The instructional presentation model builds ONLY from
`ExpectedMusicalTarget` + canonical fingering data; the UI never hard-codes
notes, hands, or fingerings for a specific lesson.

## 2. Fingering representation

`lib/practice/application/fingering_instruction.dart` — an immutable,
deterministic, target-aware value type with no CoreMIDI and no UI widgets:

```text
FingeringInstruction { int midiNote; int finger; TargetHand hand; }
```

`lib/practice/application/fingering_data.dart` — `FingeringCatalog` keyed by the
pinned lesson `targetId` (deterministic lookup; unknown ids throw). Canonical
beginner fingerings, attached to the target's exact MIDI pitches:

| targetId | Fingerings (pitch → finger) |
| --- | --- |
| `major-c-rh-block` | 60→1, 64→3, 67→5 |
| `major-c-rh-arpeggio` | 60→1, 64→2, 67→3, 72→5 |
| `major-c-lh-block` | 60→5, 64→3, 67→1 |
| `major-c-lh-arpeggio` | 60→5, 64→3, 67→1, 72→2 |
| `major-c-bothUnison-block` | left 60→5, 64→3, 67→1 AND right 60→1, 64→3, 67→5 |
| `major-c-bothUnison-arpeggio` | left 60→5, 64→3, 67→1, 72→2 AND right 60→1, 64→2, 67→3, 72→5 |

Decisions recorded:

- The task's LH arpeggio example used `C3→G3→C4→E4 = 5/3/1/2`. Our pinned
  arpeggio target is the ascending `C4→E4→G4→C5` (60/64/67/72) for both hands.
  Per the task rule ("preserve canonical target notes, attach the corresponding
  fingering to those exact MIDI pitches") the finger pattern `5, 3, 1, 2` is
  applied in sequence order to the actual target pitches: `60→5, 64→3, 67→1,
  72→2`. The target pitch list is untouched.
- `bothUnison` is a single expected note list played by both hands at once; it
  is represented as the union of one left-hand and one right-hand fingering set
  over the same pitches — no second/cloned target is created.

## 3. Instructional presentation representation

`lib/practice/application/lesson_instruction.dart` — one composite model that
Teach, Practice, and the keyboard all consume (the single source of truth for
hand label, mode label, note names, sequence, and fingerings):

```text
LessonKeyFinger { TargetHand hand; int finger; }
LessonKeyVisual  { int midiPitch; String noteName; String letterName;
                   bool isBlack; int sequenceStep; List<LessonKeyFinger> fingers; }
LessonInstruction { ExpectedMusicalTarget target; String handLabel;
                    String modeLabel; bool isArpeggio; List<LessonKeyVisual> keys; }
```

- `handLabel` = `Right Hand` / `Left Hand` / `Both Hands` (learner-facing text,
  always rendered — color is never the only indication).
- `modeLabel` = `Block` / `Arpeggio`.
- `sequenceStep` is 1-based for arpeggio (the played order) and 0 for block
  (simultaneous — "play together").
- The factory throws deterministically if any target note has no fingering, so
  the keyboard can never silently show a key without a finger.
- Hand biases (Collector/Judged training, efficacy weights, difficulty ranking)
  are NOT part of this model — explicitly out of scope.

## 4. Keyboard visualization approach

`lib/ui/widgets/piano_keyboard_view.dart` — a compact static widget built from
existing Flutter primitives only (no new dependencies):

- Range: white keys between the target's lowest and highest MIDI pitch
  (e.g. block → `C D E F G`; arpeggio → `C D E F G A B C`). Never the full 88-key
  piano.
- White keys are labeled with note letters (`C…B`, not numbers); black keys are
  rendered as dark overlays and never carry labels.
- Target keys are filled with the semantic hand color; non-target keys stay
  white. Both-unison keys render both hand colors (left half / right half).
- Finger numbers are drawn as text on each highlighted key — always text, never
  color alone.
- Arpeggio keys carry a small step badge (1 → 2 → 3 → 4) so the played order is
  explicit; block keys carry no step badges (simultaneous).
- A tiny legend under the keyboard maps color ↔ hand label (Right Hand / Left
  Hand) for accessibility.
- Optional lightweight `Semantics` labels per highlighted key (e.g. "C4, right
  hand, finger 1").
- Fixed key height with `Expanded` lanes — no fixed pixel widths, so wide ranges
  shrink instead of overflowing.

`lib/ui/widgets/hand_visual_style.dart` — the centralized semantic hand
abstraction: one color + label per hand (`Right Hand` green, `Left Hand` blue).
"Both hands" uses both semantic colors — never a third hand color.

## 5. UI integration

- `LessonScreen` — builds the `LessonInstruction` once per build from
  `catalog.buildTarget(lesson)` + `FingeringCatalog().fingeringsFor(targetId)`
  and passes it to both views. Boundary unchanged (UI still never touches
  `EvaluationEngine` / `RawMidiEvent` / CoreMIDI).
- `TeachView` — the primary instructional view: lesson title, hand chips
  (colored + always labeled), mode, target notes, press instruction, fingering
  line, arpeggio order line, keyboard, Start Practice. Existing strings stay
  byte-identical (`Lesson 1 · C Major`, `Target notes: C4, E4, G4`,
  `Press C, E, and G together on the right side of the keyboard.`).
- `PracticeView` — retains the essential context statically: hand label, play
  instruction, and the small keyboard under the connected panel. NOT
  MIDI-reactive this slice.

## 6. Tests

Fingering / instruction unit tests (new `test/fingering_instruction_test.dart`):

- RH block `1,3,5`; LH block `5,3,1`; RH arpeggio `1,2,3,5`; LH arpeggio
  `5,3,1,2` attached to the actual target pitches; both-unison contains both
  hands; deterministic across calls; the target pitch list is never altered;
  unknown target id throws.

Hand tests:

- `HandVisualStyle.right`/`.left` colors differ and labels read `Right Hand` /
  `Left Hand`; `Both Hands` label comes from `LessonInstruction.handLabel`.

Keyboard widget tests (new `test/piano_keyboard_view_test.dart`):

- white keys labeled with letters, black keys present and unlabeled;
- target keys highlighted in the hand color, non-target keys white;
- finger numbers rendered on highlighted keys;
- arpeggio shows step badges; block shows none;
- both-unison shows both hand colors and both finger sets;
- renders without overflow at default and narrow widths.

Widget tests (new `test/widget_hand_fingering_test.dart`):

- RH block teach view renders `Right Hand`, `C`, `E`, `G`, `1`, `3`, `5`;
- LH block teach view renders `Left Hand`, `5`, `3`, `1`;
- one arpeggio case renders fingers `1, 2, 3, 5` and the order line.

Regression: all existing Slice-1 / Slice-2 tests remain green, then
`flutter analyze` and `flutter build macos --debug`.

## 7. Explicit non-goals (NOT implemented)

Scheduler, mastery, evidence, review engine, spaced repetition, adaptive
difficulty/tempo, playback/audio, note-pedal or hand-tracking MIDI input, live
MIDI-reactive keyboard visualization, BLE, cloud sync, gamification, a full
88-key keyboard editor, free-play, any new evaluation/practice runtime
architecture, dynamic/derived fingering, per-hand training settings (Collector/
Judged), and any change to frozen contract documents.