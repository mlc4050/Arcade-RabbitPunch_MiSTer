# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Qualify mono arithmetic and exact registered PCM continuation through state hold/load."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from coretools import core_root, NO_WINDOW


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ghdl', required=True)
    args = parser.parse_args()
    root = core_root()
    out = root/'debug/ghdl/audio_mixer_state'
    out.mkdir(parents=True, exist_ok=True)
    sources = ['rtl/rabbitpunch_audio_mixer.vhd', 'sim/state/audio_mixer_state_tb.vhd']
    hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    logs = []
    for command in [[args.ghdl, '-a', '--std=08', '--workdir='+str(out), *sources],
                    [args.ghdl, '--elab-run', '--std=08', '--workdir='+str(out),
                     'audio_mixer_state_tb', '--assert-level=error']]:
        result = subprocess.run(command, cwd=root, text=True, capture_output=True,
                                timeout=30, **NO_WINDOW)
        logs.append(result.stdout+result.stderr)
        assert result.returncode == 0, logs[-1]
    log = '\n'.join(logs)
    assert 'AUDIO_MIXER_STATE_PASS' in log, log
    assert hashes == {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    (out/'result.log').write_text(log, encoding='utf-8', newline='\n')
    report = dict(accepted=True, source_sha256=hashes,
                  runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  log_sha256=hashlib.sha256((out/'result.log').read_bytes()).hexdigest(),
                  scope='Registered mono mixer: original independent integer arithmetic vectors plus three state roundtrips, complementary16bit writes, changed inputs held stable, exact first resumed PCM and following sample phase, reset priority during held load. Normal mix arithmetic unchanged. Not physical audio or whole-game restore qualification.')
    (root/'docs/reference/audio_mixer_state_checks.json').write_text(
        json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print(log, end='')


if __name__ == '__main__':
    main()
