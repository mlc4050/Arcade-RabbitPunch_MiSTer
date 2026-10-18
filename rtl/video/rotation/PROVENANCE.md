# HDMI rotation donor

Unchanged `rtl/video/screen_rotate_two.sv` from Arcade-Seta_MiSTer commit
`208dc11035f3c9356c5c1005c0005aad14e51239`; selected file clean in the donor.
SHA-256: `a704b114cc7d7c1684eb273ab98b436350a3ffb957b350fad975bb322ba11f9e`.
Copyright (C) 2020 Sorgelig; GPL-2.0-or-later as stated in its header.

No local arrival regression was found in the inspected Seta sim/scripts tree.
Rabbit Punch supplies VHDL arrival tests and a descriptive VHDL boundary.
This file is not in files.qip and is not connected to production.

This exact revision does not read DDRAM_BUSY. A buffering/ownership wrapper
and verified loader isolation are required before connection. The adapter
renames pins; it does not itself make DDR writes lossless under backpressure.

The isolated fc479ee fit passes all reported corners and six coverage categories
at 48 MHz: 218 ALMs, 193 registers, zero RAM/PLLs and one inherited DSP.
Minimum setup/hold slack is +9.340/+0.134 ns. The functional netlist passes
the VHDL 16x8 nonuniform-pixel arrival scoreboard for CW and CCW, including
every address, colour, byte mask and framebuffer dimensions/stride/base.
See docs/reference/hdmi_rotation_synth.json and hdmi_rotation_arrival_checks.json.
The installed ModelSim cannot parse the donor's forward declarations and
implicitly static initializers; Quartus compiles it unchanged and supplies
the functional netlist. This is not a backpressure or hardware validation.
