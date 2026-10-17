# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Negative controls for full-build timing gates, using a real fitted report."""
import contextlib
import hashlib
import io
import json
from pathlib import Path
import re
from coretools import core_root
import build_staged

root = core_root()
archive = root / 'debug/fit_archive/clocked_machine_2374ddc'
summary = archive / 'clocked_machine_check.sta.summary'
report = archive / 'clocked_machine_check.sta.rpt'
scratch = root / 'debug/timing_gate_checks'
scratch.mkdir(parents=True, exist_ok=True)
checks = []

def expect(name, callback, fails):
    failure = None
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            result = callback()
        if result:
            failure = str(result)
    except SystemExit as error:
        failure = str(error)
    assert bool(failure) == fails, (name, failure)
    checks.append(dict(case=name, rejected=bool(failure)))

expect('accepted_full_summary', lambda: build_staged.read_slacks(summary), False)
expect('accepted_full_coverage', lambda: build_staged.check_timing_coverage(report), False)
expect('missing_summary', lambda: build_staged.read_slacks(scratch / 'absent.summary'), True)
expect('missing_coverage', lambda: build_staged.check_timing_coverage(scratch / 'absent.rpt'), True)
text = summary.read_text()
for check in ('Setup', 'Hold', 'Recovery', 'Removal', 'Minimum Pulse Width'):
    changed, count = re.subn(r'(Type\s*:\s*[^\n]*' + re.escape(check) + r'[^\n]*\nSlack\s*:\s*)[^\n]+', r'\g<1>-0.001', text, count=1)
    assert count == 1, check
    path = scratch / (check.replace(' ', '_') + '.summary')
    path.write_text(changed)
    expect('negative_' + check.replace(' ', '_'), lambda: build_staged.read_slacks(path), True)
empty = scratch / 'empty.summary';empty.write_text('No timing analyzed\n')
expect('empty_summary', lambda: build_staged.read_slacks(empty), True)
coverage_text = report.read_text()
for category in ('Illegal Clocks', 'Unconstrained Clocks', 'Unconstrained Input Ports',
                 'Unconstrained Input Port Paths', 'Unconstrained Output Ports', 'Unconstrained Output Port Paths'):
    changed, count = re.subn(r'(;\s*' + re.escape(category) + r'\s*;\s*)0(\s*;\s*)0(\s*;)', r'\g<1>0\g<2>1\g<3>', coverage_text, count=1)
    assert count == 1, category
    path = scratch / (category.replace(' ', '_') + '.rpt');path.write_text(changed)
    expect('hold_coverage_' + category.replace(' ', '_'), lambda: build_staged.check_timing_coverage(path), True)
missing = scratch / 'empty.rpt';missing.write_text('')
expect('empty_coverage', lambda: build_staged.check_timing_coverage(missing), True)
result = dict(checks=checks, reference_summary_sha256=hashlib.sha256(summary.read_bytes()).hexdigest(),
              reference_coverage_sha256=hashlib.sha256(report.read_bytes()).hexdigest(),
              script_sha256=hashlib.sha256((root / 'scripts/build_staged.py').read_bytes()).hexdigest(),
              scope='Real accepted Quartus report plus controlled missing/negative timing and coverage mutations; no compile or hardware claim')
(root / 'docs/reference/build_timing_gate_checks.json').write_text(json.dumps(result, indent=2) + '\n')
print(f'PASS full-build timing gates: {len(checks)} acceptance/negative controls')
