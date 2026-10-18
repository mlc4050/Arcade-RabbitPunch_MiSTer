# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Qualify fast logical RAM against native primitives and existing VHDL contracts."""
from pathlib import Path
import hashlib,json,subprocess,time
from coretools import core_root, NO_WINDOW, setting
from hwlock import require_no_jtag
from run_baselines import run_case


def main():
    root=core_root();require_no_jtag('Fast logical RAM contract qualification');out=root/'debug/fast_ram_compare';out.mkdir(exist_ok=True)
    for width in (8,16):
        source=root/f'sim/fast/rabbitpunch_ram{width}_model.vhd'
        text=source.read_text().replace(f'entity rabbitpunch_ram{width} is',f'entity rabbitpunch_ram{width}_model is').replace(f'of rabbitpunch_ram{width} is',f'of rabbitpunch_ram{width}_model is')
        (out/f'ram{width}_model.vhd').write_text(text)
    s=(root/'sim/memory/ram_powerup_tb.vhd').read_text().replace('ram_powerup_tb','fast_ram_compare_tb').replace('RAM_POWERUP_PASS','FAST_RAM_NATIVE_COMPARE_PASS')
    s=s.replace('    signal s_clk :', '    signal su16_model_cpu_data, su16_model_view_data : t_words;\n    signal su8_model_cpu_data, su8_model_view_data : unsigned(7 downto 0);\n    signal s_clk :')
    start=s.index('        ram : entity work.rabbitpunch_ram16');end=s.index('            );',start)+len('            );')
    clone=s[start:end].replace('ram : entity work.rabbitpunch_ram16','model_ram : entity work.rabbitpunch_ram16_model').replace('=> su16_cpu_data(','=> su16_model_cpu_data(').replace('=> su16_view_data(','=> su16_model_view_data(')
    s=s[:end]+'\n'+clone+s[end:]
    start=s.index('    byte_ram : entity work.rabbitpunch_ram8');end=s.index('        );',start)+len('        );')
    clone=s[start:end].replace('byte_ram : entity work.rabbitpunch_ram8','model_byte_ram : entity work.rabbitpunch_ram8_model').replace('=> su8_cpu_data', '=> su8_model_cpu_data').replace('=> su8_view_data', '=> su8_model_view_data')
    s=s[:end]+'\n'+clone+s[end:]
    monitor='''    compare_read_contract : process
        begin
            wait until falling_edge(s_clk);
            if (s_write16 = '0') then
                assert (su16_cpu_data = su16_model_cpu_data)
                    report "Fast/native RAM16 CPU read or retained output differs" severity failure;
            end if;
            if (s_view_enable = '1') then
                assert (su16_view_data = su16_model_view_data and su8_view_data = su8_model_view_data)
                    report "Fast/native RAM inspection read differs" severity failure;
            end if;
            if (s_write8 = '0') then
                assert (su8_cpu_data = su8_model_cpu_data)
                    report "Fast/native RAM8 CPU read or retained output differs" severity failure;
            end if;
        end process;
    '''
    s=s.replace('    process\n        variable vu16_expected', monitor+'    process\n        variable vu16_expected')
    (out/'fast_ram_compare_tb.vhd').write_text(s)
    sources=['rtl/rabbitpunch_ram16.vhd','rtl/rabbitpunch_ram8.vhd']+[str(p.relative_to(root)) for p in (out/'ram16_model.vhd',out/'ram8_model.vhd',out/'fast_ram_compare_tb.vhd')]
    r=run_case('fast_ram_native_compare',sources,'fast_ram_compare_tb','100 us','FAST_RAM_NATIVE_COMPARE_PASS',wall_timeout=1200)
    r.update(source_sha256={p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in sources},scope='Simultaneous logical-model/native-Intel RAM comparison under the existing exhaustive 256-address primitive startup and independent-byte-lane workload, both read ports and output-enable hold. Native read-during-write/collision/unknown behavior is excluded and the logical models reject active same-word mixed-port writes. Not physical M10K or a complete system proof.')
    r.update(log_sha256=hashlib.sha256((root/r['log']).read_bytes()).hexdigest(),
        model_source_sha256={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in ('sim/fast/rabbitpunch_ram16_model.vhd','sim/fast/rabbitpunch_ram8_model.vhd')})
    ghdl=Path(setting('GHDL_EXE',str(root/'.local/tools/ghdl-6.0.0/bin/ghdl.exe')))
    ghdl_out=out/'ghdl';ghdl_out.mkdir(exist_ok=True)
    ghdl_sources=['sim/fast/rabbitpunch_ram16_model.vhd','sim/fast/rabbitpunch_ram8_model.vhd','rtl/rabbitpunch_layout.vhd','rtl/rabbitpunch_decode.vhd','rtl/rabbitpunch_board_memory.vhd','rtl/rabbitpunch_memory.vhd','sim/memory/ram_powerup_tb.vhd','sim/memory/memory_powerup_tb.vhd']
    hashes={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in ghdl_sources}
    commands=[['-a','--std=08',str(root/name)] for name in ghdl_sources]
    commands += [['-r','--std=08',name,'--assert-level=error','--stop-time=10ms'] for name in ('ram_powerup_tb','memory_powerup_tb')]
    logs=[]
    for args in commands:
        started=time.monotonic()
        result=subprocess.run([str(ghdl),*args],cwd=ghdl_out,capture_output=True,text=True,timeout=120,**NO_WINDOW)
        logs.append(dict(args=args,returncode=result.returncode,seconds=time.monotonic()-started,stdout=result.stdout,stderr=result.stderr))
        (ghdl_out/'commands.json').write_text(json.dumps(logs,indent=2)+'\n')
        assert result.returncode==0,result.stdout+result.stderr
        if '-r' in args:
            marker='MEMORY_POWERUP_PASS' if args[2]=='memory_powerup_tb' else 'RAM_POWERUP_PASS'
            assert marker in result.stdout
            print('PASS logical RAM contract:',args[2],flush=True)
    assert hashes=={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in ghdl_sources}
    report=dict(accepted=True,native_comparison=r,logical_checks=logs,source_sha256=hashes,
        runner_sha256=hashlib.sha256((root/'scripts/run_fast_ram_tests.py').read_bytes()).hexdigest(),
        scope='Simulation-only RAM abstractions match the native Intel primitive for the exact dual-instance 256-address workload, and pass existing all-bank startup/byte-lane contracts. Read timing, enabled output hold and configured logical contents only. Collision writes are rejected; X/uninitialized, physical M10K and electrical behavior are not modeled. Production source lists keep the real Intel wrappers.')
    (root/'docs/reference/fast_ram_contract_checks.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS fast RAM: native side-by-side comparison plus 104553 board-memory checks',flush=True)


if __name__ == '__main__':
    main()

