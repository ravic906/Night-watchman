#!/usr/bin/env python3
"""Composes Night Watchman's adaptive score in code and writes it to audio/*.ogg.

Loops are exactly LOOP seconds long. Every sustained frequency fits a whole
number of cycles in the loop, and every effect (echo, reverb, filtered noise)
is applied circularly, so the loops repeat without a click.

Usage:  python3 tools/compose_music.py [--preview PATH.ogg]
Needs:  numpy, ffmpeg (with libvorbis)
"""
import argparse
import os
import subprocess
import tempfile
import wave

import numpy as np

SR = 32000
LOOP = 32.0
N = int(SR * LOOP)
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio")
rng = np.random.default_rng(1913)


def note(name):
    """'D4' -> Hz (A4 = 440)."""
    names = {"C": -9, "C#": -8, "Db": -8, "D": -7, "D#": -6, "Eb": -6, "E": -5, "F": -4,
             "F#": -3, "Gb": -3, "G": -2, "G#": -1, "Ab": -1, "A": 0, "A#": 1, "Bb": 1, "B": 2}
    pitch, octave = name[:-1], int(name[-1])
    return 440.0 * 2 ** ((names[pitch] + 12 * (octave - 4)) / 12)


def q(f):
    """Snap a frequency so it completes whole cycles in the loop."""
    return max(1, round(f * LOOP)) / LOOP


T = np.arange(N) / SR


def osc(f, t=T, harmonics=1, bright=1.0, phase=0.0):
    out = np.zeros_like(t)
    for h in range(1, harmonics + 1):
        out += np.sin(2 * np.pi * f * h * t + phase * h) / (h ** (1.0 / bright))
    return out


def circ_filter(x, lo=None, hi=None):
    """Smooth band filter applied in the frequency domain (circular = loop safe)."""
    spec = np.fft.rfft(x, axis=0)
    freqs = np.fft.rfftfreq(x.shape[0], 1 / SR)
    mask = np.ones_like(freqs)
    if hi is not None:
        mask *= 1 / (1 + (freqs / hi) ** 4)
    if lo is not None:
        mask *= 1 / (1 + (lo / np.maximum(freqs, 1e-3)) ** 4)
    if x.ndim == 2:
        mask = mask[:, None]
    return np.fft.irfft(spec * mask, n=x.shape[0], axis=0)


def reverb_ir(seconds=2.2, decay=3.0, length=None):
    n = int(SR * seconds)
    t = np.arange(n) / SR
    ir = rng.standard_normal((n, 2)) * np.exp(-decay * t)[:, None]
    ir = circ_filter(ir, hi=5000)
    ir[0] += 1.0  # keep some dry signal
    if length:
        pad = np.zeros((length, 2))
        pad[:n] = ir
        ir = pad
    return ir / np.abs(ir).max()


def circ_reverb(x, wet=0.35, seconds=2.2):
    ir = reverb_ir(seconds, length=x.shape[0])
    y = np.fft.irfft(np.fft.rfft(x, axis=0) * np.fft.rfft(ir, axis=0), n=x.shape[0], axis=0)
    y *= np.abs(x).max() / (np.abs(y).max() + 1e-9)
    return x * (1 - wet) + y * wet


def lin_reverb(x, wet=0.35, seconds=2.2):
    pad = np.zeros((x.shape[0] + int(SR * seconds), 2))
    pad[: x.shape[0]] = x
    return circ_reverb(pad, wet, seconds)


def circ_echo(x, delay=0.375, feedback=0.45, taps=5):
    out = x.copy()
    d = int(SR * delay)
    for i in range(1, taps + 1):
        tap = np.roll(x, d * i, axis=0) * feedback ** i
        if i % 2:  # ping-pong
            tap = tap[:, ::-1]
        out += tap
    return out


def place(buf, sig, start_s, wrap=True):
    s = int(start_s * SR)
    idx = np.arange(s, s + sig.shape[0])
    if wrap:
        idx %= buf.shape[0]
    else:
        keep = idx < buf.shape[0]
        idx, sig = idx[keep], sig[keep]
    np.add.at(buf, idx, sig)


def stereo(m, width=0.0):
    return np.stack([m * (1 - width), m * (1 + width)], axis=1) if width else np.stack([m, m], axis=1)


