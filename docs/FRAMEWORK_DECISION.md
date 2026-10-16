# JTFRAME integration decision

The user explicitly approved JTFRAME reuse in its original HDL, in addition to the
existing mixed-language CPU/sound/framework plan. Do not ask for that approval again.

Use JTFRAME as a module library within the existing MiSTer shell. Keep the bootstrapped
sys/ unchanged and retain one HPS/download/video wrapper. Direct JTFRAME module reuse
does not require instantiating its separate MiSTer top-level or a second SDRAM controller.
The board-facing game interface and new hardware-specific logic remain VHDL.

## Selected direction

| Function | Reuse plan | New VHDL still required |
|---|---|---|
| Sprite row drawing | JTFRAME jtframe_objdraw, its draw/gate chain and object buffers | Descriptor walk, 16x32 row/code mapping, graphics addressing, palette/priority metadata |
| Tile row fetching | Evaluate JTFRAME jtframe_tilemap/tilebuf interfaces against two 64x64 maps | Column-major VRAM decode, scroll and bank/palette register behavior |
| RAM | Compatible JTFRAME dual-port RAM primitives | Board memory decode and state/debug access |
| Clock enables and raster counters | JTFRAME fractional enables/vtimer where suitable | Measured clock ratios, blanking/sync parameters and board interrupts |
| Main and sound CPUs | Existing TG68K/T80 kernels; assess wrapper fit separately | Board-specific bus and IRQ behavior |
| MiSTer output, HPS and ROM transport | Existing template and selected transport modules | Board ROM routing, MRA/download contract and status/control wiring |

The tilemap and raster rows are candidates, not claims that their generic defaults
match Rabbit Punch. A row engine may need an external board decoder or a different
JTFRAME primitive. MAME's incomplete GGA does not provide raw PCB timing.

## Local copies inspected

- `D:/git/Raizing_FPGA/modules/jtframe/`: fuller framework tree with documentation,
  tilemap/tilebuf, vtimer, clocking, SDRAM modules and upstream simulation examples.
  Its README explicitly supports using JTFRAME as a library as well as a framework.
  Its version predates some sprite helpers found in the other checkouts. Do not mix
  interfaces across versions without a pinned dependency closure and simulation.
- `D:/git/Arcade-KonamiGX_MiSTer/rtl/jtframe/`: subset with upstream jtcores commit
  e7958c86d79d549cf5b14b7bbdb517b109a21691 recorded in PROVENANCE.md. That file
  explicitly documents local changes to jtframe_draw and jtframe_objdraw_gate, with
  upstream reference copies beside them. Prefer the coherent upstream baseline when
  appropriate; do not silently inherit GX-specific modifications.
- `D:/git/meatsauce/cores/escapekids/rtl/vendor/jtcores/modules/jtframe/`: another
  subset used by a MiSTer wrapper. Inspected object modules carry extra Z/priority
  ports. Do not assume these are interchangeable with the other donor versions.

## Integration gates

1. Record exact donor revision, local modifications, file hashes, licence and dependency
   closure in the vendored module directory. JTFRAME headers inspected state GPLv3+.
2. Run available unmodified donor testbenches before adapting modules. Simulator/tool
   setup is still pending; no JTFRAME simulation or synthesis has passed for this core.
3. Verify Rabbit Punch graphics bit order and row addressing before connecting memory.
   A 16-pixel generic row drawer and 4-bit ysub need mapping to 32-line sprites.
4. Use MAME captures/write sweeps for snapshot timing and priority tests, including
   sprite-to-sprite behavior. Generic buffer overwrite defaults are not board evidence.
5. Keep the two MRAs aligned with the final loader layout and controls, regardless of
   whether the transport uses JTFRAME internals. Neither game has a playable RBF yet.

This decision reduces newly written graphics infrastructure. The board memory map,
bitmap layer, mixer rules, GGA behavior, sound-command glue and tests remain new work.
