# Patch Notes

## 2026-05-08 - Round lifecycle, respawn, and Color Battle fixes

### Round participation and disconnect handling
- Fixed players leaving during a round still being counted as alive or eligible to win.
- Moved round-system player removal handling before save/leaderboard cleanup so disconnects update live round state immediately, even if datastore work yields.
- Added explicit per-round participant tracking with `roundParticipantIds` so late joiners, stale player data, and players who left mid-round do not affect alive counts, results, or winner selection.
- Added connection checks during arena spawn setup so a player who leaves while the round is starting is not reset back to alive or teleported into the map.
- Made `Preparing` a real server-side state so disconnects during fade/map generation/countdown are handled as round-affecting events.
- Preserved solo testing behavior for rounds that genuinely started with one player, while ending rounds that originally had multiple players once only one participant remains.

### Respawn modes and reset behavior
- Fixed manual character reset in Respawn FFA and Color Battle sending the player back to lobby while the timer kept running.
- Routed Humanoid deaths in respawn-based modes through the same arena respawn flow used by bomb deaths.
- Added `respawnPending` tracking to prevent duplicate respawns from overlapping damage/reset events.
- Canceled pending respawns when a player leaves the server.
- Guarded respawns so disconnected players and non-participants cannot be respawned back into an active round.

### Color Battle rules
- Changed Color Battle to be respawn-based.
- Color Battle now runs until the timer ends, or until the forced last-player condition applies.
- Kept Color Battle winner selection based on tile ownership rather than kills.
- Kept Color Battle results sorted by tiles even though the mode now uses respawns.

### Results and scoring cleanup
- Round results now only include players who were actual participants in the round.
- Respawn-mode timer winner selection now ignores non-participants.
- Color Battle timer winner selection now ignores non-participants.

### Tooling
- Added an Aftman manifest pinning Rojo 7.6.1 for repeatable local builds.
- Verified the project with `rojo build default.project.json --output build-check.rbxlx`.
