# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Compare actual state RAM access against native Intel and logical endpoints."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
from coretools import core_root
from run_baselines import run_case


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    parser.add_argument('--wall-timeout', type=int, default=1200)
    args = parser.parse_args()
    assert args.label.replace('_', '').isalnum()
    assert 1 <= args.wall_timeout <= 1800
    root = core_root()
    case = 'state_ram_native_'+args.label
    out = root/'debug/baselines'/case
    assert not out.exists(), 'Keep previous attempts'
    out.mkdir(parents=True)
    originals = ['rtl/rabbitpunch_layout.vhd', 'rtl/rabbitpunch_decode.vhd',
                 'rtl/rabbitpunch_ram16.vhd', 'rtl/rabbitpunch_ram8.vhd',
                 'rtl/rabbitpunch_board_memory.vhd', 'rtl/rabbitpunch_sound_bus.vhd',
                 'rtl/state/rabbitpunch_state_memory.vhd']
    contract = json.loads((root/'docs/reference/fast_ram_contract_checks.json').read_text())
    assert contract['accepted']
    for width in (16, 8):
        native = f'rtl/rabbitpunch_ram{width}.vhd'
        model = f'sim/fast/rabbitpunch_ram{width}_model.vhd'
        assert sha(root/native) == contract['native_comparison']['source_sha256'][native]
        data = (root/model).read_bytes()
        # The pinned native contract used a CRLF checkout of these authored
        # simulation models. Admit only that exact line-ending substitution.
        assert hashlib.sha256(data.replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')).hexdigest() == contract['source_sha256'][model]
    # Rename only entity references; preserve every storage/timing statement.
    generated = []
    for width in (16, 8):
        text = (root/f'sim/fast/rabbitpunch_ram{width}_model.vhd').read_text()
        target = out/f'ram{width}_model.vhd'
        target.write_text(text.replace(f'rabbitpunch_ram{width}', f'rabbitpunch_ram{width}_model'), newline='\n')
        generated.append(target.relative_to(root).as_posix())
    for entity in ('rabbitpunch_board_memory', 'rabbitpunch_sound_bus'):
        text = (root/'rtl'/(entity+'.vhd')).read_text().replace(entity, entity+'_model')
        for width in (16, 8):
            text = text.replace(f'entity work.rabbitpunch_ram{width}', f'entity work.rabbitpunch_ram{width}_model')
        target = out/(entity+'_model.vhd')
        target.write_text(text, newline='\n')
        generated.append(target.relative_to(root).as_posix())
    sources = originals+generated+['sim/state/state_ram_native_compare_tb.vhd']
    hashes = {name: sha(root/name) for name in sources}
    snapshots = out/'inputs'
    for name in sources:
        target = snapshots/name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root/name, target)
    ini = out/'modelsim.ini'
    shutil.copyfile(Path(os.environ['MODELSIM']), ini)
    os.environ['MODELSIM'] = str(ini)
    (out/'attempt.json').write_text(json.dumps(dict(accepted=False, source_sha256=hashes,
        runner_sha256=sha(Path(__file__))), indent=2)+'\n')
    # run_case uses -onfinish exit: std.env.finish is successful completion,
    # distinct from assertions/breaks. The earlier peer -onfinish stop attempt
    # reached its full PASS marker but was rejected with process status1.
    result = run_case(case, sources, 'state_ram_native_compare_tb', '101 ms',
                      'STATE_RAM_NATIVE_COMPARE_PASS operations=532480',
                      wall_timeout=args.wall_timeout)
    trace = out/'state_ram_trace.txt'
    with trace.open() as handle:
        count = 0
        for count, line in enumerate(handle, 1):
            fields = line.split()
            number, address = map(int, fields[:2])
            assert number == count-1 and address == number % 106496
            phase = number // 106496
            writing = phase in (1, 3)
            assert fields[2] == str(writing).lower()
            if not writing:
                epoch = 0 if phase == 0 else (phase+1)//2
                expected = (255 if address < 65536 else 0) if epoch == 0 else (address*37+address//256+epoch*83)%256
                assert int(fields[3], 16) == expected
        assert count == 532480
    assert hashes == {name: sha(root/name) for name in sources}
    result.update(accepted=True, transactions=count, source_sha256=hashes,
        runner_sha256=sha(Path(__file__)), trace_sha256=sha(trace),
        log_sha256=sha(root/result['log']),
        scope='Actual state_memory feeding paired production board_memory/sound_bus '
              'with native Intel versus renamed logical RAM. All106496 dense bytes, '
              'configured initial contents and two complete writes/reads, both '
              'main byte lanes and delayed1..5-cycle credits; independent Python '
              'checks every transaction/read value. Idle sound address defined '
              'only without a request. Renderer/view disabled, collisions and '
              'unknown data excluded. No CPU/chip/full-game/FPGA qualification.')
    (root/'docs/reference'/('state_ram_native_'+args.label+'_checks.json')).write_text(json.dumps(result, indent=2)+'\n')
    print('PASS all532480 state RAM transactions including clean native completion')


if __name__ == '__main__':
    main()
