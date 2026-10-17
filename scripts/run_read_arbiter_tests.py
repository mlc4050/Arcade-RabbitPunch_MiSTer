"""Check queued read-burst arbitration before sharing the CPU SDRAM port."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case


def main():
    root = core_root()
    sources = ['rtl/rabbitpunch_sdram_types.vhd', 'rtl/rabbitpunch_read_arbiter.vhd', 'sim/memory/read_arbiter_tb.vhd']
    result = run_case('read_arbiter', sources, 'read_arbiter_tb', '500 us', 'READ_ARBITER_PASS')
    result.update(source_sha256={name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources},
        log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
        scope='Three queued read-only burst clients: simultaneous acceptance, held ownership under backend backpressure, variable response delay, round-robin fairness, continuous client credit recycling, disabled acceptance with existing requests drained; synthetic backend, no SDRAM/video/audio integration')
    (root/'docs/reference/read_arbiter_checks.json').write_text(json.dumps(result, indent=2)+'\n')


if __name__ == '__main__':
    main()
