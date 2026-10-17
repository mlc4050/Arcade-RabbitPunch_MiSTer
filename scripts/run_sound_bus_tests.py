"""Check native sound RAM and the board-specific sound memory map."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case


def main():
    root = core_root()
    sources = ['rtl/rabbitpunch_ram8.vhd', 'rtl/rabbitpunch_sound_bus.vhd', 'sim/sound/sound_bus_tb.vhd']
    result = run_case('sound_bus', sources, 'sound_bus_tb', '1 ms', 'SOUND_BUS_PASS')
    result.update(source_sha256={name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources},
        log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
        scope='Native 2048-byte sound RAM write/read and inspection, full selected sound map, YM enable-aligned writes, command ACK and ADPCM output strobes, held ROM requests/delayed replies; no CPU, actual sound chips or SDRAM')
    (root/'docs/reference/sound_bus_checks.json').write_text(json.dumps(result, indent=2)+'\n')


if __name__ == '__main__':
    main()
