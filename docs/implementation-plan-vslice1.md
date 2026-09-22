# Implementation Plan — Vertical Slice 1 (C Major / RH / Block)

Status: **Implementation plan for review. No code written.** Gate already PASS (per `docs/contract-consolidation-audit-v1.1.md`). This document is not a contract and changes no locked artifact.

Governing contracts (all LOCKED, all read-only for this phase):
`evaluation-contract-v1.1` (frozen engine, `mvp_default_v1`), `evidence-aggregation-v1.1`,
`practice-runtime-v1.1` (RT-001..RT-015), `learning-ux-v1.0`, `mvp-product-v1.1`,
`architecture-v1.1`, `implementation-roadmap-v1`.

---

## 1. End-to-end flow

```
Home (Continue Learning)
   ↓
Learning Path (Piano Foundations → C Major, RH, Block)
   ↓
C Major Lesson
   ├── Teach    (C Major = C4 E4 G4, right hand, block; target notes; visual keyboard)
   ├── Practice (connect MIDI, see target, play the chord)
   │      └── one ATTEMPT = one performance of the C-major block
   │             (Note-On/Off stream captured per attempt)
   ├── Result   (stars 0..5 from real EvaluationEngine; feedback summary; retry/continue)
   ↓
Lesson Progress (cumulative stars, capped at 10, monotonic)
   ↓
Home → Review ("No reviews due" — empty-state placeholder, no scheduler)
```

`chord.major.C.RH.block` ↔ frozen factory target `major-c-rh-block`
(`ExpectedMusicalTargetFactory.build(quality: major, root: c, hand: right, mode: block)`).

---

## 2. Files to create / modify

### New — Practice Runtime domain (`lib/practice/domain/`)

| File | Contents |
| --- | --- |
| `practice_clock.dart` | `abstract PracticeClock { DateTime now(); }` + `SystemPracticeClock`. Practice-domain time for lifecycle `started_at`/`ended_at` only (RT-004/RT-012). Never used for identity or evaluation. |
| `exercise_instance.dart` | `ExerciseInstance` (deterministic, caller-supplied `id`, wraps one `ExpectedMusicalTarget`). Thin content-derived wrapper (RT-006). |
| `attempt.dart` | `AttemptState` enum (`armed, active, paused, completed, abandoned, invalidated`; **no** `failed`) + `Attempt` (id, state, startedAt, endedAt, evaluationResult?). Frozen-consistent: carries `EvaluationResult` but is not one. |
| `practice_item.dart` | `PracticeItem` (id, `ExerciseInstance`). Owned by a Practice Interaction (RT-005). |
| `practice_interaction.dart` | `PracticeInteraction` (id, items, startedAt, endedAt, endReason) + `ExecutionSession` (id, LOCKED 1:1 to its PI, RT-011/RT-013) + `EndReason` (`completed`, `abandoned`). |

### New — Application services (`lib/practice/application/`)

