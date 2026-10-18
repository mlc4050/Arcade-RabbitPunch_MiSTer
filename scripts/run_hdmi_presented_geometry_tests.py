# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Check rotated integer metadata when analog presentation has been doubled."""
import argparse
import json
from coretools import core_root
from crt_hq_reference import LIBRARIES, sha256
from run_baselines import run_case

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--expect-rejection', action='store_true')
args = parser.parse_args()
root = core_root()
sources = []
for name in ('hdmi_rotation', 'video_aspect'):
    proof = json.loads((root / 'docs/reference' / (name + '_netlist_checks.json')).read_text())
    netlist = 'debug/netlists/' + name + '_' + proof['commit'][:7] + '/' + name + '_check.vo'
    assert sha256(root / netlist) == proof['netlist_sha256']
    sources.append(netlist)
text = (root / 'sim/video/hdmi_presentation_control_tb.vhd').read_text()
marker = '    signal su13_reference_x, su13_reference_y : unsigned(12 downto 0);'
assert text.count(marker) == 1
text = text.replace(marker, marker + '''
    signal sint_presented_x : natural range 0 to 95 := 0;
    signal sint_presented_y : natural range 0 to 55 := 0;
    signal s_presented_enable, s_presented_sync, s_presented_data : std_logic;
''')
marker = "    s_data_enable <= '1' when sint_x < 32 and sint_y < 20 else '0';"
text = text.replace(marker, marker + '''
    -- 2x horizontal and vertical geometry, four enables per native /7 cycle.
    s_presented_enable <= '1' when sint_phase = 0 or sint_phase = 2 or
        sint_phase = 4 or sint_phase = 6 else '0';
    s_presented_sync <= '1' when sint_presented_y >= 48 and sint_presented_y < 52 else '0';
    s_presented_data <= '1' when sint_presented_x < 64 and sint_presented_y < 40 else '0';
    doubled_raster : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            if (s_presented_enable = '1') then
                if (sint_presented_x = 95) then
                    sint_presented_x <= 0;
                    if (sint_presented_y = 55) then
                        sint_presented_y <= 0;
                    else
                        sint_presented_y <= sint_presented_y + 1;
                    end if;
                else
                    sint_presented_x <= sint_presented_x + 1;
                end if;
            end if;
        end if;
    end process;
''')
for formal, old, new in [('pixel_enable', 's_enable', 's_presented_enable'),
                         ('vertical_sync', 's_vertical_sync', 's_presented_sync'),
                         ('data_enable', 's_data_enable', 's_presented_data')]:
    text = text.replace('i_presented_' + formal + ' => ' + old, 'i_presented_' + formal + ' => ' + new)
start = text.index('    stimulus : process\n')
text = text[:start] + '''    stimulus : process
    begin
        su12_hdmi_width <= to_unsigned(1900, 12);
        su12_hdmi_height <= to_unsigned(1080, 12);
        su3_scale <= to_unsigned(0, 3);
        for vint_direction in 1 to 2 loop
            su2_rotation_request <= to_unsigned(vint_direction, 2);
            for vint_frame in 1 to 5 loop
                wait until rising_edge(s_vertical_sync);
            end loop;
            wait until falling_edge(s_clk);
            assert (su2_applied = vint_direction) report "Doubled fixture rotation did not latch" severity failure;
            for vint_mode in 1 to 4 loop
                su3_scale <= to_unsigned(vint_mode, 3);
                for vint_cycle in 1 to 4000 loop
                    wait until falling_edge(s_clk);
                end loop;
                assert (su13_aspect_x = su13_reference_y and su13_aspect_y = su13_reference_x)
                    report "Rotated metadata used doubled analog geometry rather than native framebuffer: mode=" &
                        integer'image(vint_mode) & " actual=" & integer'image(to_integer(su13_aspect_x)) &
                        "," & integer'image(to_integer(su13_aspect_y)) & " expected=" &
                        integer'image(to_integer(su13_reference_y)) & "," & integer'image(to_integer(su13_reference_x))
                    severity failure;
            end loop;
        end loop;
        report "HDMI_PRESENTED_GEOMETRY_PASS directions=2 integer_modes=4 native=32x20 presented=64x40";
        finish;
    end process;
end architecture;
'''
bench = root / 'debug/hdmi_presented_geometry_tb.vhd'
bench.write_text(text)
sources += ['rtl/rabbitpunch_ddr_write_queue.vhd', 'rtl/rabbitpunch_frame_publication.vhd',
            'rtl/rabbitpunch_rotation_transport.vhd', 'rtl/rabbitpunch_hdmi_presentation.vhd', bench.relative_to(root).as_posix()]
hashes = {name: sha256(root / name) for name in sources}
name = 'hdmi_presented_geometry_rejected' if args.expect_rejection else 'hdmi_presented_geometry'
try:
    result = run_case(name, sources, 'hdmi_presentation_control_tb', '5 ms',
                      'HDMI_PRESENTED_GEOMETRY_PASS', sim_args=LIBRARIES, wall_timeout=600)
except SystemExit as error:
    transcript = root / 'debug/baselines' / name / 'result.log'
    if not args.expect_rejection or not transcript.exists() or 'Rotated metadata used doubled analog geometry' not in transcript.read_text():
        raise
    result = dict(case=name, expected_rejection=True, error=str(error), log=transcript.relative_to(root).as_posix())
else:
    if args.expect_rejection:
        raise SystemExit('Expected doubled-geometry regression was not reproduced')
assert hashes == {name: sha256(root / name) for name in sources}
result.update(source_sha256=hashes, log_sha256=sha256(root / result['log']),
              scope='Complete controller RTL with qualified rotation/aspect netlists, native 32x20 /7 raster and independently doubled 64x40 analog presentation, both directions and four integer modes versus independent native transposed aspect. Synthetic geometry seam, not actual effects or hardware.')
(root / 'docs/reference' / (name + '_checks.json')).write_text(json.dumps(result, indent=2) + '\n')
print('PASS expected geometry rejection' if args.expect_rejection else 'PASS rotated geometry selection')

