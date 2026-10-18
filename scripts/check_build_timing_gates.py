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
# Full-shell scope remains explicit: all clocks timed, no SDRAM exception,
# inherited framework pin names/counts and unchanged sources are required.
import shutil
full_report = root / 'debug/fit_archive/full_shell_660a45a_phase10714_rejected/RabbitPunch.sta.rpt'
if full_report.exists():
    scope_file = root / 'scripts/framework_timing_scope.json'
    scope = json.loads(scope_file.read_text())
    stage = scratch / 'framework_stage'
    (stage / 'output_files').mkdir(parents=True, exist_ok=True)
    for name in scope['source_sha256']:
        target = stage / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root / name, target)
    expect('explicit_inherited_framework_scope',
           lambda: build_staged.check_timing_coverage(full_report, scope_file, stage), False)
    changed = scratch / 'unexpected_sdram_input.rpt'
    changed.write_text(full_report.read_text().replace('HDMI_TX_INT', 'SDRAM_DQ[0]'))
    expect('reject_untimed_sdram_pin',
           lambda: build_staged.check_timing_coverage(changed, scope_file, stage), True)
    changed = scratch / 'extra_framework_paths.rpt'
    text, count = re.subn(r'(;\s*Unconstrained Input Port Paths\s*;\s*)14(\s*;)',
                           r'\g<1>15\g<2>', full_report.read_text(), count=1)
    assert count == 1
    changed.write_text(text)
    expect('reject_increased_framework_path_count',
           lambda: build_staged.check_timing_coverage(changed, scope_file, stage), True)
    source = stage / 'sys/sys_top.v'
    source.write_text(source.read_text() + '\n// changed fixture\n')
    expect('reject_changed_framework_source',
           lambda: build_staged.check_timing_coverage(full_report, scope_file, stage), True)

# Instrumentation never grants the release build a JTAG exception.
instrumented_report = root / 'build/output_files/RabbitPunch_stp.sta.rpt'
if instrumented_report.exists():
    scope_file = root / 'scripts/framework_timing_scope.json'
    scoped_stage = root / 'build'
    expect('instrumented_reserved_jtag_scope', lambda: build_staged.check_timing_coverage(
        instrumented_report, scope_file, scoped_stage, revision='RabbitPunch_stp'), False)
    expect('release_rejects_reserved_jtag_scope', lambda: build_staged.check_timing_coverage(
        instrumented_report, scope_file, scoped_stage, revision='RabbitPunch'), True)
    changed = scratch / 'instrumented_untimed_sdram.rpt'
    changed.write_text(instrumented_report.read_text().replace('altera_reserved_tdi', 'SDRAM_DQ[0]'))
    expect('instrumented_rejects_untimed_sdram', lambda: build_staged.check_timing_coverage(
        changed, scope_file, scoped_stage, revision='RabbitPunch_stp'), True)
    changed = scratch / 'instrumented_extra_paths.rpt'
    text, count = re.subn(r'(;\s*Unconstrained Input Port Paths\s*;\s*)59(\s*;)',
                         r'\g<1>60\g<2>', instrumented_report.read_text(), count=1)
    assert count == 1
    changed.write_text(text)
    expect('instrumented_rejects_extra_paths', lambda: build_staged.check_timing_coverage(
        changed, scope_file, scoped_stage, revision='RabbitPunch_stp'), True)
    altered_scope = json.loads(scope_file.read_text())
    altered_scope['instrumented_jtag']['source_sha256']['rtl/rabbitpunch_debug.vhd'] = '0' * 64
    changed = scratch / 'changed_debug_scope.json'
    changed.write_text(json.dumps(altered_scope))
    expect('instrumented_rejects_changed_debug_source', lambda: build_staged.check_timing_coverage(
        instrumented_report, changed, scoped_stage, revision='RabbitPunch_stp'), True)

# Only the selected revision's generated bitstreams are disposable.
bitstream_stage = scratch / 'bitstream_stage'
output = bitstream_stage / 'output_files'
output.mkdir(parents=True, exist_ok=True)
for name in ('RabbitPunch_stp.rbf', 'RabbitPunch_stp.sof', 'Other.rbf', 'RabbitPunch_stp.sta.summary'):
    (output / name).write_text('test fixture')
build_staged.clear_stale_bitstreams(bitstream_stage, 'RabbitPunch_stp')
assert not (output / 'RabbitPunch_stp.rbf').exists() and not (output / 'RabbitPunch_stp.sof').exists()
assert (output / 'Other.rbf').exists() and (output / 'RabbitPunch_stp.sta.summary').exists()
checks.append(dict(case='clear_only_selected_stale_bitstreams', rejected=False))
expect('reject_bitstream_path_traversal',
       lambda: build_staged.clear_stale_bitstreams(bitstream_stage, '../outside'), True)

result = dict(checks=checks, reference_summary_sha256=hashlib.sha256(summary.read_bytes()).hexdigest(),
              reference_coverage_sha256=hashlib.sha256(report.read_bytes()).hexdigest(),
              script_sha256=hashlib.sha256((root / 'scripts/build_staged.py').read_bytes()).hexdigest(),
              scope='Real accepted Quartus report plus controlled missing/negative timing and coverage mutations; no compile or hardware claim')
(root / 'docs/reference/build_timing_gate_checks.json').write_text(json.dumps(result, indent=2) + '\n')
print(f'PASS full-build timing gates: {len(checks)} acceptance/negative controls')