| File | Contents |
| --- | --- |
| `evaluation_flow.dart` | `EvaluationFlowService.execute(target, List<RawMidiEvent>, midiSessionId) → EvaluationResult`. Composes the **frozen** chain: `MidiNormalizer` → `MusicalEventInterpreter` → `StructuralAligner` → `EvaluationDimensionObservationExtractor` → `EvaluationInputPreparer` → `EvaluationEngine`, with `EvaluationPolicyProfile.instance` and the slice-1 fixed context `{mode: block, learnerLevel: beginner, tempoBpm: 90}`. No new grading logic. |
| `practice_runtime.dart` | `PracticeRuntime` (domain authority, RT-001): owns `createInteraction`, `addPracticeItem`, `armAttempt`, `activateAttempt`, `pauseAttempt`/`resumeAttempt`, `completeAttempt(result)`, `abandonAttempt`, `invalidateAttempt`, `endInteraction`. Uses `PracticeClock`. Attempt ≠ Interaction ≠ Evidence everywhere. |
| `lesson_progress.dart` | `LessonProgress` (targetId, stars, attemptCount) + `LessonProgressStore` interface. |
| `lesson_progress_service.dart` | Applies H2.9J frozen policy: only `EvaluatedResult.stars` accumulate; `NotEnoughPerformanceResult` records an attempt but adds no stars; capped at `lessonStarCapacity: 10`, monotonic, no decay, separate from mastery. |
| `in_memory_lesson_progress_store.dart` / `json_lesson_progress_store.dart` | Store impls. JSON file store: deterministic map `{targetId: progress}`, root `Directory` injected (macOS Application Support default in production). |
| `slice1_catalog.dart` | Slice-1 producer: one lesson "C Major" → one `ExerciseInstance` (`major-c-rh-block`). Boundary only — **not** a full Exercise Generator. |
| `practice_session_controller.dart` | **MIDI + practice boundary.** Owns discovery/connection/event-stream/capture + `PracticeRuntime` + `EvaluationFlowService` + `LessonProgressService`. Exposes a narrow UI-facing `ValueNotifier<PracticeUiState>` and methods (list/connect/disconnect, startAttempt, endAttempt). UI never touches `EvaluationEngine` / `RawMidiEvent` / CoreMIDI. |

### New — Presentation (`lib/ui/`)

| File | Contents |
| --- | --- |
| `home/home_screen.dart` | Home: Continue Learning, Learning Path, Review, Your Progress. |
| `learning_path/learning_path_screen.dart` | Renders lesson list state (rendered state only; curriculum from `slice1_catalog`). |
| `lesson/lesson_screen.dart` | Host: Teach → Practice → Result as one stateful lesson flow (state via `ValueNotifier`). |
| `lesson/teach_view.dart` `practice_view.dart` `result_view.dart` | Lesson sub-stages. Practice view consumes `PracticeSessionController` (connects MIDI, start/end attempt). Result shows real stars + concise feedback from `EvaluationResult`. |
| `review/review_screen.dart` | Review destination; **empty state only**: "No reviews due". No scheduler, no fabrication (H2.11 §10/§29). |
| `widgets/star_display.dart` | Renders 0..5 stars from an int. |
| `developer/diagnostics_route.dart` | Keeps existing `MidiSourceDiagnosticView` reachable for debugging (it is not the home). |

### Modify (existing)

| File | Change |
| --- | --- |
| `lib/main.dart` | home → `HomeScreen`; diagnostics remain reachable via a developer entry; optional injected services (defaulting to Macos impls) so tests can inject fakes — same pattern as `MidiSourceDiagnosticView`. |
| `test/widget_test.dart` | Adapt the small set of tests that pump `MidiTutorApp` to the new home; diagnostics coverage moves to pumping `MidiSourceDiagnosticView` directly (test infra unchanged: `MockStreamHandler` / `TestDefaultBinaryMessengerBinding`). |
| `README.md` | Status line: foundation complete → slice-1 implementation begins; update layout/`Later phases` note. (Document only.) |

No change to any file in `lib/midi/domain`, `lib/midi/application`, or `macos/Runner/MIDI`.

---

## 3. Implementation order & dependencies

To keep every step verifiable and green:

| Step | Build | Depends on | Gate |
| --- | --- | --- | --- |
| **M0** | Practice domain (`practice_clock`, `exercise_instance`, `attempt`, `practice_item`, `practice_interaction`) | none | unit tests (M0) pass |
| **M1** | Lesson progress (`lesson_progress`, `lesson_progress_service`, both stores) | M0 | unit tests (M1) pass |
| **M2** | `evaluation_flow.dart` (frozen-pipeline composition) | frozen `lib/midi/*` | `evaluation_flow_test` matches engine semantics (M2) |
| **M3** | `practice_runtime.dart` + `practice_session_controller.dart` + `slice1_catalog.dart` | M0–M2 | unit tests (M3) pass |
| **M4** | UI (`lib/ui/**`) + `main.dart` routing + widget tests | M3 | widget tests pass |
| **M5** | Integration + validation | M4 | analyze/test/build |

