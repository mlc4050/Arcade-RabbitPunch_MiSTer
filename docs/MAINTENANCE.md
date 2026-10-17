# Paused work-RAM maintenance groundwork

rabbitpunch_maintenance waits for confirmed CPU pause and a drained CPU bus,
converts byte requests to aligned 68000 work-RAM addresses/masks, and retains
pause until its acknowledged access completes. Client initialization drains
an already-issued request while discarding its stale client reply. Native RAM
checks cover both MAME score geometries, modified interior values, preserved
neighbors, delayed acknowledgments and initialization during debt.

Its Quartus fit passes all reported 48 MHz timing/coverage gates: 60 ALMs,
46 registers, zero RAM, worst setup +8.377 ns / hold +0.169 ns
(reference/maintenance_synth.json). It uses synthetic half-period input timing,
not a complete core or physical external timing proof.

rabbitpunch_bus_owner queues one CPU and one maintenance pulse, keeps request
payloads until issue, and routes each response to its original owner. A late
CPU pulse takes priority. Maintenance waits for explicit permission; gameplay
reset never cancels the owner's debt. The composed native-RAM test poisons CPU
payload pins after their pulse, withholds maintenance permission after CPU
completion, checks both replies and the preserved CPU write, then repeats both
score-block transfers and reset-drain checks
(reference/maintenance_owner_checks.json).

These modules are not in the production board yet. Integration must include
all owner queue/active/offered work in ROM-load idle, and must acknowledge
already-issued board I/O requests even while resetting their side effects.
The current I/O initialize branch suppresses responses, so a delayed accepted
request cannot simply be forwarded into that branch. Production integration
needs directed reset/load tests before use. HPS persistence remains separate.
