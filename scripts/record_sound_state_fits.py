# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Pin isolated sound-state fits to the qualified canonical model bytes."""
import argparse
import hashlib
import json
import re
from coretools import core_root


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--chip', action='append', choices=('jt51', 'jt7759'))
    args = parser.parse_args()
    root = core_root()
    for chip in args.chip or ('jt51', 'jt7759'):
        result = json.loads((root/('debug/'+chip+'_state_synth.json')).read_text())
        model = root/'rtl/state/generated'/(chip+'_state_netlist.vhd')
        metadata = json.loads(model.with_suffix('.json').read_text())
        stage_model = root/'build'/model.relative_to(root)
        assert digest(model) == digest(stage_model) == metadata['generated_sha256']
        assert result['memory_bits'] == 0
        assert all(item['slack_ns'] >= 0 for item in result['timings'])
        folder = root/'build/rtl/synth_check'/(chip+'_state')
        report = folder/'output_files'/(chip+'_state_check.fit.rpt')
        label = '|rabbitpunch_'+chip+'_state_netlist:state_chip|'
        rows = [[field.strip() for field in line.split(';')] for line in report.read_text().splitlines()
                if line.startswith(';') and label in line]
        rows = [row for row in rows if len(row) > 8 and row[1] == label]
        assert len(rows) == 1, 'Missing/ambiguous core resource row'
        registers = int(re.match(r'\d+', rows[0][8]).group())
        assert registers >= metadata['state_bits'], 'State register count optimized below image size'
        result.update(canonical_model_sha256=metadata['generated_sha256'],
                      mapped_state_bits=metadata['state_bits'], core_registers=registers,
                      fitter_report_sha256=digest(report),
                      qsf_sha256=digest(folder/(chip+'_state_check.qsf')),
                      sdc_sha256=digest(folder/(chip+'_state_check.sdc')),
                      recorder_sha256=digest(root/'scripts/record_sound_state_fits.py'),
                      preservation_scope='Required chip hierarchy, zero RAM and fitted core '
                      'register count not less than complete mapped state size. Dynamic scan '
                      'read/write ports remain observable through registered boundary I/O. '
                      'This is a preservation sanity gate, not post-fit functional equivalence.',
                      scope='Standalone registered virtual-I/O sound-state block at48MHz '
                      'seed3 on5CSEBA6U23I7. All reported setup/hold/recovery/removal/pulse '
                      'checks nonnegative and unconstrained-path gate passed. Exact canonical '
                      'model bytes match staged source. No complete core, game restore, '
                      'hardware or deployment qualification.')
        (root/('docs/reference/'+chip+'_state_synth_checks.json')).write_text(
            json.dumps(result, indent=2)+'\n', encoding='utf-8')
        print('RECORDED', chip, 'core_registers='+str(registers), 'state_bits='+str(metadata['state_bits']))


if __name__ == '__main__':
    main()
