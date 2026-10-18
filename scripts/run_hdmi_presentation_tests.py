# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Check the complete HDMI controller around qualified donor/aspect netlists."""
import argparse
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--full', action='store_true')
args = parser.parse_args()
root = core_root()
rotation = json.loads((root / 'docs/reference/hdmi_rotation_netlist_checks.json').read_text(encoding='utf-8'))
aspect = json.loads((root / 'docs/reference/video_aspect_netlist_checks.json').read_text(encoding='utf-8'))
netlists = ['debug/netlists/hdmi_rotation_' + rotation['commit'][:7] + '/hdmi_rotation_check.vo',
            'debug/netlists/video_aspect_' + aspect['commit'][:7] + '/video_aspect_check.vo']
for path, proof in zip(netlists, (rotation, aspect)):
    assert hashlib.sha256((root / path).read_bytes()).hexdigest() == proof['netlist_sha256']
template = root / 'sim/video/hdmi_rotation_buffers_tb.vhd'
text = template.read_text(encoding='utf-8')
marker = 'begin\n    s_clk <='
assert text.count(marker) == 1
text = text.replace(marker, '''    signal s_initialize : std_logic := '1';
    signal s_busy, s_read, s_force_blank, s_rotated, s_queue_empty, s_overflow : std_logic;
    signal s_publication_seen : std_logic := '0';
    signal su13_aspect_x, su13_aspect_y : unsigned(12 downto 0);
    signal su2_requested, su2_applied : unsigned(1 downto 0);
    signal sint_stall_phase : natural range 0 to 511 := 0;
begin
    s_initialize <= '0' after 30 ns;
    su2_requested <= to_unsigned(2, 2) when GBOOL_COUNTERCLOCKWISE else to_unsigned(1, 2);
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
    assert (s_overflow /= '1' and s_read /= '1') report "HDMI presentation overflowed or issued a read" severity failure;
    s_clk <=''')
start = text.index('    dut : entity work.rabbitpunch_hdmi_rotation')
end = text.index('    monitor : process', start)
text = text[:start] + '''    dut : entity work.rabbitpunch_hdmi_presentation
        generic map (
            GINT_FRAME_PIXELS => GINT_VISIBLE_WIDTH * GINT_VISIBLE_HEIGHT
        )
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_game_ready => '1',
            i_loader_active => '0',
            i_direct_video => '0',
            iu2_rotation => su2_requested,
            i_native_pixel_enable => s_pixel_enable,
            iu8_native_red => su8_red,
            iu8_native_green => su8_green,
            iu8_native_blue => su8_blue,
            i_native_horizontal_sync_n => not s_horizontal_sync,
            i_native_vertical_sync_n => not s_donor_vertical_sync,
            i_native_data_enable => s_data_enable,
            i_presented_pixel_enable => s_pixel_enable,
            i_presented_vertical_sync => s_donor_vertical_sync,
            i_presented_data_enable => s_data_enable,
            iu12_hdmi_width => to_unsigned(1920, 12),
            iu12_hdmi_height => to_unsigned(1080, 12),
            iu2_aspect => to_unsigned(0, 2),
            iu3_scale => to_unsigned(0, 3),
            ou13_aspect_x => su13_aspect_x,
            ou13_aspect_y => su13_aspect_y,
            i_framebuffer_vertical_blank => s_framebuffer_blank,
            o_framebuffer_enable => s_enabled,
            o_framebuffer_force_blank => s_force_blank,
            ou5_framebuffer_format => su5_format,
            ou12_framebuffer_width => su12_width,
            ou12_framebuffer_height => su12_height,
            ou32_framebuffer_base => su32_base,
            ou14_framebuffer_stride => su14_stride,
            o_rotation_active => s_rotated,
            ou2_applied_rotation => su2_applied,
            o_discard_frame => open,
            o_queue_overflow => s_overflow,
            o_queue_empty => s_queue_empty,
            iu8_loader_burst_count => to_unsigned(1, 8),
            iu29_loader_word_address => to_unsigned(0, 29),
            iu64_loader_write_data => to_unsigned(0, 64),
            iu8_loader_byte_enables => to_unsigned(0, 8),
            i_loader_read => '0',
            i_loader_write => '0',
            o_loader_busy => open,
            o_loader_read_valid => open,
            ou64_loader_read_data => open,
            i_ddr_busy => s_busy,
            i_ddr_read_valid => '0',
            iu64_ddr_read_data => to_unsigned(0, 64),
            ou8_ddr_burst_count => su8_burst_count,
            ou29_ddr_word_address => su29_word_address,
            ou64_ddr_write_data => su64_data,
            ou8_ddr_byte_enables => su8_byte_enables,
            o_ddr_read => s_read,
            o_ddr_write => s_write
        );
    publication_scoreboard : process
        type t_counts is array(0 to 2) of natural range 0 to GINT_VISIBLE_WIDTH * GINT_VISIBLE_HEIGHT;
        variable vint_counts : t_counts := (others => 0);
        variable vint_slot : natural;
    begin
        wait until falling_edge(s_clk);
        if (s_write = '1') then
            assert (s_busy = '0') report "HDMI controller wrote while DDR busy" severity failure;
            vint_slot := to_integer(su29_word_address(21 downto 20));
            if (su64_data(16 downto 0) = 0) then
                vint_counts(vint_slot) := 0;
            end if;
            assert (vint_counts(vint_slot) < GINT_VISIBLE_WIDTH * GINT_VISIBLE_HEIGHT)
                report "HDMI controller emitted excess DDR pixels" severity failure;
            vint_counts(vint_slot) := vint_counts(vint_slot) + 1;
        end if;
        if (s_enabled = '1' and s_force_blank = '0') then
            assert (vint_counts(to_integer(su32_base(24 downto 23))) = GINT_VISIBLE_WIDTH * GINT_VISIBLE_HEIGHT)
                report "HDMI controller published before a complete DDR image" severity failure;
            s_publication_seen <= '1';
        end if;
        if (sint_frames >= 3) then
            assert (su2_applied = su2_requested and s_rotated = '1' and su13_aspect_x = 3 and su13_aspect_y = 4)
                report "HDMI rotation mode or portrait aspect mismatch" severity failure;
        end if;
    end process;
''' + text[end:]
marker = '                    report "HDMI_ROTATION_BUFFERS_PASS frames="'
assert text.count(marker) == 1
text = text.replace(marker, '''                    assert (s_publication_seen = '1' and s_queue_empty = '1')
                        report "HDMI controller did not publish/drain a complete image" severity failure;
''' + marker).replace('HDMI_ROTATION_BUFFERS_PASS', 'HDMI_PRESENTATION_PASS')
bench = root / 'debug/hdmi_presentation_tb.vhd'
bench.write_text(text, encoding='utf-8')
sources = netlists + ['rtl/rabbitpunch_ddr_write_queue.vhd', 'rtl/rabbitpunch_frame_publication.vhd',
    'rtl/rabbitpunch_rotation_transport.vhd', 'rtl/rabbitpunch_hdmi_presentation.vhd', bench.relative_to(root).as_posix()]
hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
libraries = [item for name in ('cyclonev_ver', 'altera_ver', 'altera_lnsim_ver', 'lpm_ver', 'sgate_ver') for item in ('-L', name)]
geometry = ['-gGINT_VISIBLE_WIDTH=288', '-gGINT_VISIBLE_HEIGHT=216', '-gGINT_TOTAL_WIDTH=432',
            '-gGINT_TOTAL_HEIGHT=256', '-gGINT_HORIZONTAL_SYNC_START=352', '-gGINT_HORIZONTAL_SYNC_END=392',
            '-gGINT_VERTICAL_SYNC_START=232', '-gGINT_VERTICAL_SYNC_END=240']
results = []
for full, direction in [(False, False), (False, True)] + ([(True, False), (True, True)] if args.full else []):
    result = run_case('hdmi_presentation_' + ('ccw' if direction else 'cw') + ('_full' if full else ''), sources,
        'hdmi_rotation_buffers_tb', '100 ms', 'HDMI_PRESENTATION_PASS', sim_args=libraries +
        ['-gGBOOL_COUNTERCLOCKWISE=' + str(direction).lower()] + (geometry if full else []), wall_timeout=1800)
    assert hashes == {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
    result.update(counterclockwise=direction, frames=3, pixels=3 * (62208 if full else 128), source_sha256=hashes,
                  log_sha256=hashlib.sha256((root / result['log']).read_bytes()).hexdigest())
    results.append(result)
    (root / 'debug/hdmi_presentation_partial_checks.json').write_text(json.dumps(results, indent=2) + '\n', encoding='utf-8')
(root / 'docs/reference/hdmi_presentation_checks.json').write_text(json.dumps(dict(cases=results,
    template_sha256=hashlib.sha256(template.read_bytes()).hexdigest(),
    scope='Complete HDMI controller RTL around qualified rotation/aspect netlists and actual transport/queue/publication RTL. Three scored frames per CW/CCW case: every pixel address/colour/mask, slot safety/progress, queue drain, positive sync normalization, frame-latched mode, 3:4 normal aspect and complete-image publication under bounded DDR stalls. Not a full-shell fit, live mode-transition/integer-size test, executing game, arbitrary FB phase/frequency or hardware/latency proof.'), indent=2) + '\n', encoding='utf-8')
