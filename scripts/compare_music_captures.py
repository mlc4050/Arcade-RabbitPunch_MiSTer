# SPDX-License-Identifier: GPL-3.0-or-later
"""Audit preserved executing-game music traces and onset-aligned WAVs against MAME.

Requires NumPy. Inputs are private captures, verified against their original
qualification reports before analysis. Spectral/envelope metrics are descriptive;
this script does not turn them into a claim of bit-exact or PCB-accurate audio.
"""
import argparse
import hashlib
import json
from pathlib import Path
import wave

import numpy as np


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def decode(path, mame):
    selected = None
    events, commands, controls = [], [], []
    for line in path.open(encoding='utf-8'):
        fields = line.split()
        if mame:
            time = float(fields[0])
            address, data = int(fields[2], 16), int(fields[3], 16)
        else:
            time = None  # Original RTL trace did not record cycle timestamps.
            address, data = int(fields[0], 16), int(fields[2], 16)
        if address == 0xf000:
            selected = data
        elif address == 0xf001:
            assert selected is not None, 'YM data without a register address'
            events.append((selected, data, time))
        elif address == 0xf600:
            commands.append(data)
        elif address == 0xf400:
            controls.append(data)
    return events, commands, controls


def sequence(left, right):
    common = next((i for i, (a, b) in enumerate(zip(left, right)) if a != b),
                  min(len(left), len(right)))
    return dict(mame_count=len(left), rtl_count=len(right), matching_prefix=common,
                shorter_is_exact_prefix=common == min(len(left), len(right)),
                first_difference=None if common == min(len(left), len(right)) else
                dict(index=common, mame=left[common], rtl=right[common]))


def read_wav(path):
    with wave.open(str(path), 'rb') as wav:
        assert wav.getnchannels() == 1 and wav.getsampwidth() == 2
        rate = wav.getframerate()
        pcm = np.frombuffer(wav.readframes(wav.getnframes()), dtype='<i2').astype(float)
    return pcm, rate


