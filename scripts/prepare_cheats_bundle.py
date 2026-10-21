# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
from coretools import core_root
root=core_root()
sys.path.insert(0,str(root/'scripts'))
import build_staged as gates

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def git(*args):
    return subprocess.check_output(['git','-C',str(root),*args],text=True).strip()

parser=argparse.ArgumentParser(description='Package a timed private candidate with matching cheat MRAs.')
parser.add_argument('--label',default='cheats')
parser.add_argument('--stage', type=Path, help='Previously qualified build snapshot inside this repository')
args=parser.parse_args()
assert args.label.replace('_','').isalnum()
stage=args.stage.resolve() if args.stage else root/'build'
assert root.resolve() in stage.resolve().parents and stage.drive.upper() == 'D:'
stamp=(stage/'BUILT_COMMIT').read_text()
commit=stamp.split()[0]
seed_match=re.search(r'\bseed=(\d+)\b',stamp)
assert seed_match
seed=int(seed_match[1])
assert seed>0
assert re.findall(r'^set_global_assignment -name SEED (\d+)$',(stage/'RabbitPunch.qsf').read_text(),re.M)==[str(seed)]
assert not (root/'.build_running').exists()
assert not (stage/'.build_running').exists()
assert 'Full Compilation was successful' in (stage/'q_staged.log').read_text()[-7000:]
gates.REV='RabbitPunch'
assert not gates.check_present(stage)
assert not gates.check_macros(stage)
assert not gates.read_slacks(stage/'output_files/RabbitPunch.sta.summary')
gates.check_timing_coverage(stage/'output_files/RabbitPunch.sta.rpt',stage/'scripts/framework_timing_scope.json',stage,revision='RabbitPunch')
clock=json.loads((stage/'output_files/full_clock_tree.json').read_text())
resources=json.loads((stage/'output_files/state_eval_resources.json').read_text())
assert resources['commit']==commit
production=['RabbitPunch.sv','RabbitPunch.qsf','RabbitPunch.sdc','files.qip','state_emu_eval.qip','rtl','sys']
assert not git('diff','--name-only',commit,'--',*production)
assert not git('ls-files','--others','--exclude-standard','--','rtl','sys')
line_ending_equivalence=[]
for receipt in ('cheats_board_v1','cheats_engine_mirrored_v2','cheats_host_loading_popup_v1','cheats_trace_rpunch_v1','cheats_trace_rabiolep_v1', 'state_controls_joystick_loading_popup_v1', 'state_controls_loading_popup_v1', 'state_controls_partial_loading_popup_v1'):
    report=json.loads((root/f'docs/reference/{receipt}_checks.json').read_text())
    assert report['accepted']
    for name,digest in report['source_sha256'].items():
        if sha(root/name)!=digest:
            # Earlier worktrees used LF; the main Windows checkout may use
            # CRLF. Admit only authored text that matches the hash-pinned
            # original test snapshot after CRLF normalization.
            assert '/vendor/' not in name and not name.startswith('rtl/cpu/'),name
            case=report.get('result',{}).get('case',receipt)
            candidates=[root/'debug/baselines'/case/'inputs'/name,
                root/'.local/archives/20261021-cleanup/snapshots/RabbitPunch-cheats-work/debug/baselines'/case/'inputs'/name]
            matches=[candidate for candidate in candidates if candidate.is_file() and sha(candidate)==digest]
            assert matches,'Original source snapshot missing: '+name
            current=(root/name).read_bytes().replace(b'\r\n',b'\n')
            original=matches[0].read_bytes().replace(b'\r\n',b'\n')
            assert current==original,'Production source changed: '+name
            line_ending_equivalence.append(dict(receipt=receipt,path=name,
                original_sha256=digest,current_sha256=sha(root/name),
                normalized_sha256=hashlib.sha256(current).hexdigest(),
                snapshot=matches[0].relative_to(root).as_posix()))
