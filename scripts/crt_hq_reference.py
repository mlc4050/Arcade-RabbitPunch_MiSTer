# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Capture native HQ2x with black blanking, independently of the CRT adapter."""
import hashlib
import json
import re
from run_baselines import run_case

LIBRARIES = [item for lib in ('cyclonev_ver', 'altera_ver', 'altera_lnsim_ver', 'lpm_ver', 'sgate_ver')
             for item in ('-L', lib)]


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pixels_at(path, expected):
    pixels = path.read_text(encoding='utf-8').splitlines()
    if len(pixels) != expected or any(len(pixel) != 6 or
            any(char not in '0123456789ABCDEF' for char in pixel) for pixel in pixels):
        raise SystemExit(f'Invalid HQ2x capture: {path}')
    return pixels


def capture_reference(root, netlist, compact=False, extended=False, wall_timeout=1800):
    width, total, sync_start, sync_end = (64, 96, 80, 88) if compact else (288, 432, 352, 392)
    height = 6 if extended else 1
    name = 'diag_crt_hq_reference_both' + ('' if compact else '_wide') + ('_extended' if extended else '')
    template = root / 'sim/video/video_options_tb.vhd'
    text = template.read_text(encoding='utf-8')
    text = text.replace('use std.env.all;', 'use std.env.all;\nuse std.textio.all;')
    for key, old, value in [('VISIBLE_WIDTH', 32, width), ('TOTAL_WIDTH', 48, total),
                            ('HORIZONTAL_SYNC_START', 40, sync_start), ('HORIZONTAL_SYNC_END', 44, sync_end)]:
        text, count = re.subn(r'(GINT_' + key + r'\s*:\s*\w+\s*:=\s*)' + str(old) + r'\b',
                             lambda match: match[1] + str(value), text)
        assert count == 1, key
    if extended:
        for key, old, value in [('VISIBLE_HEIGHT', 1, 6), ('TOTAL_HEIGHT', 4, 12),
                                ('VERTICAL_SYNC_START', 2, 8), ('VERTICAL_SYNC_END', 3, 10)]:
            text, count = re.subn(r'(GINT_' + key + r'\s*:\s*\w+\s*:=\s*)' + str(old) + r'\b',
                                 lambda match: match[1] + str(value), text)
            assert count == 1, key
    for colour, value in [('red', '31'), ('green', '79'), ('blue', 'C5')]:
        original = 'su8_' + colour + ' <= x"' + value + '";'
        assert text.count(original) == 1
        text = text.replace(original, 'su8_' + colour + ' <= x"' + value +
                            '" when s_vb = \'0\' and s_hb = \'0\' else (others => \'0\');')
    start = text.index('                assert (su8_output_red = x"31"')
    end = text.index('severity failure;', start) + len('severity failure;')
    text = text[:start] + '''                write(v_line, to_hstring(su8_output_red & su8_output_green & su8_output_blue));
                writeline(v_pixels, v_line);''' + text[end:]
    text = text.replace('    monitor : process\n', '''    monitor : process
        file v_pixels : text open write_mode is "pixels.hex";
        variable v_line : line;
''')
    marker = 'HQ_REFERENCE_BOTH_CAPTURE_PASS'
    text = text.replace('VIDEO_OPTIONS_PASS', marker)
    bench = root / 'debug' / (name + '_tb.vhd')
    if not bench.exists() or bench.read_text(encoding='utf-8') != text:
        bench.write_text(text, encoding='utf-8')
    sources = [netlist, bench.relative_to(root).as_posix()]
    hashes = {source: sha256(root / source) for source in sources}
    metadata = root / 'debug' / (name + '_checks.json')
    capture = root / 'debug/baselines' / name / 'pixels.hex'
    result = json.loads(metadata.read_text(encoding='utf-8')) if metadata.exists() else None
    cached = False
    if result and result.get('source_sha256') == hashes and capture.exists():
        log = root / result['log']
        transcript = log.read_text(encoding='utf-8') if log.exists() else ''
        cached = marker in transcript and not re.search(r'\*\* (?:Fatal|Error|Failure):', transcript)
        for key, path in [('pixels_sha256', capture), ('log_sha256', log)]:
            if key in result and result[key] != sha256(path):
                cached = False
    if not cached:
        result = run_case(name, sources, 'video_options_tb', '10 ms', marker,
                          sim_args=LIBRARIES + ['-gGINT_MODE=2'], wall_timeout=wall_timeout)
    assert hashes == {source: sha256(root / source) for source in sources}
    pixels = pixels_at(capture, 4 * width * height)
    result.update(source_sha256=hashes, pixels=len(pixels), unknown_pixels=0,
                  pixels_sha256=sha256(capture), log_sha256=sha256(root / result['log']),
                  template_sha256=sha256(template), visible=[width, height],
                  scope='Native qualified HQ2x capture with black horizontal and vertical blanking; no CRT adapter. Framework reference, not unfiltered MAME.')
    metadata.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(f'HQ2x reference: {len(pixels)} known pixels; cached={cached}', flush=True)
    return pixels, result
