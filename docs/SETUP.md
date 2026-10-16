# Windows tools still needed

## MAME

The repository is C++ source, not an installed Windows executable. Obtain the official
Windows x64 binary package from https://www.mamedev.org/release.html and extract it to
a dedicated directory. The inspected official release is 0.289 (`mame0289b_x64.exe`).
The package extracts `mame.exe`; the package filename is not the emulator command.

The local source is 1577 commits newer than tag mame0289. Use a separate checkout of
the matching tag for reference captures, or compile the exact local revision. Do not
change the user's existing source checkout merely to make its version label match.
Record executable `-version`, source commit, and file hashes before capture.

The core's gitignored mister.env already points at the local driver and the supplied
merged ROM directory. Add MAME_DIR and MAME_EXE once installed. The archive has both
sets' required files; final `-verifyroms`/`-listxml` checks need the executable.

## Quartus and simulator

The skill targets Quartus Prime Lite 17.0.2 (build 602) for DE10-nano/Cyclone V.
Lite is free. Official legacy Windows download page:
https://www.altera.com/downloads/fpga-development-tools/quartus-prime-lite-edition-design-software-version-17-0-windows

Select update/release 17.0.2 and include Cyclone V device support. Include the legacy
ModelSim-Altera Starter Edition simulator for mixed VHDL/Verilog simulation. The page
lists base 17.0 component packages too; follow its installer/update sequence when
using individual downloads rather than the complete 17.0.2 bundle.

After installation, configure QUARTUS_BIN and MODELSIM_BIN in mister.env if they differ
from C:/intelFPGA_lite/17.0/quartus/bin64 and
C:/intelFPGA_lite/17.0/modelsim_ase/win32aloem. Verify actual tool versions; a default
path printed by coretools.py is not evidence that the program exists.

No software installer or hardware build has been run by this chat.
