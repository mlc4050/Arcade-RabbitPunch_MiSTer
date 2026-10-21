# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Qualify state host command admission and final-save slot feedback."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import shutil
import xml.etree.ElementTree as ET
from coretools import core_root, NO_WINDOW
from hwlock import require_no_jtag


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ghdl', required=True)
    parser.add_argument('--label', required=True)
    parser.add_argument('--partial', action='store_true')
    parser.add_argument('--joystick', action='store_true')
    args = parser.parse_args()
    assert args.label.replace('_', '').isalnum()
    require_no_jtag('RabbitPunch state host controls test')
    root = core_root()
    assert not (args.partial and args.joystick)
    case = 'state_controls_'+('joystick_' if args.joystick else 'partial_' if args.partial else '')+args.label
    out = root/'debug/ghdl'/case
    assert not out.exists(), 'Preserve previous attempts'
    out.mkdir(parents=True)
    bench = 'state_controls_joystick_tb' if args.joystick else 'state_controls_partial_tb' if args.partial else 'state_controls_tb'
    marker = 'STATE_CONTROLS_JOYSTICK_PASS' if args.joystick else 'STATE_CONTROLS_PARTIAL_PASS' if args.partial else 'STATE_CONTROLS_PASS'
    sources = ['rtl/rabbitpunch_config.vhd', 'rtl/state/rabbitpunch_state_config.vhd',
               'rtl/state/rabbitpunch_state_controls.vhd', 'sim/state/'+bench+'.vhd']
    mapping = {}
    if args.joystick:
        for name in ('Rabbit Punch (US)', 'Rabio Lepus (Japan)'):
            for relative in ('releases/'+name+'.mra', 'releases/_alternatives/_ddr/'+name+' - DDR load.mra'):
                buttons = ET.parse(root/relative).getroot().find('buttons')
                assert buttons.attrib['names'].split(',') == [
                    'Fire/Punch', 'Missile', '-', '-', '-', '-', 'Start',
                    'Coin', 'Pause', 'Service', 'Test', 'Savestate (SS)']
                assert buttons.attrib['count'] == '2' and 'default' not in buttons.attrib
                mapping[relative] = dict(sha256=hashlib.sha256((root/relative).read_bytes()).hexdigest(),
                                         savestate_joystick_bit=15, existing_action_positions_preserved=True)
    hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    for name in sources:
        target = out/'inputs'/name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root/name, target)
    (out/'attempt.json').write_text(json.dumps(dict(accepted=False,
        source_sha256=hashes, runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()), indent=2)+'\n')
    logs = []
    for command in [[args.ghdl, '-a', '--std=08', '--workdir='+str(out), *[str(out/'inputs'/name) for name in sources]],
                    [args.ghdl, '--elab-run', '--std=08', '--workdir='+str(out),
                     bench, '--assert-level=error', '--stop-time=1ms']]:
        result = subprocess.run(command, cwd=root, text=True, capture_output=True, timeout=30, **NO_WINDOW)
        logs.append(result.stdout+result.stderr)
        (out/'result.log').write_text('\n'.join(logs), encoding='utf-8', newline='\n')
        assert result.returncode == 0, logs[-1][-6000:]
    assert marker in logs[-1]
    assert hashes == {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in hashes}
    result = dict(accepted=True, source_sha256=hashes,
        controller_mappings=mapping,
        runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        log_sha256=hashlib.sha256((out/'result.log').read_bytes()).hexdigest(),
        scope=('Controller SS+Left/Right selects the shared OSD slot with wrap and acknowledged feedback; SS+Down/Up and OSD share operation admission, selected slot, '
              'final-successful-save autoincrement and host feedback ticket. Both controllers, '
              'held/unavailable edges, cross-controller isolation and partial-restore retries; '
              'game-action suppression function preserves legacy disabled behavior. Synthetic '
              'service/host endpoints; no actual controller hardware, hps_io or whole-shell proof.' if args.joystick else
              'Partial-apply service hold with restore-only readiness. Reject SAVE without '
              'a pending UI ticket; admit RESTORE with the rejected SAVE held; no deferred '
              'SAVE or slot increment on recovery. Synthetic service/host endpoints; '
              'no actual hps_io, full apply engine, OSD rendering or hardware.' if args.partial else
              'State control module with synthetic service and host endpoints. '
              'All four slots/wrap, final-successful-save-only increment, failures, '
              'restore, no-auto, host slot/auto edits during transfer, held buttons, '
              'unavailable edge discard, simultaneous priority, reset/stray completion, '
              'default-disabled outputs, exact disabled configuration and enabled '
              'configuration header/order/separators/unique controls. No actual hps_io, OSD visibility, DDR '
              'publication, whole-game restore, FPGA or hardware qualification.'))
    (root/('docs/reference/'+case+'_checks.json')).write_text(json.dumps(result, indent=2)+'\n')
    print(logs[-1], end='')


if __name__ == '__main__':
    main()
