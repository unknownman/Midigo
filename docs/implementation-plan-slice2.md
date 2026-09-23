# Implementation Plan — Slice 2: Learning Path progression

Implementation plan for Vertical Slice 2: a real multi-lesson Learning Path with
persistent, deterministic progression. This is a planning/implementation-first
artifact, NOT a new contract, and it does not reopen any frozen contract file.

## 1. Existing architecture reused

No new system architecture, no state-management framework, and no new
dependencies. Slice 2 reuses the Slice 1 stack unchanged:

- `PracticeRuntime` (`lib/practice/application/practice_runtime.dart`) — Practice
  Interaction / Execution Session 1:1, Attempt lifecycle, deterministic IDs.
- `EvaluationFlowService` (`lib/practice/application/evaluation_flow.dart`) —
  the frozen MIDI evaluation composition; the app never grades elsewhere.
- `LessonProgress` / `LessonProgressService` / `LessonProgressStore`
  (`lib/practice/application/`) — cumulative, capped, monotonic stars; already
  keyed by arbitrary `targetId` strings, so **no store migration is needed** for
  multiple lessons.
- `PracticeSessionController` — injected `ValueNotifier<PracticeSessionSnapshot>`
  + constructor injection pattern; UI boundary unchanged (UI never touches
  `EvaluationEngine` / `RawMidiEvent` / CoreMIDI / `MidiNormalizer`).
- `ExpectedMusicalTargetFactory` — builds all six target forms deterministically.

The only change to existing application code is *generalizing* the controller's
hard-coded Slice-1 IDs/descriptions to derive from the injected target, so Slice
1 target IDs (`major-c-rh-block`, `pi-major-c-rh-block`,
`exercise-major-c-rh-block`) stay byte-identical.

## 2. Learning Path model

New pure domain types (no services, no MIDI transport types):

```text
lib/practice/domain/learning_lesson.dart
    LearningLesson { id, title, subtitle, order, quality, root, hand, mode, targetId }
    LearningLesson.starCapacity == 10        (the frozen acquisition ceiling)

lib/practice/domain/learning_path.dart
    LessonAvailability { locked, available, inProgress, completed }
    LessonState        { lesson, progress, availability }
    LearningPath       { lessons (ordered), lessonById, nextLessonAfter }
```

`LearningLesson` carries only curriculum vocabulary (target enums + derived
`targetId`). It exposes `buildTarget()` through the factory. No `RawMidiEvent`,
CoreMIDI, or `Evaluation*` types appear in any curriculum type.

## 3. Lesson catalog

`lib/practice/application/learning_catalog.dart` — a narrow fixed catalog (not an
exercise generator), mirroring the Slice-1 boundary:

| Order | Lesson id | targetId | Hand | Mode |
| --- | --- | --- | --- | --- |
| 1 | `lesson-major-c-rh-block` | `major-c-rh-block` | right | block |
| 2 | `lesson-major-c-rh-arpeggio` | `major-c-rh-arpeggio` | right | arpeggio |
| 3 | `lesson-major-c-lh-block` | `major-c-lh-block` | left | block |
| 4 | `lesson-major-c-lh-arpeggio` | `major-c-lh-arpeggio` | left | arpeggio |
| 5 | `lesson-major-c-bothUnison-block` | `major-c-bothUnison-block` | bothUnison | block |
| 6 | `lesson-major-c-bothUnison-arpeggio` | `major-c-bothUnison-arpeggio` | bothUnison | arpeggio |

- Every id is deterministic and derived from the lesson definition — no UUID,
  no `Random`, no `DateTime`, no array-index-as-identity.
- Lesson 1 reuses the Slice-1 canonical constants
  (`Slice1Catalog.cMajorLessonId`, `Slice1Catalog.cMajorTargetId`), so **all
  Slice-1 persisted progress loads unchanged**.
- `LearningCatalog` exposes `allLessons`, `lessonById`, `nextLessonAfter`,
  `previousLessonBefore` — all null-safe for unknown ids.

## 4. Progress model

Reuse `LessonProgress` as-is (`targetId`, `stars` 0..10, `attemptCount`):

- one `LessonProgress` record per target id;
- `NEP` and zero-star `EvaluatedResult` increment `attemptCount`, add no stars;
- stars accumulate, capped at 10, monotonic — **this is the existing
  acquisition/completion condition** (vertical slice 1: "completed at 10").

