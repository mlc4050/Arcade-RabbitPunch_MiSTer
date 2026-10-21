# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Compare native and exported real presentation with a constant rotation input."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil

from coretools import core_root
from run_baselines import run_case
from run_state_game_diagnostic import require_window, run


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    assert args.label.replace('_', '').isalnum()
    require_window()
    root = core_root()
    name = 'state_presentation_constant_'+args.label
    out = root/'debug'/name
    assert not out.exists(), 'Preserve earlier attempts'
    out.mkdir(parents=True)
    proof = json.loads((root/'docs/reference/state_hdmi_presentation_netlists_v4_checks.json').read_text())
    assert proof['accepted']
    netlists = ['debug/netlists/hdmi_rotation_8238d77/hdmi_rotation_check.vo',
                'debug/netlists/video_aspect_80527a6/video_aspect_check.vo']
    imports = ['rtl/rabbitpunch_hdmi_rotation.vhd', 'rtl/rabbitpunch_video_aspect.vhd',
               'rtl/video/rotation/screen_rotate_two.sv', 'sys/video_freak.sv', 'sys/math.sv']
    for source in netlists+imports:
        assert sha(root/source) == proof['source_sha256'][source], source
    composition = ['rtl/rabbitpunch_ddr_write_queue.vhd', 'rtl/rabbitpunch_frame_publication.vhd',
        'rtl/state/rabbitpunch_state_ddr_arbiter.vhd',
        'rtl/state/rabbitpunch_state_rotation_transport.vhd',
        'rtl/state/rabbitpunch_state_hdmi_presentation.vhd',
        'sim/state/state_presentation_constant_eval.vhd']
    bench = 'sim/state/state_presentation_constant_tb.vhd'
    driver = 'sim/fast/state_presentation_constant_transport.cpp'
    sources = netlists+imports+composition+[bench, driver]
    hashes = {source: sha(root/source) for source in sources}
    for source in sources:
        target = out/'inputs'/source
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root/source, target)
    libraries = [item for lib in ('cyclonev_ver', 'altera_ver', 'altera_lnsim_ver', 'lpm_ver', 'sgate_ver')
                 for item in ('-L', lib)]
    native = run_case(name, netlists+composition+[bench], 'state_presentation_constant_tb',
        '2 ms', 'STATE_PRESENTATION_CONSTANT_PASS', sim_args=libraries, wall_timeout=300)
    tools = Path('D:/git/Arcade-RabbitPunch_MiSTer/.local/tools')
    suite = tools/'oss-cad-suite-20261018/oss-cad-suite'
    dev = tools/'w64devkit-2.10.1/w64devkit/bin'
    env = dict(os.environ)
    env['PATH'] = ';'.join((str(dev), str(suite/'bin'), str(suite/'lib'), env['PATH']))
    env['VERILATOR_ROOT'] = (suite/'share/verilator').as_posix()
    env['CCACHE_DISABLE'] = '1'
    vhdl = [str(out/'inputs'/source) for source in imports+composition if source.endswith('.vhd')]
    exported = run([str(tools/'ghdl-6.0.0/bin/ghdl.exe'), '--synth', '--std=08', '--out=verilog']+
                   vhdl+['-e', 'state_presentation_constant_eval'], out, 'export', 120, env)
    (out/'fixture.v').write_text(exported.stdout, newline='\n')
    sv = [str(out/'inputs'/source) for source in imports if source.endswith('.sv')]
    command = [str(suite/'bin/verilator_bin.exe'), '--cc', '--exe', str(out/'inputs'/driver),
        '--assert', '--no-assert-case', '-Wno-fatal', '--no-timing', '--timescale', '1ps/1ps',
        '--top-module', 'state_presentation_constant_eval', '--Mdir', str(out/'obj'),
        '-o', 'sim.exe', '-CFLAGS', '-O2 -DVL_USER_FATAL', str(out/'fixture.v')]+sv
    run([part.replace('\\', '/') for part in command], out, 'verilate', 120, env)
    run([str(dev/'make.exe'), '-C', str(out/'obj'), '-f', 'Vstate_presentation_constant_eval.mk', '-j2'],
        out, 'build', 300, env)
    run([str(out/'obj/sim.exe')], out, 'run', 60, env)
    baseline = root/'debug/baselines'/name/'constant_result.txt'
    native_result = [int(field) for field in baseline.read_text().split()]
    actual = [int(field) for field in (out/'constant_result.txt').read_text().split()]
    assert hashes == {source: sha(root/source) for source in sources}
    report = dict(accepted=native_result == actual, native_result=native_result, exported_result=actual,
        fields=['applied_rotation', 'DDR_writes', 'ever_unblanked'], native=native,
        source_sha256=hashes, runner_sha256=sha(Path(__file__)),
        native_result_sha256=sha(baseline), exported_result_sha256=sha(out/'constant_result.txt'),
        raw_export_sha256=sha(out/'fixture.v'), executable_sha256=sha(out/'obj/sim.exe'),
        scope='Constant clockwise input on the actual presentation composition with a '
              '32x20 raster and 16 frames. Native uses the qualified unchanged donor '
              'functional netlists; export uses raw unchanged donor RTL. VHDL owns '
              'raster, completion and counters; C++ only supplies clock/initialization '
              'and observes public outputs. No export normalization, internal state '
              'deposits, complete game, physical DDR or hardware result.')
    (out/'comparison.json').write_text(json.dumps(report, indent=2)+'\n', newline='\n')
    if not report['accepted']:
        raise SystemExit('Native/export constant presentation differs: '+str(native_result)+' / '+str(actual))
    (root/'docs/reference'/(name+'_checks.json')).write_text(json.dumps(report, indent=2)+'\n', newline='\n')
    print('PASS constant presentation native/export: '+str(actual))


if __name__ == '__main__':
    main()
