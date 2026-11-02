# DrunkMeter

A lightweight Vanilla WoW / OctoWoW addon for tracking estimated drunkenness.

## Features

- Tracks alcohol potency and drunkenness from confirmed drink consumption.
- Failed/cooldown attempts do not increase the value.
- Syncs state from Blizzard's sober/tipsy/drunk/smashed system messages without restarting the decay phase.
- Automatically estimates decay while offline and resumes the partial 10-second phase on login.
- Corrects drunk-distorted hostile enemy levels on the target frame and visible nameplates.
- Uses a tall **32 px outer / 28 px inner** meter with dark solid-red fill.
- Shows exactly two static markers: **DRUNK** (grey) and **SMASHED** (gold).
- Shows a white 2 px decay ticker that sweeps across the full bar every 10 seconds, independent of fill height.
- Keeps only the latest 20 offline snapshots and 200 debug-log entries.

## 0.6.2 fixes

- Restored the pre-regression meter width and inset the fill so it cannot cover the border.
- Replaced the fill/marker assets with the Vanilla-safe `Interface\\ChatFrame\\ChatFrameBackground` solid texture; no gradient or retail-only texture dependency.
- Kept threshold markers and the white moving ticker on deterministic overlay layers above the fill.
- Removed non-authoritative `decayElapsed = 0` resets from chat/system synchronisation.
- Consolidated live decay around one phase variable used by both numerical decay and the ticker.
- Added robust elapsed handling: supplied elapsed when sane, `GetTime()` fallback when missing/invalid, sanity comparison for mismatched callback signatures, and a cap for absurd deltas.
- Offline recovery is guarded to run once and preserves the remainder of the partial 10-second phase.
- `/drunk debug` now records periodic timer samples (raw elapsed, fallback delta, used delta, source, phase and value) plus decay ticks, explicit resets, offline recovery and drink additions.
- Optional nameplate errors remain isolated from the core scheduler.

## Install

Download `DrunkMeter-0.6.2.zip`, extract it, and copy the `DrunkMeter` folder into:

`Interface\\AddOns\\DrunkMeter`

Then enable **DrunkMeter** from the AddOns menu.

## Offline tracking

On logout DrunkMeter stores the current value, partial decay progress and a wall-clock timestamp. On the next login it combines the saved phase with offline elapsed time, applies `-1` for each complete 10-second interval, keeps the remainder, and starts the live clock from that remainder.

Example: value 100 at phase 7 seconds, then 8 seconds offline -> one decay tick, value 99, phase 5 seconds.

## Compatibility

Built for the WoW 1.12.1 API (`Interface: 11200`) and OctoWoW.

Current version: **0.6.2**
