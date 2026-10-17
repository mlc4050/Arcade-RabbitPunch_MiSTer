"""Check sound CPU transaction completion, pause and reset with slow replies."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case


def main():
    root = core_root()
    sources = [f'rtl/cpu/t80/{name}.vhd' for name in ('T80_Pack', 'T80_Reg', 'T80_MCode', 'T80_ALU', 'T80', 'T80se')]
    sources += ['rtl/rabbitpunch_z80.vhd', 'rtl/rabbitpunch_soundcpu.vhd', 'sim/sound/soundcpu_tb.vhd']
    result = run_case('soundcpu', sources, 'soundcpu_tb', '250 us', 'SOUNDCPU_PASS')
    result.update(source_sha256={name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources},
        log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
        scope='T80 transaction adapter with 65-clock delayed replies, synthetic RAM readback/peripheral writes, pause mid-read and reset mid-read draining; no game or sound-board proof')
    (root/'docs/reference/soundcpu_checks.json').write_text(json.dumps(result, indent=2)+'\n')


if __name__ == '__main__':
    main()
