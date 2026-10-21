# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Test state flush and late DDR debt through the actual HDMI rotator."""
import argparse
import hashlib
import json
import subprocess

from coretools import core_root, NO_WINDOW
from run_baselines import run_case


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    assert args.label.replace('_', '').isalnum()
    root = core_root()
    name = 'state_hdmi_presentation_'+args.label
    assert not (root/'debug/baselines'/name).exists(), 'Preserve earlier attempts'
    def sha(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()
    proof = json.loads((root/'docs/reference/hdmi_rotation_netlist_checks.json').read_text())
    netlist = 'debug/netlists/hdmi_rotation_'+proof['commit'][:7]+'/hdmi_rotation_check.vo'
    assert sha(root/netlist) == proof['netlist_sha256']
    donor_sources = ('rtl/rabbitpunch_hdmi_rotation.vhd', 'rtl/video/rotation/screen_rotate_two.sv')
    for source in donor_sources:
        original = subprocess.check_output(['git', 'show', proof['commit']+':'+source], cwd=root, **NO_WINDOW)
        assert original.replace(b'\r\n', b'\n') == (root/source).read_bytes().replace(b'\r\n', b'\n'), source
    aspect_proof = json.loads((root/'docs/reference/video_aspect_netlist_checks.json').read_text())
    aspect_netlist = 'debug/netlists/video_aspect_'+aspect_proof['commit'][:7]+'/video_aspect_check.vo'
    assert sha(root/aspect_netlist) == aspect_proof['netlist_sha256']
    aspect_sources = ('rtl/rabbitpunch_video_aspect.vhd', 'sys/video_freak.sv', 'sys/math.sv')
    for source in aspect_sources:
        original = subprocess.check_output(['git', 'show', aspect_proof['commit']+':'+source], cwd=root, **NO_WINDOW)
        assert original.replace(b'\r\n', b'\n') == (root/source).read_bytes().replace(b'\r\n', b'\n'), source
    sources = [netlist, aspect_netlist,
        'rtl/rabbitpunch_ddr_write_queue.vhd', 'rtl/rabbitpunch_frame_publication.vhd',
        'rtl/state/rabbitpunch_state_ddr_arbiter.vhd',
        'rtl/state/rabbitpunch_state_rotation_transport.vhd',
        'rtl/state/rabbitpunch_state_hdmi_presentation.vhd',
        'sim/state/state_hdmi_presentation_tb.vhd']
    hashes = {source: sha(root/source) for source in sources+list(donor_sources)+list(aspect_sources)}
    libraries = [item for name in ('cyclonev_ver', 'altera_ver', 'altera_lnsim_ver', 'lpm_ver', 'sgate_ver') for item in ('-L', name)]
    result = run_case(name, sources, 'state_hdmi_presentation_tb', '5 ms',
                      'STATE_HDMI_PRESENTATION_PASS', sim_args=libraries, wall_timeout=300)
    assert hashes == {source: sha(root/source) for source in hashes}
    assert 'not bound' not in (root/result['log']).read_text(), 'All actual components must bind'
    result.update(accepted=True, source_sha256=hashes, runner_sha256=sha(root/'scripts/run_state_hdmi_presentation_tests.py'),
        log_sha256=sha(root/result['log']),
        rotation_netlist_receipt_sha256=sha(root/'docs/reference/hdmi_rotation_netlist_checks.json'),
        aspect_netlist_receipt_sha256=sha(root/'docs/reference/video_aspect_netlist_checks.json'),
        scope='Qualified Quartus functional netlist of the unchanged screen_rotate_two donor '
              'and descriptive VHDL wrapper; current source matches that fitted commit. '
              'Actual state RTL connects '
              'aspect, publication, queue and three-client state DDR arbiter. '
              'Synthetic 32x20 raster: retained native/custom/integer/direct mode checks; '
              'CW and CCW each publish a complete frame before midframe state flush, '
              'hold mode while flush spans VS, retire an accepted canceled state read '
              'to its original client, write state while presentation is held, and '
              'republish only after fresh capture. No full game, scaler, physical '
              'DDR controller, FPGA timing or hardware result is claimed.')
    (root/'docs/reference'/(name+'_checks.json')).write_text(json.dumps(result, indent=2)+'\n', newline='\n')


if __name__ == '__main__':
    main()
