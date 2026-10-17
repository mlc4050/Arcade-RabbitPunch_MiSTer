"""Exercise command IRQ/acknowledgement and pause on the connected sound board."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case


def main():
    root = core_root()
    manifest = json.loads((root/'docs/reference/vendor_manifest.json').read_text())
    sources = [f'rtl/cpu/t80/{name}.vhd' for name in ('T80_Pack', 'T80_Reg', 'T80_MCode', 'T80_ALU', 'T80', 'T80se')]
    sources += [row['target'] for row in manifest['files'] if row['target'].startswith(('rtl/sound/jt51/', 'sim/vendor/jt51/')) and row['target'].endswith('.v')]
    sources += [f'rtl/{name}.vhd' for name in ('rabbitpunch_z80', 'rabbitpunch_soundcpu', 'rabbitpunch_ym2151', 'rabbitpunch_ram8', 'rabbitpunch_sound_bus', 'rabbitpunch_sound_board')]
    sources += ['sim/sound/sound_board_tb.vhd']
    result = run_case('sound_board', sources, 'sound_board_tb', '400 us', 'SOUND_BOARD_PASS', wall_timeout=180)
    result.update(source_sha256={name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources},
        log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
        scope='Native sound board: two synthetic command interrupts, FF interrupt acknowledge/IM1 handler/RETI, mailbox read acknowledgements, native RAM inspection and CPU pause while JT51 sample cadence continues; behavioral ROM transport, no uPD or game sound')
    (root/'docs/reference/sound_board_checks.json').write_text(json.dumps(result, indent=2)+'\n')


if __name__ == '__main__':
    main()
