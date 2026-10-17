"""Check audio byte caches, bank-race rejection and image invalidation."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case


def main():
    root = core_root()
    sources = ['rtl/rabbitpunch_layout.vhd', 'rtl/rabbitpunch_sdram_types.vhd', 'rtl/rabbitpunch_rom_cache.vhd', 'rtl/rabbitpunch_audio_roms.vhd', 'sim/memory/audio_roms_tb.vhd']
    result = run_case('audio_roms', sources, 'audio_roms_tb', '2 ms', 'AUDIO_ROMS_PASS')
    result.update(source_sha256={name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources},
        log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
        scope='Sound CPU and sample byte frontends around existing burst caches: all eight lanes, exact image-region/bank boundaries, concurrent misses, full-address rejection of stale bank reply, withdrawn request drain and new-image invalidation; synthetic independent burst backends, no physical SDRAM arbitration or game playback')
    (root/'docs/reference/audio_roms_checks.json').write_text(json.dumps(result, indent=2)+'\n')


if __name__ == '__main__':
    main()
