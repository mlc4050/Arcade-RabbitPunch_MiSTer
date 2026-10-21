# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Read back every real-ROM byte through the native SDRAM controller/chip."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
from coretools import core_root
from run_baselines import run_case


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image', required=True, type=Path)
    parser.add_argument('--label', required=True)
    parser.add_argument('--bytes', type=int, default=0x210000)
    parser.add_argument('--wall-timeout', type=int, default=1200)
    args = parser.parse_args()
    assert args.label.replace('_', '').isalnum()
    assert 8 <= args.bytes <= 0x210000 and args.bytes % 8 == 0
    root = core_root()
    image = args.image.read_bytes()
    assert len(image) == 0x210000
    case = 'state_sdram_image_'+args.label
    out = root/'debug/baselines'/case
    assert not out.exists(), 'Keep previous attempts'
    out.mkdir(parents=True)
    (out/'rom64.hex').write_text(''.join(f'{int.from_bytes(image[n:n+8], "little"):016X}\n'
                                       for n in range(0, args.bytes, 8)), newline='\n')
    sources = ['rtl/rabbitpunch_sdram_types.vhd', 'rtl/memory/sdram/sdram.sv',
               'rtl/rabbitpunch_sdram.vhd', 'sim/vendor/sdram/sdram_chip_model_wide.sv',
               'sim/state/state_sdram_image_tb.vhd']
    hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    for name in sources:
        target = out/'inputs'/name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root/name, target)
    (out/'attempt.json').write_text(json.dumps(dict(accepted=False, source_sha256=hashes,
        image_sha256=hashlib.sha256(image).hexdigest(), checked_bytes=args.bytes), indent=2)+'\n')
    result = run_case(case, sources, 'state_sdram_image_tb', '2001 ms',
        'STATE_SDRAM_IMAGE_PASS bytes='+str(args.bytes), wall_timeout=args.wall_timeout,
        sim_args=('-gGINT_IMAGE_BYTES='+str(args.bytes),), verilog_defines=())
    assert hashes == {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    result.update(accepted=True, source_sha256=hashes, checked_bytes=args.bytes,
        image_sha256=hashlib.sha256(image).hexdigest(),
        runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
        scope='Native production SDRAM adapter/controller and unchanged chip model. '
              'Real image bytes written only through normal16-bit client2 writes '
              'and all checked64-bit readbacks rotate across clients0/1/2 at '
              '5357ps shifted clock/capture adjustment1. No memory deposits. '
              'Not actual DDR/HPS loader, full-machine DQ hierarchy, export '
              'normalization, whole-game continuation, physical timing or hardware proof.')
    (root/'docs/reference'/('state_sdram_image_'+args.label+'_checks.json')).write_text(json.dumps(result, indent=2)+'\n')


if __name__ == '__main__':
    main()
