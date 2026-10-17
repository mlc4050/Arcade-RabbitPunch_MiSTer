# MAME assumptions reproduced by this core

Reference: MAME 0.289, release commit
`f34f02505e32c1993c6a782b6814232cbfc74e36`,
`src/mame/vsystem/rpunch.cpp` and `vsystem_gga.cpp`.
Both in-scope sets carry MACHINE_SUPPORTS_SAVE and MACHINE_NO_COCKTAIL.
The absence of an imperfect-graphics flag does not establish physical video timing.

| Assumption | MAME source | Core behavior | Evidence needed for original hardware |
|---|---|---|---|
| GGA device is a skeleton | vsystem_gga.cpp description and write handler | rabbitpunch_io stores sixteen byte registers and a low-four-bit address latch | Chip documentation, netlist or PCB register tests |
| Register 0b controls interrupt rate | rpunch_state::gga_data_w / crtc_interrupt_gen | rabbitpunch_irq waits for the next vblank, then holds level 1 once per frame, or twice for data c0, until CPU acknowledge | PCB interrupt timing versus GGA writes |
| Synthetic raster configuration | rpunch machine configuration | No physical timing generator selected; the IRQ module accepts external vblank/half-frame events | Schematics/raw timing or measured PCB sync waveform |
| Scroll byte-only writes ignored | rpunch_state::scrollreg_w | Decoder/I/O update scroll only for full-word writes and store the low nine bits | PCB tests of independent byte writes |
| Guessed sprite/foreground priority split | rpunch_state::draw_sprites | Offline model copies the index-based mask and MAME's occupied-sprite priority pixels; tile/sprite RTL not implemented yet | PCB overlap tests including sprites behind foreground |

Core-specific incomplete work is tracked in HACKS.md. Additional graphics behavior
must be recorded as the hardware modules land.
No vendored CPU disagreement is currently worked around in board RTL.


## Native uPD7759 decoder saturation

The pinned MAME 0.289 upd7759.cpp update_adpcm adds its table delta to m_sample
without a nine-bit clamp. The unchanged JT7759 decoder instead saturates each
update to -256..255. Every one of their 256 step entries and state transitions
agrees in the shared range; adpcm_decode_tb checks actual decoded values there
and tests native saturation separately. Preserve the selected vendor behavior;
no patch is applied to make artificial overflowing streams match MAME. Original
DAC overflow behavior and any effect on these games remain unmeasured. This is
a known reference difference, not a claim that MAME or the donor has been proved
correct on physical hardware. Evidence: reference/adpcm_decode_checks.json.
