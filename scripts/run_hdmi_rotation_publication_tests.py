# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Qualify frame publication with the fitted rotator and actual VHDL write queue."""
import argparse
import hashlib
import json
from coretools import core_root
from run_baselines import run_case

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--full', action='store_true', help='Include both complete native rotated images')
args = parser.parse_args()
root = core_root()
proof = json.loads((root / 'docs/reference/hdmi_rotation_netlist_checks.json').read_text(encoding='utf-8'))
netlist = 'debug/netlists/hdmi_rotation_' + proof['commit'][:7] + '/hdmi_rotation_check.vo'
assert hashlib.sha256((root / netlist).read_bytes()).hexdigest() == proof['netlist_sha256']
template = root / 'sim/video/hdmi_rotation_buffers_tb.vhd'
text = template.read_text(encoding='utf-8')
marker = 'begin\n    s_clk <='
assert text.count(marker) == 1
text = text.replace(marker, '''    signal s_raw_write, s_busy, s_full, s_empty, s_overflow : std_logic;
    signal s_capture, s_flush, s_frame_valid, s_discard : std_logic;
    signal s_publication_seen : std_logic := '0';
    signal su29_raw_address : unsigned(28 downto 0);
    signal su64_raw_data : unsigned(63 downto 0);
    signal su8_raw_bytes : unsigned(7 downto 0);
    signal su3_valid_buffers : unsigned(2 downto 0);
    signal sint_stall_phase : natural range 0 to 511 := 0;
begin
    s_busy <= '1' when sint_stall_phase < 96 or
        (sint_stall_phase >= 256 and sint_stall_phase < 320) else '0';
    stalls : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            if (sint_stall_phase = 511) then
                sint_stall_phase <= 0;
            else
                sint_stall_phase <= sint_stall_phase + 1;
            end if;
        end if;
    end process;
    assert (s_overflow /= '1') report "Publication fixture overflowed its bounded queue" severity failure;
    s_clk <=''')
for old, new in [('ou29_ddr_word_address => su29_word_address', 'ou29_ddr_word_address => su29_raw_address'),
                 ('ou64_ddr_data => su64_data', 'ou64_ddr_data => su64_raw_data'),
                 ('ou8_ddr_byte_enables => su8_byte_enables', 'ou8_ddr_byte_enables => su8_raw_bytes'),
                 ('o_ddr_write => s_write', 'o_ddr_write => s_raw_write')]:
    assert text.count(old) == 1
    text = text.replace(old, new)