Each gate runs `flutter analyze` and `flutter test` before the next step starts.

---

## 4. Reuse of frozen H1/H2 layers (no rewrite)

The evaluation path reuses only existing, frozen components, invoked in order:

```
RawMidiEvent (H1.3, frozen)
  → MidiNormalizer.normalizeAll                (H2.1)
  → MusicalEventInterpreter.interpret          (H2.4)
  → StructuralAligner.align(target, sessionId, observed)  (H2.6)
  → EvaluationDimensionObservationExtractor.extract       (H2.7)
  → EvaluationInputPreparer.prepare                       (H2.8)
  → EvaluationEngine.evaluate(input, EvaluationPolicyProfile.instance, ctx)  (H2.9, frozen)
  → EvaluationResult  (EvaluatedResult.stars 0..5 | NotEnoughPerformanceResult)
```

MIDI I/O reuses `MidiDeviceDiscovery`, `MidiDeviceConnection`, `MidiEventStream`,
`MidiRawEventCapture`, `RawMidiEventBuffer` unchanged. No new grading algorithm,
no decoding, no alignment changes, no new identity from random/wall-clock.

---

## 5. Practice Runtime / Practice Interaction / Attempt boundary

```text
PracticeInteraction (deterministic id e.g. pi-major-c-rh-block-1)
  ├── 1:1 ExecutionSession (es-pi-major-c-rh-block-1)   [PR-015 v1.1]
  ├── started_at / ended_at (PracticeClock; never MIDI app_monotonic_ts_ms)
  ├── end_reason ∈ {completed, abandoned}
  └── PracticeItem (…-item-0)
        └── Attempt (…-attempt-1)
               state: armed → active ⇄ paused → completed
                      | → abandoned | → invalidated        [FAILED = no state]
               evaluationResult: EvaluationResult (stars) when completed
```

- Identities are **caller-supplied / content-derived**, deterministic, reproducible (RT-003/RT-020). No `uuid`/`DateTime.now()` as identity.
- Attempt ownership: exactly one Practice Item → one Practice Interaction (RT-013).
- `PracticeRuntime` is the domain authority; `PracticeSessionController` is the app-level orchestrator (UI boundary).
- Practice timestamps only from `PracticeClock` (RT-004/RT-012). `MidiConnectionSession.sessionId` is the MIDI capture scope (H1.2), never conflated with Execution Session (RT-011).

---

## 6. Application-layer interfaces

```text
UI (lib/ui/**)                          [Presentation]
  │  depends only on:
  ▼
PracticeSessionController                [Application Services]
  ├─ PracticeUiState (ValueNotifier)     → Home/Path/Lesson/Review screens
  ├─ listSources / connect / disconnect  → MidiDeviceDiscovery/Connection (frozen)
  ├─ startAttempt / endAttempt           → MidiRawEventCapture (buffer per attempt)
  ├─ endAttempt → EvaluationFlowService  → EvaluationResult
  │              → PracticeRuntime.completeAttempt
  │              → LessonProgressService.apply  → LessonProgressStore
  ▼
PracticeRuntime                         [Domain]
  ▼
EvaluationFlowService                   [Application Services]
  ▼
frozen H1.3 capture + H2.1–H2.9 pipeline [Domain/Infra, read-only]
```

Explicit rules:
- UI imports **no** `evaluation_engine.dart`, `raw_midi_event.dart`, or CoreMIDI.
- UI consumes evaluation results (stars/feedback), never constructs `EvaluationInput`.
- ONE MIDI capture stream per attempt; buffer cleared at `startAttempt`, snapshotted at `endAttempt` (`MidiRawEventCapture.start(sessionId)` already clears and session-filters).
- Lesson progress is the only durable state in slice 1.

---

## 7. State management (existing project conventions)

