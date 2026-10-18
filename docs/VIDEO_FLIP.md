# Common screen flip and analog output

The native machine generates RGB and sync for the MiSTer framework's analog
I/O-board path. Standard 15 kHz CRT operation uses native output with forced
scandoubling and HQ2x disabled. HDMI aspect/integer-size metadata is separate
from this native stream. Physical CRT operation and CRT Adjust remain open.

`rabbitpunch_view_flip` transforms coordinates at the existing renderer/scanout
boundary before analog and HDMI diverge. The visible viewport is X=8..295 and
Y=0..215, so a 180-degree flip maps X to 303-X and Y to 215-Y. Row requests render
the mirrored source row into the same two line banks. Pixel requests read the
mirrored source position, including the bitmap layer, and returning RGB tags
are mapped back into physical scanout coordinates. RGB values, sync, pixel
enables, transaction handshakes and bank ownership pass through existing paths.
There is no new pixel, row or frame memory and no additional RGB pipeline stage.

The effective request is the game video-flags bit 12 XOR main-OSD status bit 65
(`Flip Screen`). Applying both restores normal orientation. The real game DIP
remains a game input: the game translates it into the video flag, so it is not
also applied directly by the display logic. This option applies to analog as
well as HDMI and is therefore not hidden in direct-video mode.

Orientation is held throughout a displayed frame. A requested change is applied
at frame preparation, only when no render/pixel transaction is outstanding or
pending acceptance and no old RGB reply is returning. That edge precedes
acceptance of the next row-zero request. If work overruns the boundary,
orientation stays unchanged until a later safe frame; sync never waits.
Game-not-ready clears abandoned transaction ownership while the display is
blanked. Initialization clears the adapter. These are presentation registers,
not emulated game RAM; see STATE.md.

The VHDL unit test passes 124416 coordinate points across normal and flipped
orientations and checks pending requests, outstanding rendering/pixels,
back-to-back completion/acceptance, reload and initialization. Evidence:
reference/view_flip_checks.json. The standard machine loading/pause/replacement
regression also passes with this wiring; it completes before a full visible
render window and does not prove flipped game pixels.

A fresh MAME 0.289 Rabio Lepus capture has the real Flip Screen DIP set before
power-on and confirms video-flags 0x1000. The driver stores but does not render
this global flag (MAME_KLUDGES.md). Consequently the expected flipped image is
the raw captured frame explicitly rotated 180 degrees. Both full-renderer
comparisons, routed integrated timing and physical output are still pending.
This implementation does not claim recovery of the C7-01 GGA's internal
address generation or original-board raster behavior.


The native HPS host also passes a fresh standalone fit and complete functional
netlist protocol test with the always-visible Flip Screen menu. Every config
character, status transfer, keyboard/pad input and ROM/high-score file transfer
passes. See reference/host_flip_synth.json and reference/host_netlist_checks.json.
Physical ARM/menu operation remains part of hardware bring-up.
