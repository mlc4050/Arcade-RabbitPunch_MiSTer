# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Pin completed isolated image/transport fits to exact tested source bytes."""
import hashlib
import json
import subprocess
from coretools import core_root, NO_WINDOW


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    root = core_root()
    for block in ('state_image_buffer', 'state_header', 'state_slot_writer', 'state_slot_reader'):
        result = json.loads((root/('debug/'+block+'_synth.json')).read_text())
        sources = ['rtl/state/rabbitpunch_'+block+'.vhd']
        if block == 'state_header':
            sources += ['rtl/state/rabbitpunch_state_crc.vhd']
        source_hashes = {}
        for name in sources:
            data = subprocess.check_output(['git', 'show', result['commit']+':'+name],
                                           cwd=root, **NO_WINDOW)
            assert hashlib.sha256(data).hexdigest() == digest(root/name), name
            source_hashes[name] = digest(root/name)
        assert result['memory_bits'] == (858240 if block == 'state_image_buffer' else 0)
        assert all(item['slack_ns'] >= 0 for item in result['timings'])
        folder = root/'build/rtl/synth_check'/block
        artifacts = [folder/(block+'_check.qsf'), folder/(block+'_check.sdc'),
                     folder/(block+'_check.vhd'), folder/'output_files'/(block+'_check.fit.rpt')]
        # Project directories and outputs survive later independent staged fits.
        # Boundary/source bytes must still equal their original committed input.
        for path in artifacts[:3]:
            name = path.relative_to(root/'build').as_posix()
            data = subprocess.check_output(['git', 'show', result['commit']+':'+name],
                                           cwd=root, **NO_WINDOW)
            if path.suffix == '.qsf':
                # Quartus appends this informational line and rewrites CRLF.
                # No source, constraint, seed or instance assignment may change.
                normalize = lambda text: [line for line in text.splitlines() if line.strip() and
                    line != 'set_global_assignment -name LAST_QUARTUS_VERSION "17.0.2 Lite Edition"']
                assert normalize(data.decode()) == normalize(path.read_text()), name
            else:
                assert hashlib.sha256(data).hexdigest() == digest(path), name
            source_hashes[name] = hashlib.sha256(data).hexdigest()
        result.update(source_sha256=source_hashes,
                      artifacts_sha256={p.relative_to(root).as_posix(): digest(p) for p in artifacts},
                      recorder_sha256=digest(root/'scripts/record_state_transport_fits.py'),
                      scope='Isolated registered virtual-I/O state block at48MHz seed3. '
                      'Exact committed source/boundary bytes retained; expected RAM and required '
                      'hierarchy gates passed. All reported timing nonnegative and unconstrained '
                      'gate passed. Not a complete core, post-fit functional proof, physical DDR '
                      'or hardware/game-state restore qualification.')
        (root/('docs/reference/'+block+'_synth_checks.json')).write_text(
            json.dumps(result, indent=2)+'\n', encoding='utf-8', newline='\n')
        print('RECORDED', block, 'RAM='+str(result['memory_bits']))


if __name__ == '__main__':
    main()
