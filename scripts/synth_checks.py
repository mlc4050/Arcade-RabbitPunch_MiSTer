"""Standalone block checks invoked only through the staged-build snapshot."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

from coretools import core_root, NO_WINDOW
from hwlock import require_no_jtag


def run_memory(stage, quartus_bin, stamp):
    stage=Path(stage).resolve()
    if stage.parent!=core_root().resolve() or stage.name!="build":
        raise SystemExit("Memory check must run in the core's staged build checkout")
    require_no_jtag("Rabbit Punch standalone memory fit")
    project=stage/"rtl/synth_check/memory"
    marker=stage/".build_running"
    log_path=stage/"q_memory_check.log"
    scratch=core_root()/".local/quartus"
    env=dict(os.environ)
    # Scope application scratch redirection to this child; the shared JTAG guard
    # above still reads the normal machine-wide marker location.
    for key,folder in (("TEMP","tmp"),("TMP","tmp"),("TMPDIR","tmp"),
                       ("APPDATA","appdata"),("LOCALAPPDATA","localappdata"),
                       ("USERPROFILE","profile")):
        path=scratch/folder
        path.mkdir(parents=True,exist_ok=True)
        env[key]=str(path)
    marker.write_text(stamp,encoding="utf-8")
    try:
        with log_path.open("w",encoding="utf-8") as log:
            result=subprocess.run([str(Path(quartus_bin)/"quartus_sh.exe"),"--flow","compile","memory_check"],
                                  cwd=project,env=env,stdout=log,stderr=subprocess.STDOUT,**NO_WINDOW)
    finally:
        marker.unlink(missing_ok=True)
    log=log_path.read_text(encoding="utf-8",errors="replace")
    if result.returncode or "Full Compilation was successful" not in log:
        print("\n".join(log.splitlines()[-35:]))
        raise SystemExit(f"Standalone memory compile failed: {log_path}")
    output=project/"output_files"
    fit=(output/"memory_check.fit.summary").read_text(encoding="utf-8",errors="replace")
    bits=re.search(r"Total block memory bits\s*:\s*([\d,]+)",fit)
    if not bits or int(bits[1].replace(",",""))!=835584:
        raise SystemExit("Memory bits missing, duplicated, or implemented outside block RAM; inspect fit reports")
    hierarchy=(output/"memory_check.map.rpt").read_text(encoding="utf-8",errors="replace")
    if any(name not in hierarchy for name in ("bitmap","sprites","tiles","palette","work_ram")):
        raise SystemExit("A required RAM bank disappeared during synthesis")
    summary=(output/"memory_check.sta.summary").read_text(encoding="utf-8",errors="replace")
    timings=[]
    for block in summary.split("\n\n"):
        kind=re.search(r"Type\s*:\s*(.+)",block)
        slack=re.search(r"Slack\s*:\s*(-?[\d.]+)",block)
        if kind and slack:
            timings.append({"type":kind[1].strip(),"slack_ns":float(slack[1])})
    if not timings or any(item["slack_ns"]<0 for item in timings):
        raise SystemExit(f"Memory timing not verified or negative: {timings}")
    report={"commit":stamp.split()[0],"device":"5CSEBA6U23I7","project":"memory_check",
            "constraint_mhz":48,"seed":1,"memory_bits":835584,"timings":timings,
            "fit_summary":fit.splitlines(),"log_sha256":hashlib.sha256(log_path.read_bytes()).hexdigest(),
            "scope":"Standalone memory block with virtual I/O; not a complete core or hardware release"}
    destination=core_root()/"debug/memory_synth.json"
    destination.parent.mkdir(parents=True,exist_ok=True)
    destination.write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    print("PASS standalone memory fit: 835584 RAM bits; all reported timing checks nonnegative")
    print(destination)
    return 0
