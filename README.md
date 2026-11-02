# DrunkMeter

A lightweight Vanilla WoW / OctoWoW addon for tracking estimated drunkenness.

## Features

- Tracks alcohol potency and drunkenness from confirmed drink consumption.
- Syncs state from Blizzard's sober/tipsy/drunk/smashed system messages.
- Automatically estimates decay while offline and resumes partial decay ticks on login.
- Corrects drunk-distorted hostile enemy levels on the target frame and visible nameplates.
- Shows a compact textured vertical meter with threshold warnings.
- Keeps failed/cooldown drink attempts from increasing the meter.
- Keeps only the latest 20 offline snapshots and 200 debug-log entries.

## Install

Download `DrunkMeter-0.5.0.zip`, extract it, and copy the `DrunkMeter` folder into:

`Interface\AddOns\DrunkMeter`

Then enable **DrunkMeter** from the AddOns menu.

## Offline tracking

On logout DrunkMeter stores the current value, partial 10-second decay progress and a timestamp in SavedVariables. On the next login it applies the same `-1 / 10 seconds` decay to the elapsed offline time. Server hour/minute are also stored with snapshots for diagnostics.

The elapsed-time calculation uses Lua `time()` because the WoW 1.12 `GetGameTime()` API exposes server hour/minute but no date.

## 0.5.0 freeze fix

Core drink confirmation and decay now run before optional nameplate scanning. Nameplate correction is failure-isolated: if OctoWoW exposes an incompatible nameplate frame, only nameplate correction is disabled for that session; the meter continues adding drinks and ticking normally.

## Compatibility

Built for the WoW 1.12.1 API (`Interface: 11200`) and OctoWoW.

Current version: **0.5.0**