`JsonLessonProgressStore` already stores `{targetId: {stars, attemptCount}}`;
new lesson target ids simply add new keys. Slice-1 persisted files remain
valid.

## 5. Availability / unlock rules

Pure derivation from persisted `LessonProgress` only (load once per lesson):

```text
completed   : stars >= 10                       (existing acquisition rule)
in_progress : attemptCount > 0   and not completed
available   : no attempts        and (isFirst  OR previous lesson completed)
locked      : no attempts        and previous lesson NOT completed
```

- First lesson is always `available`.
- Lesson N (N > 1) unlocks only when lesson N-1 is `completed` (stars >= 10).
- Because `NEP` / zero-star attempts add stars == 0, they can never complete or
  unlock a lesson.
- `LearningPathService` (`lib/practice/application/learning_path_service.dart`)
  loads all lesson progress through the existing `LessonProgressService` and
  returns a `LearningPath` of `LessonState`s. Derivation is sequential, so the
  unlock state is exactly "previous completed".

## 6. UI changes

- `LearningPathScreen` — renders all six ordered lessons with their availability
  state (icon + status); locked lessons are not tappable; tapping an available /
  in-progress / completed lesson opens it. Existing strings preserved
  (`Lesson 1 · C Major`, `0 / 10 stars`).
- `LessonScreen` — accepts a `LearningLesson`; builds the correct target through
  the catalog; title reflects the lesson; **Continue** navigates to the next
  lesson when it becomes available, otherwise pops back to the Learning Path.
- `TeachView` — target-aware: lesson subtitle, note names (`C4, E4, G4` /
  `C4, E4, G4, C5`), hand/mode instruction text derived from the target.
- `PracticeView` — target-aware play instruction (notes + mode) derived from the
  target; `Finish Attempt` unchanged.
- `ResultView` — unchanged; snapshot already carries stars / progress.
- `HomeScreen` — Learning Path card summarizes the current lesson (title + stars)
  using the path service.

A small pure helper maps MIDI pitch → note name to derive the learner-facing
note strings (no MIDI transport types in the UI).

## 7. Tests

New `test/learning_catalog_test.dart`:

- six ordered lessons; ids deterministic and stable; lesson 1 == Slice-1 ids;
- `lessonById` / `nextLessonAfter` / `previousLessonBefore` null-safe for unknown
  ids and at the ends;
- each lesson builds the expected target (mode/hand/notes) via the factory.

New `test/learning_path_service_test.dart` (availability):

- fresh path → lesson 1 available, lessons 2–6 locked;
- completing lesson 1 (10 stars) unlocks lesson 2; lesson 3 stays locked until
  lesson 2 is completed;
- incomplete progress (<10 stars) does not unlock the next lesson;
- zero-star evaluated attempt (and NEP) does not count as completion / unlock;
- reopening persisted progress preserves availability;
- derived from `InMemoryLessonProgressStore` and a JSON-backed store round trip.

Extended `test/practice_session_controller_test.dart`:

- target-aware interaction/exercise/attempt ids for an arpeggio target;
- description / result-message strings derive from the target.

Extended widget tests (`widget_learning_flow_test.dart`,
`widget_learning_screens_test.dart`):

- Learning Path shows six lessons with correct availability states;
- a real MIDI arpeggio performance (RH arpeggio) evaluates to 5 stars end to end;
- Result **Continue** opens the next lesson when available; final lesson
  Continue returns to the Learning Path;
- locked lessons are not tappable.

## 8. Validation

```sh
flutter analyze          # no issues
flutter test             # all Slice-1 tests remain green
flutter build macos --debug
```

## 9. Explicit non-goals (NOT implemented)

Scheduler, mastery, evidence aggregation, evidence groups, review engine /
review queue, spaced repetition, retrieval latency adaptations, adaptive
difficulty/tempo, cloud sync, analytics, achievements/XP/streaks/leaderboards,
notifications, BLE, JSONL export, MIDI device features, any new
PracticeRuntime/Evaluation architecture, and any change to frozen contract
documents. A lesson can be completed for Learning Path progression while still
not being mastered; mastery is out of scope and "completed" here means only the
existing acquisition rule (cumulative stars reach 10).