def normalize(x, peak=0.85):
    return x * (peak / (np.abs(x).max() + 1e-9))


# ---------------------------------------------------------------- instruments

def env_t(seconds):
    return np.arange(int(SR * seconds)) / SR


def bell(f, seconds=2.5):
    t = env_t(seconds)
    partials = [(1.0, 1.0, 1.6), (2.0, 0.45, 2.6), (3.0, 0.18, 4.0), (4.2, 0.12, 6.0)]
    out = np.zeros_like(t)
    for ratio, amp, dec in partials:
        out += amp * np.sin(2 * np.pi * f * ratio * t) * np.exp(-dec * t)
    attack = np.minimum(1, t / 0.004)
    return out * attack


def thump(f0=72, f1=38, seconds=0.45, click=0.25):
    t = env_t(seconds)
    f = f1 + (f0 - f1) * np.exp(-t / 0.05)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.11)
    noise = rng.standard_normal(t.size) * np.exp(-t / 0.012) * click
    return np.tanh(1.6 * (body + noise))


def string_pad(freqs, t, vibrato=5.0, depth=0.004, harmonics=7):
    out = np.zeros_like(t)
    for i, f in enumerate(freqs):
        f = q(f)
        vib = depth * f / q(vibrato) * np.sin(2 * np.pi * q(vibrato) * t + i * 1.3)
        for h in range(1, harmonics + 1):
            out += np.sin(2 * np.pi * f * h * t + vib * h) / h
    return out


def click(seconds=0.05, hp=2500):
    t = env_t(seconds)
    n = rng.standard_normal(t.size) * np.exp(-t / 0.006)
    return circ_filter(stereo(n), lo=hp)[:, 0]


# ---------------------------------------------------------------- loops

def make_drone():
    lfo = 0.55 + 0.45 * np.sin(2 * np.pi * q(1 / 16) * T)
    left = (osc(q(note("D1")), harmonics=6, bright=1.2) * 0.9
            + osc(q(note("A1")) , harmonics=5) * 0.45
            + osc(q(note("D2")) + 0.0625, harmonics=4) * 0.3)
    right = (osc(q(note("D1")) + 0.03125, harmonics=6, bright=1.2) * 0.9
             + osc(q(note("A1")) - 0.0625, harmonics=5) * 0.45
             + osc(q(note("D2")), harmonics=4) * 0.3)
    tone = np.stack([left, right], axis=1) * lfo[:, None]
    tone = circ_filter(tone, hi=600)
    wind = circ_filter(rng.standard_normal((N, 2)), lo=180, hi=900)
    sweep = 0.5 + 0.5 * np.sin(2 * np.pi * q(1 / 8) * T + 1.0)
    wind *= (0.25 + 0.75 * sweep ** 2)[:, None]
    mix = normalize(tone, 0.6) + normalize(wind, 0.18)
    return normalize(circ_reverb(mix, 0.3), 0.8)


def make_heartbeat():
    buf = np.zeros((N, 2))
    lub, dub = thump(), thump(64, 34, click=0.15) * 0.7
    for beat in range(int(LOOP)):  # 60 bpm
        place(buf, stereo(lub), beat)
        place(buf, stereo(dub), beat + 0.28)
    buf = circ_filter(buf, hi=900)
    return normalize(circ_reverb(buf, 0.15, 0.8), 0.85)


def make_tension():
    trem = 0.55 + 0.45 * np.abs(np.sin(np.pi * q(7) * T))
    swell = 0.35 + 0.65 * (0.5 - 0.5 * np.cos(2 * np.pi * q(1 / 8) * T))
    low = string_pad([note("D4"), note("Ab4")], T)
    high = string_pad([note("Eb5"), note("D5")], T, vibrato=6.0, depth=0.006)
    pad = stereo(low * 0.8, 0.0) + np.stack([high * 0.55, high * 0.7], axis=1)
    pad *= (trem * swell)[:, None]
    pad = circ_filter(pad, lo=150, hi=4200)
    shimmer = np.zeros_like(T)
    for i, f in enumerate([note("A6"), note("Bb6"), note("E7")]):
        env = np.clip(np.sin(2 * np.pi * q(1 / 16) * T + i * 2.1), 0, 1) ** 3
        shimmer += np.sin(2 * np.pi * q(f) * T) * env
    pad = normalize(pad, 0.7) + stereo(normalize(shimmer, 0.08), 0.3)
    ticks = np.zeros((N, 2))
    tick = click(0.04, 3000)
    for i in range(int(LOOP * 2)):  # clock tick at 120 bpm
        place(ticks, stereo(tick * (1.0 if i % 2 == 0 else 0.6)), i * 0.5)
    mix = pad + normalize(ticks, 0.12)
    return normalize(circ_reverb(mix, 0.4), 0.8)


