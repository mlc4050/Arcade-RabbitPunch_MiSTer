# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Run the VHDL host protocol bench against the synthesized unchanged hps_io boundary.

ModelSim 10.5b cannot parse the current sys/hps_io.sv forward declarations.
Quartus emits a compatible functional netlist; sys sources remain unchanged.
Build --synth-check host first. This does not simulate a replacement host model.
"""
import subprocess
import sys
from coretools import core_root, NO_WINDOW
result=subprocess.run([sys.executable,str(core_root()/'scripts/run_netlist_tests.py'),'host'],capture_output=True,text=True,**NO_WINDOW)
print(result.stdout,end='')
print(result.stderr,end='',file=sys.stderr)
result.check_returncode()
