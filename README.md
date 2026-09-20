# Midigo — MIDI Tutor

A macOS piano-learning application, built with Flutter, that captures and processes raw MIDI input from USB keyboards via CoreMIDI.

> **Status**: early platform foundation. H1 (macOS CoreMIDI capture layer) is in progress.

## What this builds towards

- Detect hardware/software MIDI sources (CoreMIDI).
- Connect to a source and establish a capture session.
- Stream raw MIDI events to the app with per-session sequence numbers and monotonic timestamps.
- Later phases: exercise generation, practice runtime, evaluation, and mastery tracking.

## Project layout

- `lib/midi/domain/` — immutable domain models (`MidiSourceInfo`, `MidiConnectionSession`, `RawMidiEvent`, error contracts).
- `lib/midi/application/` — platform-agnostic adapters: device discovery, connection/session lifecycle, event stream, raw capture buffer.
- `lib/midi/infrastructure/` — platform-specific integration.
- `lib/diagnostics/` — diagnostic views for verifying discovery, connection, and live raw-event capture.
- `macos/Runner/MIDI/` — the macOS CoreMIDI native adapter (`CoreMIDIAdapter`).

## Current capabilities

- **H1.1 — Source discovery**: lists CoreMIDI MIDI input sources (name, manufacturer, unique id).
- **H1.2 — Connection + session lifecycle**: connect/disconnect over a method channel; session ids are fresh UUIDs, never reused.
- **H1.3 — Raw event capture**: MIDI client + input port + source connection, packet → `RawMidiEvent` mapping, live Dart event stream, and an in-memory append-only capture buffer.

Raw events are deliberately uninterpreted: a Note-On with velocity 0 stays a Note-On. No normalization, deduplication, or musical evaluation is performed at the capture layer.

## Platform support

macOS only (CoreMIDI). Targets Apple Silicon and Intel builds.

## Testing

```sh
flutter analyze
flutter test
xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner \
  -configuration Debug -destination 'platform=macOS'
```

Tests cover the discovery contract, connection/session lifecycle, raw-event decoding/mapping (including the Note-On velocity-0 rule), capture buffering, and native CoreMIDI packet decoding.