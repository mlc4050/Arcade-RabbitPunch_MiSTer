# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Audit the advertised state vector of an unchanged JT51 savestate donor.

A completed audit is not a qualification: accepted is true only with zero
observable continuation differences, and one tone alone is not chip coverage.
"""
import hashlib
import json
import re
from coretools import core_root
from run_baselines import run_case


def main():
    root = core_root()
    vendor = root/'rtl/state/vendor/boogiewings_jt51'
    manifest = json.loads((vendor/'vendor_manifest.json').read_text())
    for item in manifest['files']:
        assert hashlib.sha256((root/item['target']).read_bytes()).hexdigest() == item['sha256'], item['target']
    sources = sorted(path.relative_to(root).as_posix() for path in vendor.glob('*.v'))
    sources += ['rtl/state/rabbitpunch_fm_state.vhd', 'sim/state/fm_state_audit_tb.vhd']
    hashes = {path: hashlib.sha256((root/path).read_bytes()).hexdigest() for path in sources}
    result = run_case('fm_state_audit', sources, 'fm_state_audit_tb', '11 ms',
                      'JT51_STATE_AUDIT_COMPLETE', wall_timeout=120,
                      sim_args=('-suppress', '8315', '-suppress', '8360'))
    assert hashes == {path: hashlib.sha256((root/path).read_bytes()).hexdigest() for path in sources}
    log = (root/result['log']).read_text()
    match = re.search(r'JT51_STATE_AUDIT_COMPLETE differences=\s*(\d+) late_differences=\s*(\d+)', log)
    assert match, 'Missing audit counts'
    differences, late = map(int, match.groups())
    result.update(accepted=differences == 0, differences=differences,
                  late_differences=late, trace_cycles=32768, source_sha256=hashes,
                  log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
                  scope='Native unchanged BoogieWings state-enabled JT51 donor. Enabled '
                  'clocks during long reset, initialized parameters and nonzero tone. '
                  'Advertised 2820-bit vector round trip plus restored enable phase; '
                  'full/status/sample/PCM trace checked, including after 4096 clocks. '
                  'No production replacement or general chip-state qualification.')
    (root/'docs/reference/fm_state_audit_checks.json').write_text(
        json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(f'AUDIT accepted={result["accepted"]} differences={differences} late={late}', flush=True)


if __name__ == '__main__':
    main()
