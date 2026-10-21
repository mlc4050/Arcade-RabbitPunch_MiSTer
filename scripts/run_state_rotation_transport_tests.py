# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Qualify the actual presentation queue with shared state/loader DDR ownership."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from coretools import core_root, NO_WINDOW
from hwlock import require_no_jtag


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ghdl', required=True)
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    assert args.label.replace('_', '').isalnum()
    require_no_jtag('RabbitPunch state/presentation DDR native test')
    root = core_root()
    case = 'state_rotation_transport_'+args.label
    out = root/'debug/ghdl'/case
    assert not out.exists(), 'Preserve previous attempts'
    out.mkdir(parents=True)
    sources = ['rtl/rabbitpunch_ddr_write_queue.vhd', 'rtl/rabbitpunch_frame_publication.vhd',
        'rtl/state/rabbitpunch_state_ddr_arbiter.vhd', 'rtl/state/rabbitpunch_state_rotation_transport.vhd',
        'rtl/rabbitpunch_hdmi_rotation.vhd', 'rtl/rabbitpunch_video_aspect.vhd',
        'rtl/state/rabbitpunch_state_hdmi_presentation.vhd', 'sim/state/state_rotation_transport_tb.vhd']
    hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    logs = []
    for command in [[args.ghdl, '-a', '--std=08', '--workdir='+str(out), *sources],
                    [args.ghdl, '--elab-run', '--std=08', '--workdir='+str(out),
                     'state_rotation_transport_tb', '--assert-level=error']]:
        result = subprocess.run(command, cwd=root, text=True, capture_output=True, timeout=30, **NO_WINDOW)
        logs.append(result.stdout+result.stderr)
        (out/'result.log').write_text('\n'.join(logs), encoding='utf-8', newline='\n')
        assert result.returncode == 0, logs[-1][-6000:]
    log = '\n'.join(logs)
    assert 'STATE_ROTATION_TRANSPORT_PASS' in log, log
    assert hashes == {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in hashes}
    result = dict(accepted=True, source_sha256=hashes,
        runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        log_sha256=hashlib.sha256((out/'result.log').read_bytes()).hexdigest(),
        scope='Actual presentation queue/frame-publication/three-client DDR '
              'arbiter with synthetic four-pixel packets and delayed DDR responses. '
              'Loader priority/fields, discard and clean frame restart, state read '
              'debt across cancellation and presentation invalidation, continued '
              'state retry read/write while video held, and loader takeover only '
              'after canceled state response. Higher HDMI wrapper analyzed, '
              'not elaborated. No actual rotator/scaler, file loader, MiSTer '
              'DDR controller, whole-game restoration, FPGA or hardware qualification.')
    (root/('docs/reference/'+case+'_checks.json')).write_text(json.dumps(result, indent=2)+'\n')
    print(log, end='')


if __name__ == '__main__':
    main()
