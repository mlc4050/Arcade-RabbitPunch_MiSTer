"""Check Rabbit Punch's uPD7759 control/reset/start and ROM bank mapping."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case


def main():
    root = core_root()
    manifest = json.loads((root/'docs/reference/vendor_manifest.json').read_text())
    rows = [row for row in manifest['files'] if row['donor'] == 'upd7759']
    for row in rows:
        assert hashlib.sha256((root/row['target']).read_bytes()).hexdigest() == row['sha256']
    sources = [row['target'] for row in rows if row['target'].startswith('rtl/') and row['target'].endswith('.v')]
    sources += ['rtl/rabbitpunch_upd7759.vhd', 'rtl/rabbitpunch_adpcm.vhd', 'sim/sound/adpcm_tb.vhd']
    result = run_case('adpcm', sources, 'adpcm_tb', '10 ms', 'ADPCM_PASS', wall_timeout=120)
    result.update(source_sha256={name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources},
        log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
        scope='Board ADPCM adapter with unchanged JT7759: F400 active-low reset and bank bit, F600 command/start, two synthetic ROM banks, completed playback/retrigger, ignored reset command, active abort, delayed address-qualified ROM data; no game samples/shared SDRAM/mixing/physical timing')
    (root/'docs/reference/adpcm_checks.json').write_text(json.dumps(result, indent=2)+'\n')


if __name__ == '__main__':
    main()
