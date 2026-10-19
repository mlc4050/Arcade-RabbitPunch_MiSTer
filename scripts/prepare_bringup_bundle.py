# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Prepare a private MiSTer bring-up bundle from an already timed, source-matched RBF."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
from xml.sax.saxutils import escape
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
    parser.add_argument('--revision', choices=('RabbitPunch', 'RabbitPunch_stp'), default='RabbitPunch')
    options = parser.parse_args()
    root = core_root()
    debug = options.revision == 'RabbitPunch_stp'
    report_name = 'full_shell_hdmi_audio_debug_seed2_checks.json' if debug else 'full_shell_hdmi_audio_release_checks.json'
    report_path = root / 'docs/reference' / report_name
    report = json.loads(report_path.read_text())
    assert report['accepted'] and report['revision'] == options.revision
    assert report['timing_checks'] == (164 if debug else 144) and all(value >= 0 for value in report['minimum_slack_ns'].values())
    paths = ['RabbitPunch.sv', options.revision + '.qsf', 'RabbitPunch.sdc', 'files.qip', 'rtl', 'sys']
    for revision in (report['commit'], 'HEAD'):
        changed = git(root, 'diff', '--name-only', revision, '--', *paths)
        assert not changed, 'Production sources differ from the timed RBF: ' + changed
    assert not git(root, 'ls-files', '--others', '--exclude-standard', '--', 'rtl', 'sys'), 'Untracked production source needs review'
    archive_root = options.archive_root or root
    archive = archive_root / report['archive']
    for name, digest in report['artifact_sha256'].items():
        assert sha(archive / name) == digest, 'Archived fit artifact changed: ' + name
    rbf_name = options.revision + '.rbf'
    rbf = archive / rbf_name
    assert sha(rbf) == report['artifact_sha256'][rbf_name] and rbf.stat().st_size > 1000000
    date = git(root, 'show', '-s', '--format=%cs', report['commit']).replace('-', '')
    output = options.output_dir or root / 'debug/bringup' / (date + '_' + report['commit'][:7])
    if not output.is_absolute():
        output = root / output
    assert not output.exists(), 'Choose a fresh output directory; bundles are retained immutably'
    output.mkdir(parents=True)
    arcade = output / '_Arcade'
    cores = arcade / 'cores'
    cores.mkdir(parents=True)
    shutil.copy2(rbf, cores / ('Arcade-' + options.revision + '_' + date + '.rbf'))
    if debug:
        metadata = output / 'debug_metadata'
        metadata.mkdir()
        shutil.copy2(archive / 'RabbitPunch_stp.sld', metadata / 'RabbitPunch_stp.sld')
    menu_root = arcade / '_Debug' if debug else arcade
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
            destination = menu_root / '_Alternatives/DDR load' / source.name
        elif selected == 'rpdiag':
            destination = menu_root / '_Diagnostic' / source.name
        else:
            destination = menu_root / source.name
        destination.parent.mkdir(parents=True, exist_ok=True)
        if debug:
            raw = source.read_bytes()
            original_name = tree.findtext('name')
            name_tag = ('<name>' + escape(original_name) + '</name>').encode()
            assert raw.count(b'<rbf>RabbitPunch</rbf>') == raw.count(name_tag) == 1
            raw = raw.replace(b'<rbf>RabbitPunch</rbf>', b'<rbf>RabbitPunch_stp</rbf>', 1)
            raw = raw.replace(name_tag, ('<name>' + escape(original_name + ' [Debug]') + '</name>').encode(), 1)
            destination.write_bytes(raw)
            packaged = ET.parse(destination)
            assert packaged.findtext('rbf') == 'RabbitPunch_stp'
            assert packaged.findtext('name') == original_name + ' [Debug]'
            packaged.find('rbf').text = 'RabbitPunch'
            packaged.find('name').text = original_name
            assert ET.tostring(packaged.getroot()) == ET.tostring(tree.getroot()), 'Debug MRA changed more than name/target'
        else:
            shutil.copy2(source, destination)
            assert sha(source) == sha(destination)
        records.append(dict(source=source.relative_to(root).as_posix(), destination=destination.relative_to(output).as_posix(),
                            set=selected, source_sha256=sha(source), sha256=sha(destination),
                            metadata_changes=['name', 'rbf'] if debug else []))
    diagnostic_path = '_Debug/_Diagnostic/RabbitPunch_Diagnostic.mra' if debug else '_Diagnostic/RabbitPunch_Diagnostic.mra'
    probe_note = ('This instrumented RBF includes the read-only RPUN probe. Its SLD is retained under debug_metadata on the PC. Read through scripts/read_issp.py only after every build/simulation has ended and hardware access is authorized.' if debug else 'The RBF here has no JTAG probes.')
    readme = f'''Rabbit Punch / Rabio Lepus private bring-up candidate

This is a local timed prototype, not a hardware-verified release.
Revision: {options.revision}. RBF source: {report['commit']}, Quartus 17.0.2 Lite, seed {report['seed']}.
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

Start {diagnostic_path} first. After the CPU finishes filling
bitmap RAM, expect repeating one-pixel red, green, blue and white stripes. The
normal completion signature is CAFE at 0FC000, heartbeat BEEF at 0FC008. This is
the original program, not a forced test RGB output.\n{probe_note}

Then test the two game MRAs in {'_Debug' if debug else 'the bundle root'}. Begin with default output options. The DDR
load variants are under {'_Debug/' if debug else ''}_Alternatives/DDR load; they use the same game image.
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
                    production_sources_match_timed_commit=True, debug_probes=debug, mras=records,
                    files={path.relative_to(output).as_posix():sha(path) for path in output.rglob('*') if path.is_file()},
                    scope=('Private source-matched timed debug RBF; MRAs differ only in name and RBF target;' if debug else 'Private source-matched timed RBF plus byte-identical development MRAs;') + ' no ROM ZIPs, publication, deployment, JTAG or hardware execution. Required reported timing passes under the previously documented provisional SDRAM and inherited peripheral coverage scope.')
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (root / ('docs/reference/bringup_bundle_debug_checks.json' if debug else 'docs/reference/bringup_bundle_checks.json')).write_text(json.dumps(manifest, indent=2) + '\n')
    print('Prepared private bring-up bundle:', output)


if __name__ == '__main__':
    main()
