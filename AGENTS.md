# Rabbit Punch / Rabio Lepus

The roadmap in docs/ROADMAP.md was approved in the originating chat. Proceed within
that scope; do not ask for the same approval again. Read CLAUDE.md and docs/WORKFLOW.md
for the inherited project workflow. New board RTL and adapters must be VHDL; approved
CPU, sound, memory, MiSTer framework, and directly instantiated JTFRAME modules may
retain their existing HDL. The user explicitly approved Verilog JTFRAME reuse.
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
These conventions apply to every VHDL file we author or maintain, including
testbenches and packages. Wrap imported entry points used by our board logic;
required vendor-type conversions stay inside that wrapper. Do not rename imported
internal hierarchies or MiSTer sys sources for style cleanup.
All generated work, caches, build outputs, logs and temporary files go on D:.
Use scripts/d_drive.ps1 to launch Python tools with D-drive temporary/cache paths.
