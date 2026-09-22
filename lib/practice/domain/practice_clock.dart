/// Practice-domain time source.
///
/// The only sanctioned way the Practice Runtime obtains practice-lifecycle
/// timestamps (RT-004/RT-012): `started_at`/`ended_at` of a Practice
/// Interaction or Attempt belong to the practice domain and must never be
/// synthesized from MIDI capture `app_monotonic_ts_ms`, first-note time,
/// target-creation time, or evaluation-layer inference.
///
/// Identity is never derived from this clock; identity and time are separate
/// concepts. Tests inject a deterministic fake implementation.
abstract interface class PracticeClock {
  DateTime now();
}

/// Production clock backed by the system wall clock.
final class SystemPracticeClock implements PracticeClock {
  const SystemPracticeClock();

  @override
  DateTime now() => DateTime.now();
}