def waveform(mame, rtl):
    signals, sources = [], []
    duration, rate = 5.9, 48000
    for path in (mame, rtl):
        pcm, original_rate = read_wav(path)
        # Fixed onset rule, not a correlation-optimized fit. Exclude attract audio.
        start_index = 20 * original_rate
        onset = start_index + int(np.flatnonzero(np.abs(pcm[start_index:]) > 128)[0])
        onset_seconds = onset / original_rate
        assert onset_seconds + duration < len(pcm) / original_rate
        times = np.arange(round(duration * rate)) / rate + onset_seconds
        aligned = np.interp(times, np.arange(len(pcm)) / original_rate, pcm)
        signals.append(aligned)
        sources.append(dict(rate_hz=original_rate, duration_seconds=len(pcm)/original_rate,
                            music_onset_seconds=onset_seconds, peak=float(np.max(np.abs(pcm))),
                            clipped_samples=int(np.count_nonzero((pcm == -32768) | (pcm == 32767)))))
    a, b = signals
    def envelope(x):
        return np.sqrt(np.mean(x.reshape(-1, 240)**2, axis=1))
    def spectrum(x):
        windows = np.lib.stride_tricks.sliding_window_view(x, 2048)[::480]
        return np.abs(np.fft.rfft(windows * np.hanning(2048), axis=1))
    ea, eb = envelope(a), envelope(b)
    sa, sb = spectrum(a), spectrum(b)
    cosine = np.sum(sa*sb, axis=1) / np.sqrt(np.sum(sa*sa, axis=1)*np.sum(sb*sb, axis=1))
    rms_a, rms_b = np.sqrt(np.mean(a*a)), np.sqrt(np.mean(b*b))
    return dict(mame=sources[0], rtl=sources[1], compared_seconds=duration,
                common_rate_hz=rate, interpolation='linear, no gain correction or time stretch',
                rms_mame=float(rms_a), rms_rtl=float(rms_b), rms_ratio=float(rms_b/rms_a),
                gain_difference_db=float(20*np.log10(rms_b/rms_a)),
                envelope_window_ms=5, envelope_correlation=float(np.corrcoef(ea, eb)[0, 1]),
                spectral_window_samples=2048, spectral_hop_samples=480,
                mean_spectral_cosine=float(np.mean(cosine)),
                median_spectral_cosine=float(np.median(cosine)),
                scope='Descriptive onset-aligned first gameplay-music excerpt, not a full-track or sample-exact acceptance test.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input-root', type=Path, default=Path('debug/audio_reference'))
    parser.add_argument('--report', type=Path, default=Path('docs/reference/music_comparison_checks.json'))
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    cases = []
    for game in ('rabiolep', 'rpunch'):
        mame = args.input_root / 'mame' / game
        rtl = args.input_root / 'rtl' / game
        mr = json.loads((root / f'docs/reference/music_reference_{game}_checks.json').read_text())
        rr = json.loads((root / f'docs/reference/gameplay_fast_{game}_1800_pad_checks.json').read_text())
        for path, expected in [(mame/'music_writes.txt', mr['files']['music_writes.txt']),
                               (mame/'mame.wav', mr['files']['mame.wav']),
                               (rtl/'rtl_sound_writes.txt', rr['rtl_sound_trace_sha256']),
                               (rtl/'mono.wav', rr['audio']['wav_sha256'])]:
            assert sha(path) == expected, 'Archived capture hash mismatch: ' + str(path)
        left, lc, lf = decode(mame/'music_writes.txt', True)
        right, rc, rf = decode(rtl/'rtl_sound_writes.txt', False)
        def values(events, keep):
            return [(r, v) for r, v, _ in events if keep(r)]
        # Preserve the full raw comparison. Timer control is excluded only in
        # additional diagnostic comparisons; its status/IRQ effects still matter.
        raw = sequence(values(left, lambda r: True), values(right, lambda r: True))
        non_timer = sequence(values(left, lambda r: r != 0x14), values(right, lambda r: r != 0x14))
        voice = sequence(values(left, lambda r: r >= 0x20), values(right, lambda r: r >= 0x20))
        resets = []
        tails = []
        for events in (left, right):
            indexes = [i for i, (r, v, _) in enumerate(events) if (r, v) == (0xff, 0)]
            assert indexes
            resets.append([dict(event_index=i, seconds=events[i][2]) for i in indexes])
            tails.append(values(events[indexes[-1]:], lambda r: r != 0x14))
        gameplay = sequence(*tails)
        assert gameplay['shorter_is_exact_prefix'], 'Gameplay music register sequence differs'
        assert lc == rc, 'ADPCM command sequence differs'
        cases.append(dict(set=game, raw_ym=raw, excluding_timer_control=non_timer,
                          voice_registers=voice, global_register_clear_events=dict(mame=resets[0], rtl=resets[1]),
                          gameplay_after_last_global_clear=gameplay,
                          adpcm_commands=sequence(lc, rc), adpcm_controls=sequence(lf, rf),
                          waveform=waveform(mame/'mame.wav', rtl/'mono.wav'),
                          input_sha256={str(p): sha(p) for p in (mame/'music_writes.txt',mame/'mame.wav',rtl/'rtl_sound_writes.txt',rtl/'mono.wav')}))
        print(game, 'gameplay register prefix', gameplay['matching_prefix'],
              'RMS ratio', round(cases[-1]['waveform']['rms_ratio'], 4),
              'spectral cosine', round(cases[-1]['waveform']['mean_spectral_cosine'], 4), flush=True)
    # Prove that the sequence comparison detects a changed note or missing write.
    assert not sequence([(8, 120), (40, 10)], [(8, 121), (40, 10)])['shorter_is_exact_prefix']
    assert not sequence([(8, 120), (40, 10), (8, 0)], [(8, 120), (8, 0)])['shorter_is_exact_prefix']
    report=dict(cases=cases, runner_sha256=sha(Path(__file__)), numpy_version=np.__version__,
                scope='Retrospective audit of immutable 1800-frame executing-game captures. Original raw inputs and their separate MAME/RTL qualification hashes are checked. No fresh game simulation, full-track match, exact waveform equality, or physical audio gain claim.',
                timer_difference='First raw divergence is YM register 0x14: 0x0A versus 0x2A. Bit 5 clears timer B status; it is not an instrument/note bit. Raw differences remain reported and timer timing is not waived.',
                limitations=['RTL peripheral trace has no event timestamps.',
                             'MAME runs 60 Hz while RTL raster is approximately 60.282 Hz; compare music starts separately.',
                             'US attract sequence diverges before a game-reset command; ordered gameplay music matches the shorter capture.',
                             'Music excerpt is 5.9 seconds, not a complete track.',
                             'Spectral cosine is a similarity metric, not percent hardware accuracy.'])
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')


if __name__ == '__main__':
    main()
