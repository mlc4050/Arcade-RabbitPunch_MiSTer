# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Analyze the experimental VHDL MiSTer boundary without substituting a PLL."""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
from pathlib import Path
from coretools import core_root, NO_WINDOW, modelsim_bin
from hwlock import require_no_jtag
from run_state_machine_backend_tests import state_machine_sources


def state_emu_sources():
    sources = [name for name in state_machine_sources()
               if name.startswith('rtl/')]
    sources += ['rtl/rabbitpunch_pll.vhd', 'rtl/rabbitpunch_reset_release.vhd', 'rtl/rabbitpunch_host.vhd',
        'rtl/rabbitpunch_crt_adjust.vhd', 'rtl/rabbitpunch_video_options.vhd',
        'rtl/rabbitpunch_video_aspect.vhd', 'rtl/rabbitpunch_status_led.vhd',
        'rtl/rabbitpunch_hdmi_rotation.vhd', 'rtl/rabbitpunch_ddr_write_queue.vhd',
        'rtl/rabbitpunch_frame_publication.vhd', 'rtl/state/rabbitpunch_state_ddr_arbiter.vhd',
        'rtl/state/rabbitpunch_state_rotation_transport.vhd', 'rtl/state/rabbitpunch_state_hdmi_presentation.vhd',
        'rtl/state/rabbitpunch_state_abi.vhd', 'rtl/state/rabbitpunch_state_config.vhd',
        'rtl/state/rabbitpunch_state_controls.vhd', 'rtl/rabbitpunch_debug.vhd',
        'rtl/state/rabbitpunch_state_build.vhd', 'rtl/state/rabbitpunch_state_emu.vhd',
        'rtl/state/rabbitpunch_state_emu_boundary.vhd']
    sources += ['rtl/video/crt_adjust/crt_adjust.sv', 'rtl/video/rotation/screen_rotate_two.sv']
    assert len(sources) == len(set(sources))
    return sources


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    assert args.label.replace('_', '').isalnum()
    require_no_jtag('State MiSTer VHDL source analysis')
    root = core_root()
    out = root/'debug/baselines'/('state_emu_sources_'+args.label)
    assert not out.exists(), 'Preserve previous attempts'
    out.mkdir(parents=True)
    # Verify the unchanged framework ABI for this explicit macro combination.
    active = [True]
    pins = {}
    for line in (root/'sys/emu_ports.vh').read_text().splitlines():
        line = line.split('//')[0].strip()
        if line.startswith('`ifdef '):
            active.append(active[-1] and line.split()[1] == 'MISTER_FB')
        elif line == '`endif':
            active.pop()
        elif active[-1]:
            match = re.fullmatch(r'(input|output|inout)\s*(?:\[(\d+):0\])?\s*(\w+),?', line)
            if match:
                direction, high, name = match.groups()
                pins[name] = ({'input': 'in', 'output': 'out', 'inout': 'inout'}[direction],
                              int(high)+1 if high else 1)
    assert len(active) == 1 and len(pins) == 81
    bridge = (root/'rtl/state/rabbitpunch_state_emu_boundary.vhd').read_text()
    actual = {}
    for name, direction, kind in re.findall(r'^        (\w+) : (in|out|inout) (std_logic|unsigned\(\d+ downto 0\))', bridge, re.M):
        actual[name] = (direction, 1 if kind == 'std_logic' else int(re.search(r'\d+', kind)[0])+1)
    assert actual == pins, 'Framework ABI differs'
    enabled = 'GBOOL_ENABLE_STATES => true'
    disabled = 'GBOOL_ENABLE_STATES => false'
    assert bridge.count(enabled)+bridge.count(disabled) == 1
    controls_enabled = enabled in bridge
    production_state_sources = 'rtl/state/rabbitpunch_state_emu_boundary.vhd' in (root/'files.qip').read_text()
    assert controls_enabled == production_state_sources, 'Production source list and state-control gate differ'
    donors = ['rtl/state/vendor/meatsauce_t80/'+name+'.vhd' for name in
              ('T80_Reg', 'T80_MCode', 'T80_ALU', 'T80')]
    sources = [name for name in state_emu_sources() if name.endswith('.vhd')]
    hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in donors+sources}
    tools = modelsim_bin()
    ini = out/'modelsim.ini'
    shutil.copyfile(Path(os.environ['MODELSIM']), ini)
    env = os.environ.copy()
    env['MODELSIM'] = str(ini)
    logs = []
    commands = []
    for library in ('state_t80', 'work'):
        commands += [[str(tools/'vlib.exe'), library],
                     [str(tools/'vmap.exe'), library, str(out/library)]]
    for library, group in [('state_t80', donors), ('work', sources)]:
        # Use the production runner's one-file invocations. This installed
        # compiler exits with C0000374 on a batch spanning both generated
        # sound models and the legacy T80; retain that rejected batch log.
        for name in group:
            commands.append([str(tools/'vcom.exe'), '-2008', '-work', library, str(root/name)])
    for command in commands:
        result = subprocess.run(command, cwd=out, env=env, text=True, capture_output=True, timeout=180, **NO_WINDOW)
        logs.append(dict(command=command, returncode=result.returncode,
                         stdout=result.stdout, stderr=result.stderr))
        (out/'commands.json').write_text(json.dumps(logs, indent=2)+'\n', encoding='utf-8')
        assert result.returncode == 0, (result.stdout+result.stderr)[-8000:]
    assert hashes == {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in hashes}
    report = dict(analyzed=True, functional_qualification=False, source_sha256=hashes,
        state_controls_enabled=controls_enabled, production_state_sources=production_state_sources,
        compiler_sha256=hashlib.sha256((tools/'vcom.exe').read_bytes()).hexdigest(),
        private_modelsim_ini_sha256=hashlib.sha256(ini.read_bytes()).hexdigest(),
        framework_abi='MISTER_FB=1, MISTER_FB_PALETTE/MISTER_DUAL_SDRAM undefined',
        framework_abi_pins=len(pins), framework_header_sha256=hashlib.sha256((root/'sys/emu_ports.vh').read_bytes()).hexdigest(),
        scope='VHDL source analysis only, including the real PLL/RAM wrappers '
              'and installed vendor component declarations. No PLL replacement. Imported '
              'Verilog and framework components are not elaborated by this check. '
              'No actual HPS/DDR/video behavior, whole-game, FPGA or hardware proof.',
        runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
    (root/'docs/reference'/('state_emu_sources_'+args.label+'_checks.json')).write_text(json.dumps(report, indent=2)+'\n')
    print('ANALYZED state VHDL MiSTer composition;81 framework pins;controls enabled='+str(controls_enabled))


if __name__ == '__main__':
    main()
