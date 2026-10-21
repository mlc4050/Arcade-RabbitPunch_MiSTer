# Savestate implementation cross-checks

Local source examples inspected while validating the Rabbit Punch state path:

| Core | Pinned commit | Relevant files and limits |
| --- | --- | --- |
| Konami GX | `89124d4f29e1d3f95557e5e5265efcbe9d0d7cb4` | `rtl/gx_savestate.sv`, `rtl/gx_ss_ddr.sv`, `docs/SAVESTATES.md`: CPU parking, atomic slot publication and common save/load raster release. Its documentation explicitly excludes ROM cache/clock phase state and reports eventual frame drift; that is not proof of cycle-exact continuation. The existing Rabbit Punch 68000 donor is pinned to this source. |
| Namco System 2 | `5fe71a594fa9ec4462acf04248f7f6abb0f64ba7` | `rtl/savestate/`, `docs/savestates.md`: coherent CPU phase stop, draining queued sound operations, rebuilding derived video before release. Its YM2151 path replays register shadows and documents envelope differences, so it cannot supply exact FM continuation here. |
| NMK16 | `4c9b923a87dcefee27574a8a06361e47e8e9b963` | `rtl/savestate/savestate.sv`, `savestate_ui.sv`: four DDR slots, framebuffer-write priority, completion feedback and HPS status updates. Its sound-replay and timeout-release policies need separate review before reuse; they do not replace Rabbit Punch's complete sound image or partial-apply hold. Its UI also documents the conflict between an F2 state shortcut and Service Mode. |
| Taito GNET | `4f21d12c5c8f6958eda6ef3193add1cbc3b417df` | `rtl/savestates.vhd`, `rtl/statemanager.vhd`, `sim/system/src/tb/tb_savestates.vhd`: VHDL memory/register sequencing, busy handshakes and a system-idle capture boundary. Its PSX memory and CPU maps are not Rabbit Punch interfaces. |
| System 11 | `cb0fe4040b9c9479140d9de6ce9ca4015df19549` | `rtl/savestates.vhd`, `rtl/statemanager.vhd`: related VHDL state-transfer and idle coordination patterns; board-specific register coverage still requires its own inventory. |
| Jaleco MS1 B/C/D | `f16ec2b84c14409b5ae7b8ade761fffd7ec34b8e` | `rtl/savestate/savestate.sv`: toggle-handshaked DDR ownership, final counter/length publication and raster release after sprite-buffer refill. It uses sound-register replay and permits timeout release; those policies do not establish exact sound continuation or safe partial-apply recovery here. |
| Seibu SPI | `fd25dd4057547d654c876bc0349698d1c88619e2` | `rtl/spi_ss.sv`, `rtl/savestates.sv`, `SeibuSPI.sv`: private CPU stub entry before image writes, explicit DMA-idle wait, cache invalidation and a free-running physical raster. These are useful ordering cross-checks; the 386/cache and interrupt assumptions are board-specific. The DDR composition masks busy when its requester does not own the bus. |
| meatsauce Zero Team USA | `dccc50bb72ded70b67dd9aebec22964f1e4e23b6` | `cores/zeroteamusa/rtl/common/savestate.sv`, `savestate_ram.sv`: registered state-bus acknowledgments, borrowed byte-pair RAM ports and final region-header publication after a subordinate image stream. Its 32-slot region packing is unnecessary for the requested four-slot interface and is not adopted. |

These references support architectural comparisons, not transferred validation.
No production source was imported or changed by this cross-check. Any subsequent
reuse must preserve the imported implementation behind a descriptive VHDL wrapper,
pin its provenance, and pass the Rabbit Punch continuation tests.

Rabbit Punch retains complete generated FM/ADPCM register images, validates an
entire image before apply, drains accepted responses across cancellation, and
holds an incomplete restore until repair or game reset. The remaining full-game
gate compares timed CPU writes, PCM/cadence and pixels from the same canonical
release edge. Matching screens or ordered bus writes alone cannot close it.
