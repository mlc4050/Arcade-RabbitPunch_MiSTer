"""Validate per-field write sweeps and retain their non-ROM histograms."""
import hashlib
import json

from coretools import core_root, mame_version
from write_timing import parse


def main():
    root = core_root()
    if mame_version() != "0289":
        raise SystemExit("Write timing reference requires pinned MAME 0289")
    destination = root / "docs/reference/write_timing"
    destination.mkdir(parents=True, exist_ok=True)
    reports = []
    for game in ("rabiolep", "rpunch"):
        for mode in ("attract", "play"):
            path = root / "debug/wtiming" / f"{game}_fields_{mode}.txt"
            legacy = root / "debug/wtiming" / f"{game}{'_play' if mode == 'play' else ''}.txt"
            data, previous = parse(path), parse(legacy)
            if data["frames"] != 1800 or data["vtotal"] != 224 or data["vbstart"] != 216:
                raise SystemExit(f"Unexpected sweep coverage: {path}")
            for kind in ("hist", "last"):
                for name, values in data[kind].items():
                    if len(values) != data["vtotal"] or any(value < 0 for value in values):
                        raise SystemExit(f"Invalid histogram: {path}/{name}")
                for name, values in previous[kind].items():
                    if data[kind][name] != values:
                        raise SystemExit(f"Neutral settings changed {path}/{kind}/{name}")
            hist = data["hist"]
            tile_sum = [a + b for a, b in zip(hist["tile_bg0"], hist["tile_bg1"])]
            if tile_sum != hist["videoram"]:
                raise SystemExit(f"Tile field partition mismatch: {path}")
            sprite_sum = [sum(values) for values in zip(
                hist["sprite_y"], hist["sprite_code"], hist["sprite_x"], hist["sprite_unused"])]
            outside = [total - counted for total, counted in zip(hist["spriteram"], sprite_sum)]
            if any(value < 0 for value in outside):
                raise SystemExit(f"Sprite fields counted twice: {path}")
            fields = {}
            for name, values in hist.items():
                relative = values[216:] + values[:216]
                total = sum(relative)
                fields[name] = {
                    "writes": total,
                    "vblank_writes": sum(relative[:8]),
                    "first_24_lines_writes": sum(relative[:24]),
                    "relative_lines": [index for index, count in enumerate(relative) if count],
                }
            saved = destination / path.name
            saved.write_bytes(path.read_bytes())
            reports.append({
                "set": game, "mode": mode, "frames": 1800,
                "skip_frames": 600 if mode == "attract" else 1500,
                "coin_frame": 0 if mode == "attract" else 600,
                "mameversion": "0289", "vtotal": 224, "vblank_start": 216,
                "raw": str(saved.relative_to(root)),
                "raw_sha256": hashlib.sha256(saved.read_bytes()).hexdigest(),
                "coarse_histograms": "identical to prior captures",
                "writes_outside_first_64_sprite_slots": sum(outside), "fields": fields,
                "scope": "MAME synthetic raster; scripted play can include course selection, deaths and continue prompts",
            })
            print(f"PASS {game}/{mode}: field partitions and original coarse histograms agree")
    (root / "docs/reference/write_timing_checks.json").write_text(
        json.dumps(reports, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
