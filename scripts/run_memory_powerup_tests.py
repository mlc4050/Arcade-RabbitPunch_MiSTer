# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Check every mapped RAM word without simulator memory deposits."""
import argparse
import hashlib
import json
from coretools import core_root
from run_baselines import run_case


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--boundary", action="store_true")
    parser.add_argument("--sampled", action="store_true", help="Replay the netlist boundary-sampling contract")
    args = parser.parse_args()
    root = core_root()
    sources = ["rtl/rabbitpunch_layout.vhd", "rtl/rabbitpunch_decode.vhd",
               "rtl/rabbitpunch_ram16.vhd", "rtl/rabbitpunch_board_memory.vhd",
               "rtl/rabbitpunch_memory.vhd", "sim/memory/memory_powerup_tb.vhd"]
    if args.boundary:
        sources.insert(-1, "rtl/synth_check/memory/memory_check.vhd")
    variant = "memory_powerup_boundary" if args.boundary else "memory_powerup"
    if args.sampled:
        variant += "_sampled"
    sim_args = []
    if args.boundary:
        sim_args.append("-gEVALUATION_BOUNDARY=true")
    if args.sampled:
        sim_args.append("-gEXHAUSTIVE=false")
    hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
    result = run_case(variant, sources, "memory_powerup_tb", "10 ms",
                      "MEMORY_POWERUP_PASS", wall_timeout=300,
                      sim_args=sim_args)
    if hashes != {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}:
        raise SystemExit("Memory sources changed during simulation")
    result.update(evaluation_boundary=args.boundary, exhaustive=not args.sampled, source_sha256=hashes,
                  log_sha256=hashlib.sha256((root / result["log"]).read_bytes()).hexdigest(),
                  scope=("First/last of every 256-word region read" if args.sampled else "All 52224 mapped RAM words read") + " via CPU and inspection before any write; bitmap FFFF, other banks zero. Upper/lower masked writes at first/middle/last addresses preserve the other byte. No RAM deposits; no physical hardware measurement.")
    (root / f"docs/reference/{variant}_checks.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
