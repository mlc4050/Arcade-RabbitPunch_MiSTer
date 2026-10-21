# T80 230-bit state-port evaluation

Copied byte-for-byte from `D:/git/meatsauce/cores/s32multi/rtl/audio/T80` at
`dccc50bb72ded70b67dd9aebec22964f1e4e23b6`. Selected source files match that
commit. Per-file source/target hashes are in `vendor_manifest.json`; original
three-clause BSD-style licence and copyright headers are retained.

This local T80 v350 snapshot extends REG/DIR to include WZ, Alternate and
Halt_FF, and normalizes execution to a clean fetch on DIRSet. The unchanged
T80s wrapper is retained as a bus-interface reference; the evaluation uses a
descriptive VHDL boundary around the imported CPU in its own VHDL library.

The interface does not export all microstate or pending NMI context. It needs
a proved clean, prefix-free opcode-fetch boundary after the interrupt decision.
RabbitPunch has no ordinary Z80 NMI or BUSRQ input; this restriction must remain
explicit. HALT, refresh R, IFF/IM, pending EI/IRQ, alternate banks, WZ and normal
sound-ROM behavior need native qualification before production replacement.

The import is isolated from files.qip. No imported file is locally edited.
