# DrunkMeter

A lightweight Vanilla WoW / OctoWoW addon for tracking estimated drunkenness.

## Features

- Tracks alcohol potency and drunkenness from confirmed drink consumption.
- Syncs state from Blizzard's sober/tipsy/drunk/smashed system messages.
- Automatically estimates decay while offline and resumes partial decay ticks on login.
- Corrects drunk-distorted hostile enemy levels on the target frame and visible nameplates.
- Uses a very slim textured vertical meter with only DRUNK and SMASHED threshold markers.
- Keeps failed/cooldown drink attempts from increasing the meter.
- Keeps only the latest 20 offline snapshots and 200 debug-log entries.

## 0.6.0 UI redesign

- Meter width reduced from 22px to 12px.
- Removed the tipsy threshold marker and max/cap marker.
- DRUNK threshold is grey; SMASHED remains gold.
- Threshold and decay lines span exactly the bar width.
- Value and state now sit below the meter.
- Removed the drink/beer icon assets from the addon package.

## Install

Download `DrunkMeter-0.6.0.zip`, extract it, and copy the `DrunkMeter` folder into:

`Interface\\AddOns\\DrunkMeter`

Then enable **DrunkMeter** from the AddOns menu.

## Offline tracking

On logout DrunkMeter stores the current value, partial 10-second decay progress and a timestamp in SavedVariables. On the next login it applies the same `-1 / 10 seconds` decay to the elapsed offline time. Server hour/minute are also stored with snapshots for diagnostics.

## Nameplate safety

Core drink confirmation and decay run before optional nameplate scanning. Nameplate correction is failure-isolated: if OctoWoW exposes an incompatible nameplate frame, only nameplate correction is disabled for that session; the meter continues adding drinks and ticking normally.

## Compatibility

Built for the WoW 1.12.1 API (`Interface: 11200`) and OctoWoW.

Current version: **0.6.0**