date=git('show','-s','--format=%cs',commit).replace('-','')
out=root/f'debug/bringup/{date}_{args.label}_{commit[:7]}'
assert not out.exists()
archive=out/'fit_evidence'
archive.mkdir(parents=True)
for source in list((stage/'output_files').glob('RabbitPunch.*'))+list((stage/'output_files').glob('*.json'))+[stage/'BUILT_COMMIT',stage/'q_staged.log']:
    if source.is_file() and source.suffix not in ('.sof','.pof'):
        shutil.copy2(source,archive/source.name)
cores=out/'_Arcade/cores'
cores.mkdir(parents=True)
rbf=cores/f'Arcade-RabbitPunch_{date}.rbf'
shutil.copy2(stage/'output_files/RabbitPunch.rbf',rbf)
assert rbf.stat().st_size>1000000
mra_records=[]
for source in (root/'releases/_dev/cheats').rglob('*.mra'):
    relative=source.relative_to(root/'releases/_dev/cheats')
    target=out/'_Arcade'/relative
    target.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(source,target)
    mra_records.append(dict(path=target.relative_to(out).as_posix(),sha256=sha(target)))
assert len(mra_records)==4
rows=[]
for block in re.split(r'\n\s*\n',(stage/'output_files/RabbitPunch.sta.summary').read_text()):
    kind=re.search(r'Type\s*:\s*(.+)',block)
    slack=re.search(r'Slack\s*:\s*(-?[\d.]+)',block)
    if kind and slack:
        rows.append((kind[1].strip(),float(slack[1])))
minimum={kind:min(slack for name,slack in rows if kind in name) for kind in ('Setup','Hold','Recovery','Removal','Minimum Pulse Width') if any(kind in name for name,slack in rows)}
(out/'README.txt').write_text('Rabbit Punch / Rabio Lepus cheats candidate\n\nCopy the contents of _Arcade to your MiSTer _Arcade folder. Replace both game MRAs as well as the RBF; the Cheats submenu uses code definitions from these MRAs. No ROM files are included.\n\nCheats > offers Infinite Missiles, Infinite Lives and Infinite Energy/Shield for each player. Enable/disable independently. Hold SS with Left/Right to select the savestate slot, Down to save or Up to restore. Each accepted SS + Left/Right change shows a brief Savestate slot 1-4 popup and updates the OSD slot. SS + Up shows Loading state 1-4 when restore starts. Existing savestate image compatibility is retained.\n\nMAME 0.289 and native VHDL simulations pass; full fitted timing passes. Cheats have not yet been checked on physical MiSTer hardware. Test both sets, toggle each cheat, disable them again, and save/restore with a cheat enabled. Cheat choices follow the current menu selection rather than the saved game.\n\nSource '+commit+', Quartus 17.0.2 Lite, seed '+str(seed)+'. See manifest.json for hashes and timing.\n')
report=dict(accepted=True,commit=commit,revision='RabbitPunch',seed=seed,
    rbf=rbf.relative_to(root).as_posix(),rbf_sha256=sha(rbf),timing_checks=len(rows),minimum_slack_ns=minimum,
    mras=mra_records,source_line_ending_equivalence=line_ending_equivalence,hardware_verified=False,published=False,deployed=False,
    scope='Private source-matched full fitted cheats candidate. All reported timing checks, required hierarchy, framework coverage scope, fitted clock and state resource checks pass. No physical cheat validation, publication or deployment.',
    files={p.relative_to(out).as_posix():sha(p) for p in out.rglob('*') if p.is_file()})
(out/'manifest.json').write_text(json.dumps(report,indent=2)+'\n')
target=root/f'docs/reference/{args.label}_release_seed{seed}_checks.json'
assert not target.exists(), 'Preserve earlier receipts'
target.write_text(json.dumps(report,indent=2)+'\n')
bundle=root/f'debug/bringup/RabbitPunch_{args.label}_{date}'
assert not bundle.with_suffix('.zip').exists()
shutil.make_archive(str(bundle),'zip',out,'_Arcade')
print('CHEATS_CANDIDATE_READY',out)
print('ZIP',bundle.with_suffix('.zip'))
print('MINIMUM SLACK',minimum)
