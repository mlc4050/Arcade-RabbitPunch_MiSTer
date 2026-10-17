# Rabbit Punch / Rabio Lepus

The roadmap in docs/ROADMAP.md was approved in the originating chat. Proceed within
that scope; do not ask for the same approval again. Read CLAUDE.md and docs/WORKFLOW.md
for the inherited project workflow. New board RTL and adapters must be VHDL; approved
CPU, sound, memory, MiSTer framework, and directly instantiated JTFRAME modules may
retain their existing HDL. The user explicitly approved Verilog JTFRAME reuse.
All newly authored HDL, including testbenches and simulation packages, must be
VHDL. Preserve imported HDL unchanged. Use VHDL-2008 features supported by the
target tool; ModelSim acceptance alone does not prove Quartus synthesizability.
Do not treat the inherited template demo as a Rabbit Punch implementation.

User VHDL conventions: use ieee.numeric_std and unsigned, never std_logic_vector
in our new board RTL. std_logic ports use i_/o_ (i_clk/o_ready), internal std_logic
signals use s_. Unsigned input/output ports use iu<width>_/ou<width>_ (iu16_data
for unsigned(15 downto 0)); unconstrained unsigned ports use iux_/oux_. Internal
unsigned signals use su<width>_; unsigned variables use vu<width>_. Integer/natural
signals use sint_, integer/natural variables use vint_. Every state-machine
enumeration type uses t_ (t_state), its signal uses styp_ (styp_state), with uppercase STATE_ literals:
type t_state is (STATE_IDLE, STATE_WAITING, STATE_DRAINING);
signal styp_state : t_state := STATE_IDLE;
Expand all sequential if/elsif/else bodies onto separate lines, closing with
end if;. Use four spaces per indentation level and no tabs in authored VHDL.
Enclose every if/elsif condition in parentheses: if (s_signal = '1') then.
Keep VHDL signal assignments as <=, comparisons as =, and variable assignments as :=.
Use descriptive adapter ports around vendor logic; keep vendor pin names only inside that translation boundary and
explain cryptic signals there. Preserve unchanged third-party sources.
Write each named VHDL port-map association on its own line, indented four spaces
inside the map. Put port map ( and the closing ); on separate lines from the
associations. Do not combine inputs or outputs into paragraph-like maps.
These conventions apply to every VHDL file we author or maintain, including
testbenches and packages. Wrap imported entry points used by our board logic;
required vendor-type conversions stay inside that wrapper. Do not rename imported
internal hierarchies or MiSTer sys sources for style cleanup.
All generated work, caches, build outputs, logs and temporary files go on D:.
Use scripts/d_drive.ps1 to launch Python tools with D-drive temporary/cache paths.

The user requests continuous independent work within the approved scope. Keep
implementing, testing and recording evidence without routine confirmation or a
plan-only stopping point. Stop only on completion, explicit user direction, usage
limits or a genuine blocker requiring unavailable input/permission. Follow the
continuation rule in D:/git/MiSTer-CoreSkill/mister-arcade-core/SKILL.md.

Generic and constant names are uppercase and type-prefixed: GBOOL_/CBOOL_
for boolean, GINT_/CINT_ for integer/natural/positive, GU<width>_/CU<width>_
for sized unsigned, GUX_/CUX_ for unconstrained unsigned, GSTR_/CSTR_ for
string and G_/C_ for single-bit std_logic. Named generic maps follow the same
names. Imported component formal names remain unchanged at their wrappers.
