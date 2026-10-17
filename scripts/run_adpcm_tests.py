"""Check native JT7759 at 640 kHz with delayed synthetic sample ROM reads."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case


def main():
    root = core_root()
    manifest = json.loads((root/'docs/reference/vendor_manifest.json').read_text())
    files = [row for row in manifest['files'] if row['donor'] == 'upd7759']
    for row in files:
        assert hashlib.sha256((root/row['target']).read_bytes()).hexdigest() == row['sha256']
    sources = [row['target'] for row in files if row['target'].startswith('rtl/') and row['target'].endswith('.v')]
    sources += ['rtl/rabbitpunch_upd7759.vhd', 'sim/sound/jt7759_baseline_tb.vhd']
    results = []
    for wrapped in (False, True):
        result = run_case('jt7759_wrapper' if wrapped else 'jt7759_baseline', sources, 'jt7759_baseline_tb', '7 ms', 'JT7759_BASELINE_PASS', wall_timeout=120, sim_args=(f"-gUSE_WRAPPER={str(wrapped).lower()}",))
        result.update(wrapper=wrapped, source_sha256={name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources},
            log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
            scope='Native unchanged JT7759 and descriptive wrapper, 48 MHz evaluation clock and 640 kHz enable, two different synthetic standalone sample starts/completions, delayed ROM replies and reset mute; nonzero PCM presence only, no decoded-value/game waveform/bank/hardware timing proof')
        results.append(result)
    (root/'docs/reference/jt7759_checks.json').write_text(json.dumps(results, indent=2)+'\n')


if __name__ == '__main__':
    main()
