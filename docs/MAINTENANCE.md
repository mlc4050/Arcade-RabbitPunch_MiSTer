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

The board, complete system and logical platform now expose maintenance byte
access. The board's pause request also pauses the sound CPU; maintenance ready
waits for both CPU adapters plus drained main-bus ownership. Ordinary CPU
requests bypass the owner on their original edge when the bus is free, and
replies remain combinationally qualified by owner. Contention alone uses packet
queues. Directed tests verify that request/reply edges are preserved, both
contention orders complete, poisoned source pins cannot change queued data,
and all-idle includes queued, active and currently offered work.

System download waits for both ROM transport and board-owner idle. Reset-time
I/O clears its side effects while still acknowledging an already-issued
request with FF read data, allowing the old owner to drain. The executing-CPU
diagnostic consumes maintained A511/3311 words, preserves independent user
pause, checks both byte lanes and the end of work RAM, cancels a client result
without canceling backend debt, and replaces images on offered I/O writes and
ROM fetches (reference/system_maintenance_checks.json). Without the I/O ack fix
the diagnostic stalls image loading; the private negative control is in
debug/baselines/system_maintenance_unfixed_io/result.log. The earlier queued-
CPU prototype also exposed the need to count queue debt at ROM handoff; the
final CPU bypass removes its ordinary-path request delay.

The audio regression also performs maintenance write/read while a sample is
playing: both CPUs pause while ADPCM and YM cadence continue. Platform controls,
DIP, byte/DDR and native HPS protocol regressions pass with the integrated owner.
Full-platform implementation passes all reported 48 MHz timing and six coverage
gates with 6431 ALMs, 7832 registers and unchanged 927339 RAM bits
(reference/platform_synth.json); worst setup +2.885 ns, hold +0.082 ns. These interfaces provide access for
persistence/state tooling, but HPS score upload/restore is not implemented.
