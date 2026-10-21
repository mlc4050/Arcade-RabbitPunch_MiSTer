# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Qualify the unchanged STOP-aware GX capture donor behind VHDL boundaries."""
import hashlib
import json
import shutil
import argparse
from coretools import core_root
from run_baselines import run_case


def main():
    root = core_root()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--masked', action='store_true')
    args = parser.parse_args()
    manifest = json.loads((root/'rtl/state/vendor/konamigx/vendor_manifest.json').read_text())
    for item in manifest['files']:
        assert hashlib.sha256((root/item['target']).read_bytes()).hexdigest() == item['sha256'], item['target']
    name = 'm68k_capture_masked' if args.masked else 'm68k_capture'
    out = root/'debug/baselines'/name
    for filename in ('microrom.mem', 'nanorom.mem'):
        target = out/'rtl/cpu/fx68k'/filename
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root/'rtl/state/vendor/konamigx/fx68k'/filename, target)
    sources = ['rtl/state/vendor/konamigx/fx68k/'+filename for filename in
               ('fx68k.sv', 'fx68kAlu.sv', 'uaddrPla.sv')]
    sources += ['rtl/state/vendor/konamigx/gx_ss_m68k.sv',
                'rtl/state/rabbitpunch_state_fx68k.vhd',
                'rtl/state/rabbitpunch_m68k_capture.vhd',
                'rtl/state/rabbitpunch_capture_stack_undo.vhd',
                'sim/state/m68k_capture_tb.vhd']
    hashes = {path: hashlib.sha256((root/path).read_bytes()).hexdigest() for path in sources}
    sim_args = ['-suppress', '8315', '-suppress', '8360']
    if args.masked:
        sim_args += ['-gGINT_START_SR=9984']
    result = run_case(name, sources, 'm68k_capture_tb', '11 ms', 'M68K_CAPTURE_PASS',
                      sim_args=sim_args, wall_timeout=120)
    assert hashes == {path: hashlib.sha256((root/path).read_bytes()).hexdigest() for path in sources}
    result.update(source_sha256=hashes, initial_sr='2700' if args.masked else '2000',
                  log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
                  scope='Isolated unchanged GX fx68k/capture donor with new descriptive '
                  'VHDL boundaries and native VHDL bench. Three repeated 400-write '
                  'continuations and STOP recapture/resume, followed by normal IRQ wake. '
                  'Transactional old-word read/write and pre-IACK stack undo; original '
                  'stack sentinel preserved and journal validated against captured SSP-2. '
                  'No full-game, sound, DDR, OSD, synthesis or '
                  'hardware qualification; donor remains outside files.qip.')
    (root/('docs/reference/'+name+'_checks.json')).write_text(
        json.dumps(result, indent=2)+'\n', encoding='utf-8')


if __name__ == '__main__':
    main()
