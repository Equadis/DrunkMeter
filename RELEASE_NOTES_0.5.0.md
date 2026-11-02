# DrunkMeter 0.5.0

- Adds SavedVariables-backed offline decay estimation.
- Preserves partial 10-second decay progress across logout/login.
- Keeps the latest 20 offline/state snapshots and 200 debug-log entries.
- Hardens nameplate correction so a client-specific nameplate error cannot freeze drink confirmation or decay.
- Core drink confirmation/decay now runs before optional nameplate scanning.
