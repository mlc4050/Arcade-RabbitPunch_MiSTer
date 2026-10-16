"""Verify neutral MAME settings reproduce the original attract references."""
import hashlib
import json
import subprocess
import sys

from coretools import core_root, NO_WINDOW
from png_rgb import read_rgb


def main():
    root = core_root()
    reports = []
    for game in ("rabiolep", "rpunch"):
        subprocess.run(
            [sys.executable, "-B", str(root / "scripts/mame_capture.py"), game,
             "--frame", "1200", "--name", "neutral"],
            cwd=root, check=True, timeout=180, **NO_WINDOW)
        original = root / "debug" / f"{game}-attract"
        neutral = root / "debug" / f"{game}-neutral"
        old_image = read_rgb(original / "reference.png")
        new_image = read_rgb(neutral / "reference.png")
        if new_image != old_image:
            raise SystemExit(f"{game}: neutral settings changed the reference pixels")
        names = sorted(path.name for path in original.glob("*.bin"))
        if not names or names != sorted(path.name for path in neutral.glob("*.bin")):
            raise SystemExit(f"{game}: capture dump set changed")
        for name in names:
            if (original / name).read_bytes() != (neutral / name).read_bytes():
                raise SystemExit(f"{game}: neutral settings changed {name}")
        reports.append({
            "set": game, "frame": 1200, "pixels": new_image[0] * new_image[1],
            "rgb_sha256": hashlib.sha256(new_image[2]).hexdigest(),
            "comparison": "identical", "dumps_compared": names,
            "options": "noreadconfig, brightness=1, contrast=1, gamma=1, nohlsl_enable, video=none",
        })
        print(f"PASS {game}: neutral settings preserve every RGB pixel and {len(names)} dumps", flush=True)
    (root / "docs/reference/neutral_settings_checks.json").write_text(
        json.dumps(reports, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
