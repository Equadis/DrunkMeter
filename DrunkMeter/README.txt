DrunkMeter 0.6.2
================

Vanilla WoW / OctoWoW addon for tracking estimated drunkenness.

Features
--------
- Tracks confirmed alcohol consumption and potency.
- Failed/cooldown drink attempts do not increase the meter.
- Uses the 0-256 drunkenness scale and Blizzard sober/tipsy/drunk/smashed state messages.
- Corrects drunk-distorted hostile enemy levels on the target frame and visible nameplates.
- Automatically estimates decay while offline and resumes the saved partial 10-second phase.
- Nameplate correction is failure-isolated so it cannot stop drink tracking or decay.

0.6.2
-----
- Restored the intended 32 px outer / 28 px inner tall meter proportions.
- Red fill is inset inside a thin border and uses a flat Vanilla-safe solid texture (no gradient).
- Exactly two static marker lines: DRUNK is grey and SMASHED is gold.
- White decay ticker is 2 px high and sweeps top-to-bottom across the full bar every 10 seconds.
- Ticker position is independent of red fill height.
- Live decay and ticker now share one authoritative decayElapsed phase.
- Removed chat/system synchronisation resets that could repeatedly restart the phase.
- Added robust elapsed handling using callback elapsed plus a GetTime() monotonic fallback and sanity checks.
- Offline recovery runs once and preserves partial phase.
- Added bounded /drunk debug timer diagnostics for raw/fallback delta, phase, ticks, resets and drinks.

Commands
--------
/drunk                 Show current value/state and help.
/drunk set <0-256>     Manually correct the estimate (resets decay phase).
/drunk reset           Set value to zero and reset phase.
/drunk lock            Lock the meter.
/drunk unlock          Unlock it for dragging.
/drunk debug           Toggle bounded timer/debug chat output.
/drunk clearlog        Clear the SavedVariables debug log.
/drunk show            Show the meter.
/drunk hide            Hide the meter.

Install
-------
Copy the DrunkMeter folder to Interface\AddOns\DrunkMeter and enable it from the AddOns menu.