def make_musicbox():
    scale = ["D5", "E5", "F5", "G5", "A5", "Bb5", "C6", "D6", "A4", "C#5"]
    phrase = [  # (beat in 0.5 s steps, note)
        (0, "A5"), (2, "F5"), (3, "E5"), (4, "D5"), (8, "C#5"), (10, "E5"), (12, "A4"),
        (16, "D5"), (18, "F5"), (19, "A5"), (20, "Bb5"), (24, "A5"), (28, "G5"), (29, "F5"), (30, "E5"),
        (32, "A5"), (34, "F5"), (35, "E5"), (36, "D5"), (40, "Bb5"), (42, "A5"), (44, "C#5"),
        (48, "D5"), (50, "E5"), (51, "F5"), (52, "E5"), (56, "D5"), (60, "A4"),
    ]
    assert all(n in scale for _, n in phrase)
    buf = np.zeros((N, 2))
    for step, n in phrase:
        pan = 0.25 * np.sin(step)
        b = bell(note(n)) * (0.8 + 0.2 * rng.random())
        place(buf, np.stack([b * (1 - pan), b * (1 + pan)], axis=1), step * 0.5)
    buf = circ_echo(buf, 0.375, 0.4, 4)
    return normalize(circ_reverb(buf, 0.45, 2.8), 0.75)


# ---------------------------------------------------------------- stingers

def make_scare():
    length = 4.5
    t = env_t(length)
    buf = np.zeros((t.size, 2))
    # Reverse swell into the hit.
    swell_t = env_t(1.0)
    swell = rng.standard_normal(swell_t.size) * (swell_t / 1.0) ** 3
    swell = circ_filter(stereo(swell), lo=300, hi=6000)
    place(buf, swell * 0.5, 0.0, wrap=False)
    hit_t = env_t(3.5)
    env = np.exp(-hit_t / 0.9)
    low = string_pad([note("D2"), note("Eb2"), note("Ab2")], hit_t, harmonics=12) * env
    screech = string_pad([note("D6"), note("Eb6"), note("A6")], hit_t, vibrato=11, depth=0.02, harmonics=5)
    screech *= np.exp(-hit_t / 0.6)
    burst = rng.standard_normal(hit_t.size) * np.exp(-hit_t / 0.08)
    hit = np.tanh(1.5 * (normalize(low, 0.8) + normalize(screech, 0.45) + burst * 0.4))
    place(buf, stereo(hit), 1.0, wrap=False)
    return normalize(lin_reverb(buf, 0.35), 0.95)


def make_theft():
    t = env_t(1.8)
    out = np.zeros_like(t)
    for i, n in enumerate(["E5", "Eb5"]):
        seg = (t >= i * 0.35)
        tt = np.clip(t - i * 0.35, 0, None)
        tone = string_pad([note(n), note(n) / 2], tt, vibrato=9, depth=0.01, harmonics=6)
        out += tone * np.exp(-tt / 0.5) * np.minimum(1, tt / 0.01) * seg
    return normalize(lin_reverb(stereo(out), 0.3, 1.5), 0.8)


def make_spotted():
    buf = np.zeros((int(SR * 1.2), 2))
    place(buf, stereo(bell(note("A4"), 1.2)), 0.0, wrap=False)
    place(buf, stereo(bell(note("D5"), 1.0) * 0.8), 0.09, wrap=False)
    return normalize(lin_reverb(buf, 0.3, 1.2), 0.6)


def make_dawn():
    t = env_t(6.0)
    chord = string_pad([note("D4"), note("F#4"), note("A4"), note("D5")], t, vibrato=5, depth=0.003)
    chord *= np.minimum(1, t / 1.2) * np.exp(-np.maximum(0, t - 3.0) / 1.2)
    buf = stereo(normalize(circ_filter(stereo(chord), hi=3500)[:, 0], 0.5))
    for i, n in enumerate(["D5", "F#5", "A5", "D6"]):
        place(buf, stereo(bell(note(n), 2.5) * 0.4), 0.4 + i * 0.25, wrap=False)
    return normalize(lin_reverb(buf, 0.45, 2.5), 0.8)


