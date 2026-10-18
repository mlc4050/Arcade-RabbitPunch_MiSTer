# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Generate VHDL live-control cases from the established CRT image scoreboard."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case

root = core_root()
template_path = root / 'sim/video/crt_adjust_geometry_tb.vhd'
template = template_path.read_text()
old = """        wait until rising_edge(s_clk) and sint_frames = 2 and sint_y = GINT_TEST_FRAME_LINES - 2;
        s_score <= '1';"""
assert template.count(old) == 1
results = []
for name in ('live_controls', 'disable_reenable'):
    switch = """        wait until falling_edge(s_clk) and sint_frames = 1 and sint_y = 8;
"""
    if name == 'disable_reenable':
        switch += """        s_adjust <= '0';
        for vint_clock in 1 to 200 loop
            wait until falling_edge(s_clk);
            assert (su8_output_red = su8_red and su8_output_green = su8_green and
                su8_output_blue = su8_blue and s_output_enable = s_pixel_enable and
                s_output_hsync = s_hsync and s_output_vsync = s_vsync and
                s_output_hblank = s_hblank and s_output_vblank = s_vblank)
                report "Live CRT disable did not restore exact native bypass" severity failure;
        end loop;
"""
    switch += """        su5_size <= to_unsigned(30, 5);
        su7_position <= to_unsigned(89, 7);
        s_adjust <= '1';
        wait until rising_edge(s_clk) and sint_frames = 3 and sint_y = GINT_TEST_FRAME_LINES - 2;
        s_score <= '1';"""
    bench = template.replace(old, switch)
    bench_path = root / 'debug' / ('crt_' + name + '_tb.vhd')
    bench_path.write_text(bench)
    sources = ['rtl/video/crt_adjust/crt_adjust.sv', 'rtl/rabbitpunch_crt_adjust.vhd',
               bench_path.relative_to(root).as_posix()]
    hashes = {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in sources}
    result = run_case('crt_' + name, sources, 'crt_adjust_geometry_tb', '10 ms',
                      'CRT_ADJUST_GEOMETRY_PASS', sim_args=['-gGU5_HORIZONTAL_SIZE=00010',
                      '-gGU7_HORIZONTAL_POSITION=0001000'], wall_timeout=300)
    assert hashes == {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in sources}
    result.update(source_sha256=hashes, pixels=1728,
                  log_sha256=hashlib.sha256((root / result['log']).read_bytes()).hexdigest())
    results.append(result)
(root / 'docs/reference/crt_live_controls_checks.json').write_text(json.dumps(dict(
    cases=results, template_sha256=hashlib.sha256(template_path.read_bytes()).hexdigest(),
    scope='CRT RTL at 288/432 horizontal and 6/12 vertical geometry, /7 enables. Change from size +2/position +8 to size -2/position -8 in vertical blank, then exact source-order/sync scoreboard after two frames of settling. Second case also disables for 200 system clocks with every-clock native bypass checks, then reenables. No glitch-free setting transition, production-frame shift transition, combined-effects transition, extreme clipping or physical monitor proof.'), indent=2) + '\n')
