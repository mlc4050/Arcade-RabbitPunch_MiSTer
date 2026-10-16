# JTFRAME row-drawer and object-buffer baseline

Source: Arcade-KonamiGX_MiSTer, commit
89124d4f29e1d3f95557e5e5265efcbe9d0d7cb4; selected files clean.
Donor identifies https://github.com/jotego/jtcores at
e7958c86d79d549cf5b14b7bbdb517b109a21691 as its upstream. Licence:
GPL-3.0-or-later (SPDX headers). DONOR_NOTES.md retains the donor's original history.

- jtframe_draw.v is copied byte-for-byte from the donor's
  jtframe_draw_upstream_reference.v, avoiding the GX-specific modified drawer.
- jtframe_obj_buffer.v and jtframe_dual_ram.v are copied byte-for-byte.
- jtframe_dual_ram.v contains both jtframe_dual_ram and jtframe_dual_ram_cen.
  This is the complete dependency closure for the tested default configurations.
- No gate/wrapper or shift helper is vendored at this stage. Board scheduling and
  row-address integration have not been implemented.

Local RTL changes: none; the source basename of the unmodified drawer is restored.
Hashes and original paths: docs/reference/vendor_manifest.json. Local tests check
row pixels, palette, flip and ROM delays; object-buffer tests check transparent pen,
priority modes, bank changes and clearing. These are new interface tests, not upstream
unit tests: no standalone row/buffer test accompanied this donor subset.

The buffer is resetless. Its SIMULATION define initializes the line-bank selector;
the test clears both RAM banks through public read/erase ports. Hardware startup
initialization and MAME-measured snapshot policy remain board-integration work.
