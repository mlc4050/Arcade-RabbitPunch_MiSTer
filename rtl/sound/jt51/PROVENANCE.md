# JT51 evaluation copy

Upstream: https://github.com/jotego/jt51, Jose Tejada Gomez, GPL-3.0-or-later.
Copied unchanged from Arcade-JalecoMS1BCD_MiSTer at f16ec2b84c14409b5ae7b8ade761fffd7ec34b8e; the selected files
are clean in that donor. Its exact upstream JT51 revision is not recorded here.
The native HDL dependency closure is selected by its jt51.f list. LICENSE and
README are preserved. All file SHA256s are in docs/reference/vendor_manifest.json.

SIMULATION diagnostic helpers sep32.v and sep32_cnt.v are copied unchanged from
the local complete upstream JT51 checkout at 00dd3f935c8d73bbebe7a16c4af1c6f32ac742ed, under
sim/vendor/jt51. They are not chip RTL or synthesis dependencies. That older
checkout's top-level test uses DAC ports absent from this selected donor; do
not silently mix its chip RTL with this version. The selected donor carries no
original regression suite. New VHDL baseline tests must identify their scope;
vendoring alone is not validation or game sound integration.
