# Third-party sources

The MiSTer shell is based on MiSTer-devel/Template_MiSTer at
9c8eadb40067c8ce3aef90899844f62d688ac73a. Its original source notices remain.
The project distribution licence is GPL-3.0-or-later, subject to final dependency audit;
this does not change any imported component's own licence.

| Component | Licence stated by source/donor | Local record |
|---|---|---|
| fx68k | GPLv3; upstream Jorge Cwik | rtl/cpu/fx68k/PROVENANCE.md and LICENSE |
| T80 | BSD-style three-clause; Daniel Wallner and contributors | rtl/cpu/t80/PROVENANCE.md and retained source headers |
| JTFRAME subset | GPL-3.0-or-later; Jose Tejada Gomez | rtl/jtframe/PROVENANCE.md and retained SPDX headers |
| TG68K.C evaluation copy | LGPL-3.0-or-later; Tobias Gubener and contributors | rtl/cpu/tg68k/PROVENANCE.md and retained source headers |
| Donor CPU testbenches | Copied from the named local core repositories | sim/vendor/PROVENANCE.md and source manifest |
| DDR PHY and word-copy engine | GPL v3 in the Psikyo donor README/LICENSE; unchanged | rtl/memory/ddram/PROVENANCE.md and retained LICENSE/UPSTREAM_README.md |
| JT51 / YM2151 | GPL-3.0-or-later; Jose Tejada Gomez | rtl/sound/jt51/PROVENANCE.md and retained LICENSE/README |
| JT7759 / uPD7759 | GPL-3.0-or-later; Jose Tejada Gomez | rtl/sound/jt7759/PROVENANCE.md and retained LICENSE/README |
| NMK16 CPU state monitors (evaluation) | Retained donor notices; unchanged imports | rtl/state/vendor/nmk16/PROVENANCE.md and vendor_manifest.json |
| GX STOP-aware fx68k and capture | GPL-3.0-or-later; Jorge Cwik and donor contributors | rtl/state/vendor/konamigx/PROVENANCE.md and vendor_manifest.json; selected through VHDL state wrappers |
| BoogieWings state-enabled JT51 (evaluation) | GPL-3.0-or-later in JT51 source headers; Jose Tejada Gomez, instrumentation by Umberto Parisi | rtl/state/vendor/boogiewings_jt51/PROVENANCE.md and vendor_manifest.json; separate from production sound |
| Generated state-capable sound VHDL | GPL-3.0-or-later; derived mechanically from the Jose Tejada Gomez chip sources | rtl/state/generated/*_state_netlist.json pins source hashes, generator, tool and state map; docs/SOUND_STATE_NETLIST.md describes qualification |
| SDRAM controller and command model | GPL-3.0-or-later; Sorgelig and donor contributors | rtl/memory/sdram/PROVENANCE.md and sim/vendor/sdram/ |
| CRT Adjust | GPL-3.0-or-later; Umberto Parisi, Andrea Bogazzi | rtl/video/crt_adjust/PROVENANCE.md and source notices |
| HDMI screen_rotate_two | GPL-2.0-or-later; Sorgelig | rtl/video/rotation/PROVENANCE.md and source notices |
| Skill tooling and workflow assets | Inherited from MiSTer-CoreSkill | Bootstrap history and original file notices |

Exact donor commits, source paths and file hashes are in
docs/reference/vendor_manifest.json. No donor RTL was edited locally. Donor-specific
fixes and comments are retained in each DONOR_NOTES.md; they describe their source
projects and are not claims about Rabbit Punch. TG68K is an evaluation/reference
dependency, not the selected main CPU. Its wrapper is only used by a donor test.

The fx68k .mem files are its GPL CPU control store, not game ROMs. User game ROMs,
captured RAM dumps and simulator scratch remain outside tracked source. MAME sources
are kept in a separate reference snapshot with their own original notices.

The distribution retains component notices, licence texts and source provenance.
Release source identity and vendor integrity are recorded in
`docs/reference/savestate_release_20261020_checks.json`.

Local vendor-file integrity passes for every entry in
[the pinned manifest](docs/reference/vendor_manifest.json); the checked byte hashes
and file count are retained in
[the integrity report](docs/reference/vendor_integrity_checks.json).
The JT51/JT7759 records pin the selected donor commits and file bytes; they do
not claim an exact upstream chip-repository revision where the donor omits it.

The isolated Z80 state evaluation imports an unchanged BSD-licensed T80 snapshot
from meatsauce commit `dccc50bb72ded70b67dd9aebec22964f1e4e23b6`.
Its [provenance and byte manifest](rtl/state/vendor/meatsauce_t80/PROVENANCE.md)
are retained beside the files. A descriptive VHDL wrapper uses a separate
library and is selected by the production state composition.