marker = '    monitor : process'
assert text.count(marker) == 1
text = text.replace(marker, '''    write_queue : entity work.rabbitpunch_ddr_write_queue
        port map (
            i_clk => s_clk,
            i_initialize => s_flush,
            i_write => s_raw_write and s_capture,
            iu29_word_address => su29_raw_address,
            iu64_data => su64_raw_data,
            iu8_byte_enables => su8_raw_bytes,
            o_full => s_full,
            o_empty => s_empty,
            o_overflow => s_overflow,
            i_ddr_busy => s_busy,
            o_ddr_write => s_write,
            ou29_ddr_word_address => su29_word_address,
            ou64_ddr_data => su64_data,
            ou8_ddr_byte_enables => su8_byte_enables
        );
    publication : entity work.rabbitpunch_frame_publication
        generic map (
            GINT_FRAME_PIXELS => GINT_VISIBLE_WIDTH * GINT_VISIBLE_HEIGHT
        )
        port map (
            i_clk => s_clk,
            i_initialize => '0',
            i_enable => '1',
            i_game_ready => '1',
            i_loader_active => '0',
            i_vertical_sync => s_donor_vertical_sync,
            i_donor_enabled => s_enabled,
            i_pixel_write => s_raw_write,
            iu2_write_buffer => su29_raw_address(21 downto 20),
            iu2_read_buffer => su32_base(24 downto 23),
            i_queue_empty => s_empty,
            i_queue_overflow => s_overflow,
            o_capture_enable => s_capture,
            o_flush_queue => s_flush,
            o_framebuffer_valid => s_frame_valid,
            o_discard_frame => s_discard,
            ou3_valid_buffers => su3_valid_buffers
        );
    publication_scoreboard : process
        type t_counts is array(0 to 2) of natural range 0 to GINT_VISIBLE_WIDTH * GINT_VISIBLE_HEIGHT;
        variable vint_counts : t_counts := (others => 0);
        variable vint_slot : natural;
    begin
        wait until falling_edge(s_clk);
        if (s_raw_write = '1' and su64_raw_data(15 downto 0) = 0) then
            vint_counts(to_integer(su29_raw_address(21 downto 20))) := 0;
        end if;
        if (s_write = '1') then
            assert (s_busy = '0') report "Publication wrote while DDR busy" severity failure;
            vint_slot := to_integer(su29_word_address(21 downto 20));
            assert (vint_counts(vint_slot) < GINT_VISIBLE_WIDTH * GINT_VISIBLE_HEIGHT)
                report "Publication scoreboard saw excess DDR pixels" severity failure;
            vint_counts(vint_slot) := vint_counts(vint_slot) + 1;
        end if;
        if (s_frame_valid = '1') then
            assert (vint_counts(to_integer(su32_base(24 downto 23))) = GINT_VISIBLE_WIDTH * GINT_VISIBLE_HEIGHT)
                report "Published framebuffer before all DDR pixel writes" severity failure;
            s_publication_seen <= '1';
        end if;
    end process;
''' + marker)
marker = '                    report "HDMI_ROTATION_BUFFERS_PASS frames="'
assert text.count(marker) == 1
text = text.replace(marker, '''                    assert (s_publication_seen = '1' and s_empty = '1')
                        report "No complete framebuffer published or queue not drained" severity failure;
''' + marker)
bench = root / 'debug/hdmi_rotation_publication_tb.vhd'
bench.write_text(text, encoding='utf-8')
sources = [netlist, 'rtl/rabbitpunch_ddr_write_queue.vhd', 'rtl/rabbitpunch_frame_publication.vhd', bench.relative_to(root).as_posix()]
hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
libraries = [item for name in ('cyclonev_ver', 'altera_ver', 'altera_lnsim_ver', 'lpm_ver', 'sgate_ver')
             for item in ('-L', name)]
geometry = ['-gGINT_VISIBLE_WIDTH=288', '-gGINT_VISIBLE_HEIGHT=216', '-gGINT_TOTAL_WIDTH=432',
            '-gGINT_TOTAL_HEIGHT=256', '-gGINT_HORIZONTAL_SYNC_START=352', '-gGINT_HORIZONTAL_SYNC_END=392',
            '-gGINT_VERTICAL_SYNC_START=232', '-gGINT_VERTICAL_SYNC_END=240']
results = []
for full, direction in [(False, False), (False, True)] + ([(True, False), (True, True)] if args.full else []):
    name = 'rotation_publication_' + ('ccw' if direction else 'cw') + ('_full' if full else '')
    result = run_case(name, sources, 'hdmi_rotation_buffers_tb', '100 ms', 'HDMI_ROTATION_BUFFERS_PASS',
                      sim_args=libraries + ['-gGBOOL_COUNTERCLOCKWISE=' + str(direction).lower()] + (geometry if full else []), wall_timeout=600)
    assert hashes == {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
    result.update(rotation_fit_commit=proof['commit'], frames=3, counterclockwise=direction,
                  pixels=3 * (62208 if full else 128), source_sha256=hashes,
                  log_sha256=hashlib.sha256((root / result['log']).read_bytes()).hexdigest())
    results.append(result)
    (root / 'debug/hdmi_rotation_publication_partial_checks.json').write_text(json.dumps(results, indent=2) + '\n', encoding='utf-8')
(root / 'docs/reference/hdmi_rotation_publication_checks.json').write_text(json.dumps(dict(cases=results,
    template_sha256=hashlib.sha256(template.read_bytes()).hexdigest(),
    scope='Fitted isolated triple-buffer rotator plus actual VHDL queue/publication RTL. Three complete scored frames: exact addresses/colours/masks, no active read/write slot overlap, read-slot progress, repeated 96/64-clock DDR busy bursts, no overflow, and valid publication only after the advertised slot has received every DDR pixel. At least one complete image must be published and queue drained. Publication RTL not yet fitted; no actual loader mux, phase/frequency sweep, physical display or latency proof. Disconnected from production.'), indent=2) + '\n', encoding='utf-8')
