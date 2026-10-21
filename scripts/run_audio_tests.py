"""Exercise command IRQ, banked sample playback and pause in the complete logical audio subsystem."""
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
    sources += [row['target'] for row in manifest['files'] if row['donor'] == 'upd7759' and row['target'].startswith('rtl/') and row['target'].endswith('.v')]
    sources += ['rtl/rabbitpunch_upd7759_control.vhd', 'rtl/rabbitpunch_upd7759_playback.vhd', 'rtl/rabbitpunch_upd7759.vhd', 'rtl/rabbitpunch_adpcm.vhd', 'rtl/rabbitpunch_audio.vhd', 'sim/sound/audio_tb.vhd']
    result = run_case('audio', sources, 'audio_tb', '8 ms', 'AUDIO_PASS', wall_timeout=240)
    result.update(source_sha256={name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources},
        log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
        scope='Connected T80/native sound bus/RAM/JT51/JT7759: two command IRQ handlers select both sample banks and trigger complete synthetic samples; YM busy readback, IRQ ACK, paused native RAM inspection and continued playback/cadence while CPU pauses; behavioral delayed ROM transports, no shared SDRAM/game samples/mixing/physical timing')
    (root/'docs/reference/audio_checks.json').write_text(json.dumps(result, indent=2)+'\n')


if __name__ == '__main__':
    main()