Repo has **no** state-management package (pubspec: only `cupertino_icons`; dev: `flutter_test`, `flutter_lints`). Stay consistent:

- `ValueNotifier`/`ValueListenableBuilder` + constructor injection — same pattern already used by `MidiRawEventCapture.revision` and `MidiSourceDiagnosticView` (services passed in, Macos impls as defaults).
- Screens are `StatefulWidget`; lesson sub-stages switch on a `ValueNotifier<LessonStage>`.
- No `provider`/`bloc`/`riverpod`; no new pubspec dependencies.
- Navigation: plain `Navigator.push`/`MaterialPageRoute` (diagnostics stays reachable, not the home).

---

## 8. Persistence requirements for slice 1

Only lesson progress is persisted:

- `JSONLessonProgressStore(root)` writes a small deterministic JSON map `{targetId: {stars, attemptCount}}` to macOS Application Support (`library/Application Support/Midigo/lesson_progress.json`); `InMemoryLessonProgressStore` for tests.
- No database; no schema migrations; no attempt/practice-interaction/evidence persistence (evidence is explicitly **not implemented** in H2.11; runtime records are in-memory).
- Store is behind the `LessonProgressStore` interface so a richer store can replace it later without touching UI.

**Genuine open decision** (see §14-1): persistence format/location. Recommended = hand-rolled JSON above (zero new deps, matches repo style). Alternative = add `shared_preferences`.

---

## 9. Learner-facing screens / states

| Screen | States / content |
| --- | --- |
| Home | Continue Learning (→ C Major), Learning Path, Review, Your Progress; one primary action. |
| Learning Path | single phase "Piano Foundations"; lesson "C Major" state: locked/available/new/in-progress/completed needs review mapping (rendered from progress). |
| C Major Lesson | Teach → Practice → Result flow. |
| Teach | chord name, root C, quality Major, RH, block; target notes C4 E4 G4; visual keyboard with target keys; playback note (optional). No internal terminology. |
| Practice | target visible; MIDI connect state (connect/disconnect); "Play the C Major chord" + Done; live capture active; retry allowed. |
| Result | real stars (0..5), concise feedback from `EvaluationResult` (e.g. "2 missing notes", pitch/timing), retry / continue. Never fabricates; NEP shown as "Not enough performance". |
| Stars / progress | `n/10`, capped monotonic; completed at 10. |

---

## 10. Review UX placeholder/boundary

- `ReviewScreen` exists and is reachable from Home.
- **Empty state only** in slice 1: renders exactly "No reviews due" (H2.11 §10/§29). No scheduler, no review queue, no intervals, no fabricated items, no `SUCCESS/RELEARNING_SUCCESS` vocabulary (EVG-023).
- Review state derives only from real domain data; with no scheduler phase, the empty state is truthful.

---

## 11. Automated tests

| Suite | File | Covers |
| --- | --- | --- |
| Practice runtime unit | `test/practice_runtime_test.dart` | PI lifecycle + `end_reason`; Attempt state machine **all** transitions incl. illegal ones (`paused→completed` allowed, `abandoned→active` rejected, no `failed`); 1:1 ES↔PI; deterministic IDs; timestamps from fake `PracticeClock` (not MIDI monotonic). |
| Evaluation flow | `test/evaluation_flow_test.dart` | Pure-Dart `RawMidiEvent` fixture of a perfect C-major block (60/64/67 note-on/note-off) → `EvaluatedResult` (5 stars); wrong-pitch fixture → reduced stars; incomplete (1 note) → NEP. Must match `evaluation_engine_test.dart` semantics; asserts provenance/versions pass through. |
| Lesson progress | `test/lesson_progress_test.dart` | 5-star attempt → 5/10; monotonic cap at 10; NEP → no stars but +1 attempt; 0-star evaluated → 0 stars, +1 attempt; no decay. |
| Stores | `test/lesson_progress_store_test.dart` | in-memory; JSON round-trip via temp `Directory`; corrupt file → deterministic empty/error. |
| Session controller | `test/practice_session_controller_test.dart` | connect → start/end attempt with injected fake stream + fake clock → interaction/attempt/execution-session records + stars + progress; abort mid-attempt → `abandoned`; connect before MIDI → clear error. |
| Widget (learning flow) | `test/widget_learning_flow_test.dart` | Pump `MidiTutorApp` (or Home) with injected fakes; navigate Path → Lesson → Teach → Practice (MockStream `note_on/off`) → Result shows star widget + message; progress updates; back to Home. Mirrors existing `MockStreamHandler` test style. |
| Widget (review/home/path) | `test/widget_learning_screens_test.dart` | Empty-state Review ("No reviews due"); Home primary-action presence; Learning Path renders rendered state. |
| Widget (adapt diagnostics) | edit `test/widget_test.dart` | Existing diagnostics coverage re-pointed to pump `MidiSourceDiagnosticView` directly; assertions unchanged. |