def make_fail():
    t = env_t(4.5)
    out = np.zeros_like(t)
    for i, n in enumerate(["D3", "C3", "Bb2", "A2"]):
        tt = np.clip(t - i * 0.7, 0, None)
        tone = string_pad([note(n), note(n) * 1.5], tt, harmonics=9)
        out += tone * np.minimum(1, tt / 0.05) * np.exp(-tt / 1.1) * (t >= i * 0.7)
    out = circ_filter(stereo(out), hi=1800)[:, 0]
    return normalize(lin_reverb(stereo(out), 0.4, 2.0), 0.8)


def make_punch():
    buf = np.zeros((int(SR * 0.9), 2))
    place(buf, stereo(click(0.05, 1200)), 0.0, wrap=False)
    place(buf, stereo(thump(180, 90, 0.12, 0.6) * 0.5), 0.0, wrap=False)
    place(buf, stereo(click(0.05, 1800) * 0.8), 0.09, wrap=False)
    place(buf, stereo(bell(note("A6"), 0.7) * 0.25), 0.1, wrap=False)
    return normalize(lin_reverb(buf, 0.15, 0.5), 0.7)


# ---------------------------------------------------------------- output

def write_ogg(path, x, quality=4):
    x = np.clip(x, -1, 1)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        wav_path = tmp.name
    with wave.open(wav_path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype("<i2").tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path,
                    "-c:a", "libvorbis", "-q:a", str(quality), path], check=True)
    os.remove(wav_path)


def loop_seam(x):
    """Jump between the last and first sample, relative to typical step size."""
    step = np.abs(np.diff(x, axis=0)).mean()
    return float(np.abs(x[0] - x[-1]).max() / (step + 1e-9))


def preview(layers, stingers, path):
    """A 48 s mix walking through calm -> fear -> Shadow -> dawn."""
    secs = 48
    n = SR * secs
    t = np.arange(n) / SR

    def tile(x):
        return np.tile(x, (int(np.ceil(n / x.shape[0])), 1))[:n]

    def ramp(a, b):
        return np.clip((t - a) / (b - a), 0, 1)

    fear = ramp(8, 30)
    danger = ramp(20, 30) * (1 - ramp(32, 34))
    mix = tile(layers["drone"]) * 0.8
    mix += tile(layers["musicbox"]) * (0.6 * (1 - fear) * (1 - ramp(40, 41)))[:, None]
    mix += tile(layers["heartbeat"]) * (fear * 0.8 * (1 - ramp(41, 44)))[:, None]
    mix += tile(layers["tension"]) * (danger * 0.7)[:, None]
    for name, at in [("punch", 4.0), ("spotted", 14.0), ("theft", 22.0), ("scare", 29.0), ("dawn", 41.0)]:
        place(mix, stingers[name] * 0.9, at, wrap=False)
    mix *= (1 - ramp(46, 48))[:, None]
    write_ogg(path, normalize(mix, 0.9), 5)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", help="also write a demo mix to this .ogg path")
    args = ap.parse_args()
    os.makedirs(OUT_DIR, exist_ok=True)

    layers = {
        "drone": make_drone(),
        "heartbeat": make_heartbeat(),
        "tension": make_tension(),
        "musicbox": make_musicbox(),
    }
    stingers = {
        "scare": make_scare(),
        "theft": make_theft(),
        "spotted": make_spotted(),
        "dawn": make_dawn(),
        "fail": make_fail(),
        "punch": make_punch(),
    }
    for name, x in {**layers, **stingers}.items():
        peak = float(np.abs(x).max())
        seam = f"  loop seam {loop_seam(x):.2f}x avg step" if name in layers else ""
        print(f"{name:10s} {x.shape[0] / SR:5.1f}s  peak {peak:.2f}{seam}")
        write_ogg(os.path.join(OUT_DIR, f"{name}.ogg"), x)
    if args.preview:
        preview(layers, stingers, args.preview)
        print("preview ->", args.preview)


if __name__ == "__main__":
    main()
