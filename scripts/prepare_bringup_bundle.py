# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Prepare a private MiSTer bring-up bundle from an already timed, source-matched RBF."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import xml.etree.ElementTree as ET
from coretools import core_root, NO_WINDOW


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(root, *arguments):
    return subprocess.check_output(['git', '-C', str(root), *arguments], text=True, **NO_WINDOW).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive-root', type=Path, help='Worktree retaining the accepted Quartus artifact archive')
    parser.add_argument('--output-dir', type=Path)
    options = parser.parse_args()
    root = core_root()
    report_path = root / 'docs/reference/full_shell_hdmi_audio_release_checks.json'
    report = json.loads(report_path.read_text())
    assert report['accepted'] and report['revision'] == 'RabbitPunch'
    assert report['timing_checks'] == 144 and all(value >= 0 for value in report['minimum_slack_ns'].values())
    paths = ['RabbitPunch.sv', 'RabbitPunch.qsf', 'RabbitPunch.sdc', 'files.qip', 'rtl', 'sys']
    for revision in (report['commit'], 'HEAD'):
        changed = git(root, 'diff', '--name-only', revision, '--', *paths)
        assert not changed, 'Production sources differ from the timed RBF: ' + changed
    assert not git(root, 'ls-files', '--others', '--exclude-standard', '--', 'rtl', 'sys'), 'Untracked production source needs review'
    archive_root = options.archive_root or root
    archive = archive_root / report['archive']
    for name, digest in report['artifact_sha256'].items():
        assert sha(archive / name) == digest, 'Archived fit artifact changed: ' + name
    rbf = archive / 'RabbitPunch.rbf'
    assert sha(rbf) == report['artifact_sha256']['RabbitPunch.rbf'] and rbf.stat().st_size > 1000000
    date = git(root, 'show', '-s', '--format=%cs', report['commit']).replace('-', '')
    output = options.output_dir or root / 'debug/bringup' / (date + '_' + report['commit'][:7])
    if not output.is_absolute():
        output = root / output
    assert not output.exists(), 'Choose a fresh output directory; bundles are retained immutably'
    output.mkdir(parents=True)
    arcade = output / '_Arcade'
    cores = arcade / 'cores'
    cores.mkdir(parents=True)
    shutil.copy2(rbf, cores / ('Arcade-RabbitPunch_' + date + '.rbf'))
    mras = list((root / 'releases/_dev').glob('*.mra'))
    mras += list((root / 'releases/_dev/_ddr').glob('*.mra'))
    mras += list((root / 'releases/_dev/_diagnostic').glob('*.mra'))
    assert len(mras) == 5
    records = []
    for source in mras:
        tree = ET.parse(source)
        assert tree.findtext('rbf') == 'RabbitPunch' and tree.findtext('mameversion') == '0289'
        selected = tree.findtext('setname')
        assert selected in ('rabiolep', 'rpunch', 'rpdiag')
        if source.parent.name == '_ddr':
            destination = arcade / '_Alternatives/DDR load' / source.name
        elif selected == 'rpdiag':
            destination = arcade / '_Diagnostic' / source.name
        else:
            destination = arcade / source.name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        assert sha(source) == sha(destination)
        records.append(dict(source=source.relative_to(root).as_posix(), destination=destination.relative_to(output).as_posix(),
                            set=selected, sha256=sha(source)))
    readme = f'''Rabbit Punch / Rabio Lepus private bring-up candidate

This is a local timed prototype, not a hardware-verified release.
RBF source: {report['commit']}, Quartus 17.0.2 Lite, seed {report['seed']}.
All {report['timing_checks']} required timing checks pass. Minimum setup/hold:
{report['minimum_slack_ns']['Setup']:+.3f}/{report['minimum_slack_ns']['Hold']:+.3f} ns.
The accepted provisional raster and SDRAM phase still need physical bring-up.

No ROM ZIPs are included. The original diagnostic needs no ROMs; the two games
use the user's already-verified MAME 0.289 ROM set (merged rabiolep.zip).
This bundle has not been copied to or launched on a MiSTer.

When doing the authorized hardware bring-up, copy the _Arcade contents into the
MiSTer's _Arcade directory. The RBF belongs in _Arcade/cores. Keep the ROM ZIP
in the configured MiSTer arcade ROM location. The MRA files retain their tested
ROM layout, DIP defaults, Shoot/Missile controls and hiscore transfers.

Start _Diagnostic/RabbitPunch_Diagnostic.mra first. After the CPU finishes filling
bitmap RAM, expect repeating one-pixel red, green, blue and white stripes. The
normal completion signature is CAFE at 0FC000, heartbeat BEEF at 0FC008. This is
the original program, not a forced test RGB output. The RBF here has no JTAG probes.

Then test the two default game MRAs. Begin with default output options. The DDR
load variants are under _Alternatives/DDR load; they use the same game image.
Check both-player movement, Shoot, Missile, coin/start and pause. Physical game
boot/play, audio, analog CRT/HDMI output and .dip/.nvm filesystem round trips remain
unverified until results are recorded from the actual device.

manifest.json records the source-matched fit, exact RBF and MRA hashes. Nothing
under releases/ was published, and no deployment or hardware operation was run.
'''
    (output / 'README.txt').write_text(readme)
    manifest = dict(packager_sha256=sha(Path(__file__)),prepared=True, hardware_verified=False, deployed=False, published=False,
                    packaging_commit=git(root, 'rev-parse', 'HEAD'), rbf_commit=report['commit'],
                    revision=report['revision'], seed=report['seed'], timing_checks=report['timing_checks'],
                    minimum_slack_ns=report['minimum_slack_ns'], fit_report_sha256=sha(report_path),
                    archive_worktree=str(archive_root), artifact_archive=report['archive'], output=str(output),
                    production_sources_match_timed_commit=True, mras=records,
                    files={path.relative_to(output).as_posix():sha(path) for path in output.rglob('*') if path.is_file()},
                    scope='Private source-matched timed RBF plus byte-identical development MRAs; no ROM ZIPs, publication, deployment, JTAG or hardware execution. Required reported timing passes under the previously documented provisional SDRAM and inherited peripheral coverage scope.')
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (root / 'docs/reference/bringup_bundle_checks.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print('Prepared private bring-up bundle:', output)


if __name__ == '__main__':
    main()
