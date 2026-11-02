DrunkMeter 0.6.0
================

Vanilla WoW / OctoWoW addon for tracking estimated drunkenness.

Features
--------
- Tracks confirmed alcohol consumption and potency.
- Syncs from Blizzard sober/tipsy/drunk/smashed system messages.
- Corrects drunk-distorted hostile enemy levels on the target frame and visible nameplates.
- Uses a slim textured vertical meter with only DRUNK (grey) and SMASHED (gold) threshold lines.
- Value and state are displayed below the meter; drink icons and the tipsy/max markers are removed.
- Automatically estimates decay while you are offline.
- Nameplate correction is failure-isolated so custom nameplates cannot stop drink tracking or decay.

Offline decay
-------------
DrunkMeter saves the current value, partial 10-second decay progress, a wall-clock timestamp,
and the current server clock whenever the tracked state changes and on logout. On the next login
it applies the same -1 per 10 seconds decay to the elapsed offline time and resumes the partial tick.

The calculation uses Lua time() because WoW 1.12 GetGameTime() exposes only server hour/minute and
no date. Server hour/minute are still stored in the rolling history for diagnostics.

Only the latest 20 offline/state snapshots and latest 200 debug log entries are retained so the
SavedVariables file stays small.

Commands
--------
/drunk                 Show current value/state and help.
/drunk set <0-256>     Manually correct the estimate.
/drunk reset           Set value to zero.
/drunk lock            Lock the meter.
/drunk unlock          Unlock it for dragging.
/drunk debug           Toggle debug chat output.
/drunk clearlog        Clear the SavedVariables debug log.
/drunk show            Show the meter.
/drunk hide            Hide the meter.

Install
-------
Copy the DrunkMeter folder to Interface\AddOns\DrunkMeter and enable it from the AddOns menu.
