# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Full native rotation writes through the isolated DDR-busy queue."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
root = core_root()
fit = json.loads((root / 'debug/ddr_write_queue_synth.json').read_text())
assert fit['memory_bits'] == 51712
rotation = json.loads((root / 'docs/reference/hdmi_rotation_netlist_checks.json').read_text())
netlist = 'debug/netlists/hdmi_rotation_' + rotation['commit'][:7] + '/hdmi_rotation_check.vo'
assert hashlib.sha256((root / netlist).read_bytes()).hexdigest() == rotation['netlist_sha256']
template_path = root / 'sim/video/hdmi_rotation_tb.vhd'
template = template_path.read_text()
bench = template.replace('begin\n    s_clk <=', '''    signal s_initialize : std_logic := '1';
    signal s_raw_write, s_queue_busy, s_queue_full, s_queue_empty, s_queue_overflow : std_logic;
    signal su29_raw_address : unsigned(28 downto 0);
    signal su64_raw_data : unsigned(63 downto 0);
    signal su8_raw_bytes : unsigned(7 downto 0);
    signal sint_stall_phase : natural range 0 to 511 := 0;
begin
    s_initialize <= '0' after 30 ns;
    s_queue_busy <= '1' when sint_stall_phase < 96 or
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
    assert (s_queue_overflow /= '1') report "Queued rotation overflowed under bounded DDR stalls" severity failure;
    s_clk <=''')
assert bench != template
for old, new in [('ou29_ddr_word_address => su29_word_address','ou29_ddr_word_address => su29_raw_address'),
                 ('ou64_ddr_data => su64_data','ou64_ddr_data => su64_raw_data'),
                 ('ou8_ddr_byte_enables => su8_byte_enables','ou8_ddr_byte_enables => su8_raw_bytes'),
                 ('o_ddr_write => s_write','o_ddr_write => s_raw_write')]:
    assert bench.count(old) == 1
    bench = bench.replace(old, new)
bench = bench.replace('    monitor : process', '''    write_queue : entity work.rabbitpunch_ddr_write_queue
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_write => s_raw_write,
            iu29_word_address => su29_raw_address,
            iu64_data => su64_raw_data,
            iu8_byte_enables => su8_raw_bytes,
            o_full => s_queue_full,
            o_empty => s_queue_empty,
            o_overflow => s_queue_overflow,
            i_ddr_busy => s_queue_busy,
            o_ddr_write => s_write,
            ou29_ddr_word_address => su29_word_address,
            ou64_ddr_data => su64_data,
            ou8_ddr_byte_enables => su8_byte_enables
        );
    monitor : process''')
bench = bench.replace("if (s_write = '1') then", "if (s_write = '1') then\n                assert (s_queue_busy = '0') report \"Queued rotation wrote while DDR busy\" severity failure;")
bench = bench.replace('elsif (sint_frames = 4) then', 'elsif (sint_frames = 4) then\n            assert (s_queue_empty = \'1\') report "Queued rotation did not drain during blanking" severity failure;')
bench_path = root / 'debug/hdmi_rotation_queued_tb.vhd'
bench_path.write_text(bench)
sources = [netlist, 'rtl/rabbitpunch_ddr_write_queue.vhd', bench_path.relative_to(root).as_posix()]
hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
libraries = [item for name in ('cyclonev_ver','altera_ver','altera_lnsim_ver','lpm_ver','sgate_ver') for item in ('-L',name)]
geometry = ['-gGINT_VISIBLE_WIDTH=288','-gGINT_VISIBLE_HEIGHT=216','-gGINT_TOTAL_WIDTH=432',
            '-gGINT_TOTAL_HEIGHT=256','-gGINT_HORIZONTAL_SYNC_START=352','-gGINT_HORIZONTAL_SYNC_END=392',
            '-gGINT_VERTICAL_SYNC_START=232','-gGINT_VERTICAL_SYNC_END=240']
results = []
for direction in ('false', 'true'):
    result = run_case('rotation_queued_' + direction + '_full', sources, 'hdmi_rotation_tb', '100 ms',
                      'HDMI_ROTATION_PASS', sim_args=libraries + geometry + ['-gGBOOL_COUNTERCLOCKWISE=' + direction], wall_timeout=600)
    assert hashes == {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
    result.update(counterclockwise=direction == 'true', pixels=62208, source_sha256=hashes,
                  log_sha256=hashlib.sha256((root / result['log']).read_bytes()).hexdigest())
    results.append(result)
    (root / 'debug/hdmi_rotation_queue_partial_checks.json').write_text(json.dumps(results, indent=2) + '\n')
(root / 'docs/reference/hdmi_rotation_queue_checks.json').write_text(json.dumps(dict(cases=results,
    template_sha256=hashlib.sha256(template_path.read_bytes()).hexdigest(), queue_fit_commit=fit['commit'],
    scope='Fitted unchanged rotation netlist plus VHDL write queue. All 62208 nonuniform pixels, independent CW/CCW DDR addresses/byte masks/colour and buffer selection, under repeated 96- and 64-clock busy bursts in a 512-clock period. No overflow; queue drains before the next frame. No loader ownership, arbitrary-duration DDR stall safety, frame publication/latency or physical hardware proof; disconnected from production.'), indent=2) + '\n')