Assertions count target: existing **476** staying green + ~30–40 new (M0–M5).

---

## 12. Acceptance criteria

1. `flutter analyze` → no issues. `flutter test` → existing 476 + new all pass. `flutter build macos --debug` succeeds.
2. Learner can go Home → Learning Path → C Major → Teach → Practice with a real keyboard (or injected fake): capture → evaluation → Result, end to end.
3. Stars on Result are the **real** `EvaluationResult.stars` (perfect C-major block = 5; wrong notes/large timing spread = lower; empty/single-note = NEP), never hard-coded.
4. Lesson progress is cumulative, capped at 10/10, monotonic, persists across app restart (JSON store).
5. Attempt lifecycle end-to-end: `armed → active → completed`; abandon mid-attempt → `abandoned`; no `failed` state anywhere.
6. `PracticeInteraction` ↔ `ExecutionSession` is exactly 1:1; Execution Session ≠ `MidiConnectionSession` in code and docs.
7. Practice timestamps come from `PracticeClock`; no code promotes MIDI `app_monotonic_ts_ms` to practice time.
8. No UI file imports `evaluation_engine.dart` / `raw_midi_event.dart` / CoreMIDI.
9. Review screen shows "No reviews due"; no scheduler types/vocabulary anywhere in slice-1 code.
10. No frozen contract file or `lib/midi/domain`/`lib/midi/application` file is modified.

---

## 13. Explicitly NOT implemented in slice 1

Full mastery; full scheduler/review engine; evidence recording/aggregation; complete curriculum beyond `major-c-rh-block`; arpeggio/LH/minor/F#/Bb targets in UI; live per-note feedback during practice; tempo/playback engine; BLE; adaptive difficulty; gamification (no streaks/coins/XP); cloud sync; analytics; persistence of attempts/interactions/evidence.

---

## 14. Genuinely unresolved decisions for review

1. **Persistence**: recommend zero-dependency JSON file store (§8). Requires your sign-off to hand-roll the store instead of adding `shared_preferences`.
2. **Attempt granularity**: an attempt = ONE performance of the C-major block (single 3-note chord). Alternative = a multi-chord series per attempt (would require reworking alignment semantics). Recommendation: single-chord attempt, matches the frozen block target shape.
3. **Slice-1 fixed evaluation context**: `learnerLevel = beginner`, `tempoBpm = 90` (the simultaneity dimension throws without a learner level). Recommendation: beginner as the MVP default.
4. **State mgmt**: no package (ValueNotifier + constructor injection). If you prefer `provider`/`riverpod`, say so before M4.
5. **Diagnostics reachability**: keep `MidiSourceDiagnosticView` behind a developer entry rather than deleting it. Recommendation: keep it.

## 15. Deliverable flow after approval

On your sign-off: execute M0→M5, run the §12 acceptance gates, then `flutter analyze` / `flutter test` / `flutter build macos --debug`, commit the slice as `feat(midi): implement vertical slice 1 - C major block practice` (subject to your approval), and report results — without modifying any frozen contract.