"""Run the unchanged JT7759 donor smoke with a generated, original sample ROM."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case


def synthetic_rom():
    data = bytearray(1 << 17)
    data[:5] = bytes((3, 0x5a, 0xa5, 0x69, 0x55))
    for index in range(4):
        offset = 0x20 + index * 0x10
        data[5+index*2:7+index*2] = offset.to_bytes(2, 'big')
        address = offset*2 + 1
        data[address:address+5] = bytes((0x89, 3, 0x77, 0xff, 0))
    return data


def main():
    root = core_root()
    manifest = json.loads((root/'docs/reference/vendor_manifest.json').read_text())
    files = [row for row in manifest['files'] if row['donor'] == 'upd7759']
    for row in files:
        assert hashlib.sha256((root/row['target']).read_bytes()).hexdigest() == row['sha256']
    sources = [row['target'] for row in files if row['target'].endswith('.v')]
    out = root/'debug/baselines/jt7759_donor'
    out.mkdir(parents=True, exist_ok=True)
    data = synthetic_rom()
    (out/'test.rom').write_bytes(data)
    # Preserve the failed automatic multi-sample fixture transcript. The
    # independent VHDL test covers two different complete sample commands.
    previous = out/'result.log'
    if previous.exists() and 'Donor sample failed to complete' in previous.read_text():
        (out/'automatic_stall.log').write_text(previous.read_text())
    setup = ('force -freeze /test/stn 1', 'run 50 us',
             'force -freeze /test/stn 0', 'run 10 us',
             'force -freeze /test/stn 1', 'run 4 ms',
             'if {[examine -radix unsigned /test/busyn] != 1} {error "Donor first sample failed to complete"}')
    result = run_case('jt7759_donor', sources, 'test', '1 ns', 'jt7759: sample done',
                      wall_timeout=120, setup_commands=setup)
    result.update(source_sha256={name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources},
        synthetic_rom_sha256=hashlib.sha256(data).hexdigest(),
        log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
        scope='Original donor chip/test/ROM model with simulator-controlled start: first synthetic sample completes and returns idle; original automatic multi-sample fixture stalls, so it is not a retrigger proof. Separate VHDL baseline covers two different complete commands at 640 kHz; no PCM-value/game/wrapper proof')
    (root/'docs/reference/jt7759_donor_checks.json').write_text(json.dumps(result, indent=2)+'\n')


if __name__ == '__main__':
    main()
