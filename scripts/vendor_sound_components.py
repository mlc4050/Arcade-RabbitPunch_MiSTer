"""Pin an unchanged local JT51 evaluation copy and its simulation-only helpers."""
import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path
from coretools import core_root, NO_WINDOW


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ym2151-donor", type=Path, required=True)
    parser.add_argument("--jt51-verification", type=Path, required=True)
    args = parser.parse_args()
    root = core_root()
    donors = {"ym2151": args.ym2151_donor, "jt51_verification": args.jt51_verification}
    jobs = [("ym2151", f"rtl/third_party/jt51/hdl/{name}", f"rtl/sound/jt51/hdl/{name}")
            for name in (args.ym2151_donor / "rtl/third_party/jt51/hdl/jt51.f").read_text().splitlines()
            if name.endswith(".v") and not name.startswith("../")]
    jobs += [("ym2151", f"rtl/third_party/jt51/{name}", f"rtl/sound/jt51/{name}") for name in ("LICENSE", "README.md")]
    jobs += [("jt51_verification", f"ver/common/{name}", f"sim/vendor/jt51/{name}") for name in ("sep32.v", "sep32_cnt.v")]
    destination = root / "docs/reference/vendor_manifest.json"
    metadata = json.loads(destination.read_text())
    targets = {target for donor, source, target in jobs}
    metadata["files"] = [row for row in metadata["files"] if row["target"] not in targets]
    for donor, repo in donors.items():
        def git(*arguments):
            return subprocess.check_output(["git", "-C", str(repo), *arguments], text=True, **NO_WINDOW).strip()
        paths = [source for key, source, target in jobs if key == donor]
        assert not git("status", "--porcelain", "--", *paths), "Selected sound donor files have local changes"
        metadata["donors"][donor] = dict(directory=repo.name, commit=git("rev-parse", "HEAD"), selected_files_clean=True)
    for donor, source, target in jobs:
        original, copied = donors[donor] / source, root / target
        digest = hashlib.sha256(original.read_bytes()).hexdigest()
        if copied.exists() and hashlib.sha256(copied.read_bytes()).hexdigest() != digest:
            raise SystemExit(f"Refusing to overwrite changed copy: {copied}")
        copied.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(original, copied)
        metadata["files"].append(dict(donor=donor, source=source, target=target, sha256=digest))
    destination.write_text(json.dumps(metadata, indent=2) + "\n")
    commit = metadata["donors"]["ym2151"]["commit"]
    helper_commit = metadata["donors"]["jt51_verification"]["commit"]
    (root / "rtl/sound/jt51/PROVENANCE.md").write_text(f"""# JT51 evaluation copy

Upstream: https://github.com/jotego/jt51, Jose Tejada Gomez, GPL-3.0-or-later.
Copied unchanged from Arcade-JalecoMS1BCD_MiSTer at {commit}; the selected files
are clean in that donor. Its exact upstream JT51 revision is not recorded here.
The native HDL dependency closure is selected by its jt51.f list. LICENSE and
README are preserved. All file SHA256s are in docs/reference/vendor_manifest.json.

SIMULATION diagnostic helpers sep32.v and sep32_cnt.v are copied unchanged from
the local complete upstream JT51 checkout at {helper_commit}, under
sim/vendor/jt51. They are not chip RTL or synthesis dependencies. That older
checkout's top-level test uses DAC ports absent from this selected donor; do
not silently mix its chip RTL with this version. The selected donor carries no
original regression suite. New VHDL baseline tests must identify their scope;
vendoring alone is not validation or game sound integration.
""")
    print(f"Pinned {len(jobs)} unchanged JT51/dependency/helper files; donors unchanged")


if __name__ == "__main__":
    main()
