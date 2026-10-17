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
| Skill tooling and workflow assets | Inherited from MiSTer-CoreSkill | Bootstrap history and original file notices |

Exact donor commits, source paths and file hashes are in
docs/reference/vendor_manifest.json. No donor RTL was edited locally. Donor-specific
fixes and comments are retained in each DONOR_NOTES.md; they describe their source
projects and are not claims about Rabbit Punch. TG68K is an evaluation/reference
dependency, not the selected main CPU. Its wrapper is only used by a donor test.

The fx68k .mem files are its GPL CPU control store, not game ROMs. User game ROMs,
captured RAM dumps and simulator scratch remain outside tracked source. MAME sources
are kept in a separate reference snapshot with their own original notices.

Full component notices/licence texts and build-source obligations must be audited
before distribution. This development checkpoint is not a binary release.
