# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Bind an existing native dense-RAM proof to a frozen game diagnostic."""
import argparse
import hashlib
import json
from pathlib import Path
from coretools import core_root


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    root = core_root()
    bundle, out = args.bundle.resolve(), args.out.resolve()
    assert bundle.drive.upper() == out.drive.upper() == 'D:'
    target = out / 'native_state_ram_admission.json'
    assert out.is_dir() and not target.exists(), 'Preserve previous admissions'
    plan = json.loads((out / 'plan.json').read_text())
    assert plan['manifest_sha256'] == sha(bundle / 'manifest.json')
    receipt_path = root / 'docs/reference/state_ram_native_clean_completion_v2_checks.json'
    receipt = json.loads(receipt_path.read_text())
    assert receipt['accepted'] and receipt['transactions'] == 532480
    assert sha(root / receipt['log']) == receipt['log_sha256']
    assert sha(root / 'debug/baselines/state_ram_native_clean_completion_v2/state_ram_trace.txt') == receipt['trace_sha256']
    checked = {}
    for name, expected in receipt['source_sha256'].items():
        assert sha(root / name) == expected, name
        if name.startswith('rtl/'):
            frozen = bundle / 'inputs' / name
            assert sha(frozen) == expected, name
            # Only the two passive CPU observation outputs differ between the
            # frozen inputs and exported sources; no RAM source differs.
            assert sha(bundle / 'export_inputs' / name) == expected, name
            checked[name] = expected
    for width in (8, 16):
        frozen = bundle / f'reference/sim/fast/rabbitpunch_ram{width}_model.vhd'
        qualified = root / f'debug/baselines/state_ram_native_clean_completion_v2/ram{width}_model.vhd'
        expected = frozen.read_text().replace(f'rabbitpunch_ram{width}',
                                               f'rabbitpunch_ram{width}_model')
        assert qualified.read_text() == expected, frozen
        checked[f'logical_ram{width}_source'] = sha(frozen)
    report = dict(accepted=True, bundle_manifest_sha256=sha(bundle / 'manifest.json'),
        native_receipt_sha256=sha(receipt_path), source_sha256=checked,
        recorder_sha256=sha(Path(__file__)),
        scope='Dense RAM abstraction admission only. All106496 bytes, initial '
              'contents and two complete write/read patterns with delayed credits '
              'match native Intel RAM through actual state_memory/board_memory/'
              'sound_bus. Frozen native sources are byte exact; logical sources '
              'differ only by test entity renaming and text newline representation. '
              'Views are disabled during held access; collisions/unknown data are '
              'excluded. Does not admit SDRAM alias normalization, event monitors, '
              'whole-game continuation, full shell or hardware.')
    target.write_text(json.dumps(report, indent=2) + '\n')
    print('ADMITTED frozen dense RAM abstraction; other game gates remain open')


if __name__ == '__main__':
    main()
