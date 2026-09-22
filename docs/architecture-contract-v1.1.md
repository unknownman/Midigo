# Architecture Contract v1.1 (H2.11 consolidation)

Layered architecture and identity conventions already established by the locked
repository (H1 CoreMIDI foundation, H2 music pipeline, H2.9 evaluation). This
phase consolidates them into their authoritative written form.

Supporting sources: `README.md`, `lib/` layout, `lib/midi/domain/evaluation_contract.dart`,
`lib/midi/domain/evaluation_policy.dart`, `lib/midi/domain/evaluation_result.dart`.

## Layering

```text
Presentation (UI)          -> learner-facing screens; consumes application services only
Application Services       -> orchestrates domain + infrastructure (MIDI adapters, discovery)
Domain                      -> immutable models, pure domain services (evaluation, target, policy)
Infrastructure             -> platform-specific integration (macOS CoreMIDI native adapter)
```

The `lib/` layout already realizes three of these:

```text
lib/midi/domain/       DOMAIN      - immutable models (MidiSourceInfo, RawMidiEvent,
                                     ExpectedMusicalTarget, EvaluationInput, EvaluationResult,
                                     EvaluationPolicyProfile, EvaluationContract, ...)
lib/midi/application/  APPLICATION - platform-agnostic adapters + orchestrators (discovery,
                                     connection, normalizer, interpreter, aligner, extractor,
                                     preparer, engine; expected-target factory)
lib/midi/diagnostics/  PRESENTATION-adjacent diagnostic views/metrics (verification UI)
macos/Runner/MIDI/     INFRASTRUCTURE - macOS CoreMIDI adapter
```

## Core identity conventions (locked in code)

```text
- Identities are content-derived and deterministic; never random, never wall-clock.
  (ExpectedMusicalTargetFactory derives targetId from the definition; MvpDefaultEvaluationProfile
  and contracts are fixed constants.)
- No UUID.randomUUID() / DateTime.now() identity generation anywhere in lib/.
- Every layer result is immutable; mutating source collections cannot mutate outputs.
- Same input + same contract + same profile => same result (determinism).
- No I/O, no randomness, no global mutable state in domain services.
```

## Pipeline (H2.5 → H2.9)

```text
ExpectedMusicalTarget (H2.5) + ExpectedMusicalTargetFactory
  -> structural_aligner (H2.6)
  -> evaluation_dimension_observation_extractor (H2.7)
  -> evaluation_input_preparer (H2.8)
  -> EvaluationEngine (H2.9)
  -> EvaluationResult (H2.9)
```

MIDI capture feeds the pipeline from H1/H2.1: raw events → normalized events →
musical events → observations. See H2.1-H2.8 commits.

## Contract identity + governance

```text
contract_name/version      Evaluation Contract v1.1, Evidence Aggregation v1.1,
                           Practice Runtime v1.1, MVP Product v1.1, Learning UX v1.0
profile era                mvp_default_v1 / Evaluation Contract v1.1 (H2.9 generation)
provenance requirement     EV-012 (derived): every result propagates targetId, sessionId,
                           mode, evaluationProfileId/Version, layer algorithm versions
```

## Boundaries mandated by H2.11

```text
- UI must not directly manipulate EvaluationEngine / Scheduler / Evidence / CoreMIDI / RawMidiEvent.
- Session Composer != Exercise Generator != Practice Runtime
- Practice Interaction != MIDI Connection Session; Execution Session != MIDI Connection Session
- One authoritative contract artifact per major subsystem.
```

## Lock status

```text
LOCKED: YES
Status: LOCKED (v1.1, consolidation of H1/H2-locked facts)
```