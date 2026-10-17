# DDR load-time transport

Copied byte-for-byte from Arcade-Psikyo_MiSTer at e2f717e110f9c113e46d949072c81c4b5e966965; all selected files
are clean. Source paths/hashes are in docs/reference/vendor_manifest.json.
The donor README states GPL v3 and its LICENSE contains GPLv3. Both are retained.
The native files do not add an or-later statement; no broader licence is inferred.
The donor header traces the loading mechanism to srg320/Arcade-PsikyoSH2_MiSTer.
No vendor changes are made. This is a development integration, not a hardware claim.

rom_loader reads eight-byte DDR granules and emits four little-endian 16-bit
words. Its optional Psikyo ADPCM-A swap must be disabled for Rabbit Punch's
already-laid-out image. Native write addresses are 25 bits, sufficient for the
0x210000-byte in-scope image; do not silently widen or truncate a larger image.
DDR request acceptance also requires DDRAM_BUSY low, even when native busy is
low. The descriptive boundary must account for both sources of backpressure.
Native dl_req is held until dl_busy acknowledges acceptance and remains blocked
until dl_busy drops; it is not a ready/valid word stream without an adapter.

The original DDR PHY test/model are retained unchanged under sim/vendor/ddram.
Run them before adaptation. No matching native word-loader test was identified;
a new VHDL behavioral DDR/word-backend baseline must pass before system use.
No physical DDR/HPS, rotator sharing or real-image transfer is proven by copying.
