# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""One-line read-only RPUN telemetry through the shared JTAG guard.

    python scripts/probe.py
    python scripts/probe.py --fields frames pll_locked underflow_events

Counters survive gameplay reset. The RPUN source bus has no write/clear actions.
"""
import argparse
import re
import sys
from identity import prefix
from read_issp import read as read_raw

DEFAULT_INSTANCE = 'RPUN'


def decode(output):
    fields = dict(re.findall(r'^\s{2}([a-z][a-z0-9_]*)\s+(0x[0-9A-Fa-f]+|[0-9]+|yes|no)\s*$', output, re.MULTILINE))
    if fields.get('core_tag') != '0x5250554E' or fields.get('layout_version') != '1':
        raise SystemExit('No valid RPUN layout decoded; retain the raw log and check the loaded build')
    return fields


def read(instance=DEFAULT_INSTANCE):
    result = read_raw(instance, capture=True)
    output = result.stdout + result.stderr
    if result.returncode:
        raise SystemExit(f'Probe read failed ({result.returncode}):\n{output}')
    return decode(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--instance', default=DEFAULT_INSTANCE)
    parser.add_argument('--fields', nargs='+')
    args = parser.parse_args()
    values = read(args.instance)
    keys = args.fields or list(values)
    unknown = set(keys) - values.keys()
    if unknown:
        parser.error('Unknown fields: ' + ', '.join(sorted(unknown)))
    print(prefix() + ' '.join(f'{key}={values[key]}' for key in keys))
    return 0


if __name__ == '__main__':
    sys.exit(main())
