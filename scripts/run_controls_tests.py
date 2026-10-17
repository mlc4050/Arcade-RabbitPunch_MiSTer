# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Check board-input and pause composition, preserving DIPs across game reset."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
root=core_root()
sources=['rtl/mame_keys.sv','rtl/rabbitpunch_keys.vhd','rtl/rabbitpunch_inputs.vhd','rtl/rabbitpunch_pause.vhd','rtl/rabbitpunch_controls.vhd','sim/board/controls_tb.vhd']
result=run_case('controls',sources,'controls_tb','1 ms','CONTROLS_PASS')
result.update(source_sha256={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources},
    log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
    scope='Connected MAME keyboard/pad mapper and pause owners: pad-to-keyboard toggle, held-key unrelated input, OSD/state pause, cold-versus-game reset DIP preservation and original freeze pin held inactive; no physical controls/native HPS/gameplay/CPU-drain proof')
(root/'docs/reference/controls_checks.json').write_text(json.dumps(result,indent=2)+'\n')
