# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Pin completed parent fits without recompiling or changing their source inputs."""
import argparse
import hashlib
import json
from pathlib import Path
import shlex
import subprocess
from coretools import core_root, NO_WINDOW


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', action='append', help='Record only this named parent; may repeat')
    args = parser.parse_args()
    root = core_root()
    for block, memory in (('state_host', 0), ('state_maincpu', 39584), ('state_board', 907936), ('state_snapshot', 0),
                          ('state_audio', 16384), ('state_image_validator', 0),
                          ('state_apply', 0), ('state_banks', 0), ('state_publish', 0), ('state_service', 858240),
                          ('state_machine', 1784608),
                          ('state_scanout', 0)):
        if args.target and block not in args.target:
            continue
        result = json.loads((root/f'debug/{block}_synth.json').read_text())
        assert result['memory_bits'] == memory
        assert all(row['slack_ns'] >= 0 for row in result['timings'])
        source_folder = root/'rtl/synth_check'/block
        fit_folder = root/'build/rtl/synth_check'/block
        qsf = source_folder/f'{block}_check.qsf'
        sources = [qsf, source_folder/f'{block}_check.sdc']
        for line in qsf.read_text().splitlines():
            fields = shlex.split(line)
            if len(fields) >= 4 and fields[2] in ('VHDL_FILE', 'SYSTEMVERILOG_FILE'):
                sources.append((source_folder/fields[3]).resolve())
        if block in ('state_maincpu', 'state_board', 'state_machine'):
            sources += [root/'rtl/cpu/fx68k'/name for name in ('microrom.mem', 'nanorom.mem')]
        source_hashes, blob_hashes = {}, {}
        for path in sources:
            name = path.relative_to(root).as_posix()
            data = subprocess.check_output(['git', 'show', result['commit']+':'+name],
                                           cwd=root, **NO_WINDOW)
            # Git's text checkout policy can expand LF to CRLF. Only that
            # byte substitution is allowed; vendor -text inputs stay exact.
            actual = path.read_bytes()
            assert data.replace(b'\r\n', b'\n') == actual.replace(b'\r\n', b'\n'), name
            staged = (root/'build'/name).read_bytes()
            if name.startswith('rtl/cpu/') or '/vendor/' in name:
                assert actual == data and staged == data, name
            if path.suffix != '.qsf':
                assert staged.replace(b'\r\n', b'\n') == data.replace(b'\r\n', b'\n'), name
            source_hashes[name] = sha(staged)
            blob_hashes[name] = sha(data)
        artifacts = [fit_folder/f'{block}_check{ext}' for ext in ('.qsf', '.sdc', '.vhd')]
        artifacts += [fit_folder/'output_files'/f'{block}_check.fit.rpt']
        for path in artifacts[:3]:
            name = path.relative_to(root/'build').as_posix()
            data = subprocess.check_output(['git', 'show', result['commit']+':'+name],
                                           cwd=root, **NO_WINDOW)
            if path.suffix == '.qsf':
                def normalized(text):
                    return [line for line in text.splitlines() if line.strip() and
                            line != 'set_global_assignment -name LAST_QUARTUS_VERSION "17.0.2 Lite Edition"']
                assert normalized(data.decode()) == normalized(path.read_text()), name
            else:
                assert data.replace(b'\r\n', b'\n') == path.read_bytes().replace(b'\r\n', b'\n'), name
        if block in ('state_audio', 'state_machine'):
            rows = [line.split(';') for line in artifacts[-1].read_text().splitlines()]
            preserved = {}
            for chip in ('jt51', 'jt7759'):
                model = 'rabbitpunch_'+chip+'_state_netlist'
                model_path = root/'rtl/state/generated'/(chip+'_state_netlist.vhd')
                metadata = json.loads(model_path.with_suffix('.json').read_text())
                assert metadata['generated_sha256'] == sha(model_path.read_bytes())
                minimum = metadata['state_bits']
                matches = [row for row in rows if len(row) > 8 and
                           row[1].strip().startswith('|'+model+':')]
                assert len(matches) == 1, (model, matches)
                count = int(matches[0][8].strip().split()[0].replace(',', ''))
                assert count >= minimum, (model, count)
                preserved[model] = count
            result['fitted_sound_registers'] = preserved
        result.update(source_sha256=source_hashes,
                      committed_blob_sha256=blob_hashes,
                      artifacts_sha256={p.relative_to(root).as_posix(): sha(p.read_bytes())
                                        for p in artifacts},
                      recorder_sha256=sha(Path(__file__).read_bytes()),
                      scope='Isolated registered virtual-I/O parent at48MHz seed3. Exact '
                      'committed dependencies and boundary inputs retained; expected memory, '
                      'hierarchy, unconstrained-path and nonnegative timing gates passed. '
                      'Register counts are preservation checks, not post-fit functional proof. '
                      'Not a whole-core fit or game-state/hardware restore qualification.')
        (root/f'docs/reference/{block}_synth_checks.json').write_text(
            json.dumps(result, indent=2)+'\n', encoding='utf-8', newline='\n')
        print('RECORDED', block, 'RAM='+str(memory))


if __name__ == '__main__':
    main()
