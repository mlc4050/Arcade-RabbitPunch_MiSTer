"""Pin selected local CPU/JTFRAME copies without modifying donor repositories."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

from coretools import core_root, NO_WINDOW


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    for name in ("seta", "psikyo", "gx"):
        ap.add_argument("--" + name, type=Path, required=True)
    args = ap.parse_args()
    root = core_root()
    donors = {key: getattr(args, key) for key in ("seta", "psikyo", "gx")}
    jobs = []
    for name in ("TG68K_Pack.vhd", "TG68K_ALU.vhd", "TG68KdotC_Kernel.vhd", "TG68K.vhd"):
        jobs.append(("seta", f"rtl/cpu/tg68k/{name}", f"rtl/cpu/tg68k/{name}"))
    jobs.append(("seta", "rtl/cpu/tg68k/PROVENANCE.md", "rtl/cpu/tg68k/DONOR_NOTES.md"))
    for name in ("T80_Pack.vhd", "T80_Reg.vhd", "T80_MCode.vhd", "T80_ALU.vhd", "T80.vhd", "T80se.vhd"):
        jobs.append(("psikyo", f"rtl/cpu/t80/{name}", f"rtl/cpu/t80/{name}"))
    jobs.append(("psikyo", "rtl/cpu/t80/PROVENANCE.md", "rtl/cpu/t80/DONOR_NOTES.md"))
    for name in ("jtframe_obj_buffer.v", "jtframe_dual_ram.v"):
        jobs.append(("gx", f"rtl/jtframe/{name}", f"rtl/jtframe/{name}"))
    jobs.append(("gx", "rtl/jtframe/jtframe_draw_upstream_reference.v", "rtl/jtframe/jtframe_draw.v"))
    jobs.append(("gx", "rtl/jtframe/PROVENANCE.md", "rtl/jtframe/DONOR_NOTES.md"))
    jobs += [
        ("psikyo", "sim/tg68k_spike/tb_tg68k_boot.vhd", "sim/vendor/tg68k/tb_tg68k_boot.vhd"),
        ("psikyo", "sim/t80_spike/tb_t80_boot.vhd", "sim/vendor/t80/tb_t80_boot.vhd"),
    ]
    for suffix in ("smoke", "ccr", "pace"):
        jobs.append(("seta", f"sim/tg68k_{suffix}_tb/tb_tg68k_{suffix}.sv",
                     f"sim/vendor/tg68k/tb_tg68k_{suffix}.sv"))
    for name in ("fx68k.sv", "fx68kAlu.sv", "uaddrPla.sv", "microrom.mem", "nanorom.mem", "LICENSE", "README.md"):
        jobs.append(("seta", f"rtl/cpu/fx68k/{name}", f"rtl/cpu/fx68k/{name}"))
    jobs.append(("seta", "rtl/cpu/fx68k/PROVENANCE.md", "rtl/cpu/fx68k/DONOR_NOTES.md"))
    jobs.append(("seta", "sim/fx68k_pace_tb/tb_fx68k_pace.sv", "sim/vendor/fx68k/tb_fx68k_pace.sv"))
    metadata = {"donors": {}, "files": []}
    for key, repo in donors.items():
        paths = [src for donor, src, _ in jobs if donor == key]
        def git(*argv):
            return subprocess.check_output(["git", "-C", str(repo), *argv], text=True, **NO_WINDOW).strip()
        status = git("status", "--porcelain", "--", *paths)
        if status:
            raise SystemExit(f"Selected donor files have local changes: {key}\n{status}")
        metadata["donors"][key] = {"directory": repo.name, "commit": git("rev-parse", "HEAD"),
                                   "selected_files_clean": True}
    for key, source, target in jobs:
        src, dst = donors[key] / source, root / target
        digest = hashlib.sha256(src.read_bytes()).hexdigest()
        if dst.exists() and hashlib.sha256(dst.read_bytes()).hexdigest() != digest:
            raise SystemExit(f"Refusing to overwrite a different local file: {dst}")
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)
        metadata["files"].append({"donor": key, "source": source, "target": target, "sha256": digest})
    out = root / "docs/reference/vendor_manifest.json"
    out.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(f"Copied and SHA256-pinned {len(jobs)} files; donors unchanged")


if __name__ == "__main__":
    main()
