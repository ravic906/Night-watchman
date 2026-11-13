#!/usr/bin/env python3
"""Composes Night Watchman's adaptive score and sound effects in code and writes it to audio/*.ogg.

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


# ---------------------------------------------------------------- sound effects

def lin_filter(x, lo=None, hi=None):
    """Band filter for one-shots (zero-padded so nothing wraps around)."""
    pad = int(SR * 0.05)
    y = circ_filter(np.concatenate([x, np.zeros(pad)]), lo=lo, hi=hi)
    return y[: x.size]


def make_step(seed):
    """Watchman's boot on a tiled floor: heel thud + hard tile tick."""
    r = np.random.default_rng(seed)
    t = env_t(0.3)
    heel = np.zeros_like(t)
    th = thump(120 + r.uniform(-15, 15), 60 + r.uniform(-8, 8), 0.2, click=0.3)
    heel[: th.size] += th * 0.6
    tick = r.standard_normal(t.size) * np.exp(-t / 0.004)
    tick = lin_filter(tick, lo=1800, hi=7000) * r.uniform(0.5, 0.8)
    scuff = lin_filter(r.standard_normal(t.size), lo=500, hi=3000)
    scuff *= np.exp(-np.maximum(0, t - 0.03) / 0.03) * (t > 0.03) * r.uniform(0.05, 0.12)
    out = heel + tick + scuff
    return normalize(lin_reverb(stereo(out), 0.18, 0.5), 0.8)


def make_sneak(seed):
    """A thief's soft-soled creep: muffled pad and a fabric scuff."""
    r = np.random.default_rng(seed)
    t = env_t(0.35)
    pad = thump(80 + r.uniform(-10, 10), 45, 0.15, click=0.05) * 0.4
    out = np.zeros_like(t)
    out[: pad.size] += pad
    scuff = lin_filter(r.standard_normal(t.size), lo=350, hi=2200)
    env = np.minimum(1, t / 0.02) * np.exp(-t / 0.07)
    out += scuff * env * 0.5
    return normalize(lin_reverb(stereo(out), 0.25, 0.6), 0.8)


def creak(seconds, rate_curve, resonances=(620, 1250, 2300), jitter=0.25, seed=3):
    """Hinge creak: a stick-slip pulse train ringing through a few resonances."""
    r = np.random.default_rng(seed)
    t = env_t(seconds)
    rate = rate_curve(t / seconds)
    phase = np.cumsum(rate) / SR
    pulses = np.zeros_like(t)
    hits = np.nonzero(np.diff(np.floor(phase)) > 0)[0]
    pulses[hits] = 1.0 + r.uniform(-jitter, jitter, hits.size)
    ir_t = env_t(0.03)
    ir = sum(np.sin(2 * np.pi * f * ir_t) * np.exp(-ir_t / (0.012 - i * 0.002)) / (i + 1)
             for i, f in enumerate(resonances))
    out = np.convolve(pulses, ir)[: t.size]
    env = np.minimum(1, t / 0.08) * np.minimum(1, (seconds - t) / 0.15)
    return out * env


def make_door_creak():
    out = creak(1.4, lambda u: 28 + 70 * np.sin(np.pi * u) ** 1.5 + 12 * np.sin(17 * u))
    latch = np.zeros(int(SR * 1.6))
    latch[: out.size] += out
    cl = click(0.04, 1500) * 0.5
    place_at = int(SR * 1.42)
    latch[place_at: place_at + cl.size] += cl
    return normalize(lin_reverb(stereo(latch), 0.35, 1.5), 0.85)


def make_door_swing():
    out = creak(0.55, lambda u: 55 + 60 * u, resonances=(800, 1600, 2700), seed=7)
    return normalize(lin_reverb(stereo(out), 0.25, 0.8), 0.7)


def make_door_slam():
    t = env_t(1.0)
    out = np.zeros_like(t)
    th = thump(95, 42, 0.7, click=0.7)
    out[: th.size] += th
    r = np.random.default_rng(11)
    for i in range(6):  # frame and latch rattle
        at = int(SR * (0.03 + i * 0.035 + r.uniform(0, 0.01)))
        cl = click(0.03, 1200) * 0.5 * 0.7 ** i
        out[at: at + cl.size] += cl
    out = lin_filter(out, hi=5000)
    return normalize(lin_reverb(stereo(out), 0.4, 1.4), 0.9)


def beep(f, seconds, square=0.3):
    t = env_t(seconds)
    tone = np.sin(2 * np.pi * f * t) + square * np.sin(2 * np.pi * 3 * f * t) / 3
    return tone * np.minimum(1, t / 0.005) * np.minimum(1, (seconds - t) / 0.01)


def make_alarm_arm():
    """Keypad confirm: three rising beeps."""
    buf = np.zeros((int(SR * 0.9), 2))
    for i, f in enumerate([880, 1175, 1568]):
        place(buf, stereo(beep(f, 0.11) * 0.6), i * 0.14, wrap=False)
    return normalize(lin_reverb(buf, 0.15, 0.4), 0.7)


def make_alarm_chime():
    """Break-in chime: two-tone ding-dong, twice."""
    buf = np.zeros((int(SR * 2.2), 2))
    for rep in range(2):
        for i, n in enumerate(["E6", "C6"]):
            b = bell(note(n), 1.0)
            b[: int(SR * 0.25)] += beep(note(n), 0.25, 0.6) * np.exp(-env_t(0.25) / 0.1) * 0.3
            place(buf, stereo(b), rep * 0.7 + i * 0.3, wrap=False)
    return normalize(lin_reverb(buf, 0.3, 1.2), 0.8)


def make_alarm_cut():
    """Panel dying: falling squeal into an electrical fizz."""
    t = env_t(1.3)
    f = 1500 * np.exp(-t * 2.2) + 120
    squeal = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.6)
    r = np.random.default_rng(21)
    fizz = lin_filter(r.standard_normal(t.size), lo=2500) * (r.random(t.size) < 0.08)
    fizz *= np.exp(-np.maximum(0, t - 0.3) / 0.25) * (t > 0.3)
    return normalize(lin_reverb(stereo(squeal * 0.7 + fizz * 0.8), 0.25, 0.8), 0.8)


def make_breaker():
    """Heavy breaker clunk with a dying mains hum."""
    t = env_t(1.6)
    out = np.zeros_like(t)
    th = thump(110, 50, 0.4, click=0.8)
    out[: th.size] += th
    hum = sum(np.sin(2 * np.pi * 50 * h * t) / h for h in (1, 2, 3, 5))
    out += hum * 0.25 * np.exp(-t / 0.35) * np.minimum(1, t / 0.02)
    cl = click(0.04, 1500) * 0.6
    out[: cl.size] += cl
    return normalize(lin_reverb(stereo(lin_filter(out, hi=6000)), 0.35, 1.2), 0.85)


def make_lockpick():
    """A few metallic ticks of a pick working a lock."""
    r = np.random.default_rng(31)
    buf = np.zeros((int(SR * 0.8), 2))
    tick_t = env_t(0.03)
    for i in range(5):
        f = r.uniform(3800, 5200)
        tick = np.sin(2 * np.pi * f * tick_t) * np.exp(-tick_t / 0.006)
        tick += r.standard_normal(tick_t.size) * np.exp(-tick_t / 0.002) * 0.3
        place(buf, stereo(tick * r.uniform(0.5, 1.0)), 0.05 + i * r.uniform(0.07, 0.13), wrap=False)
    return normalize(lin_reverb(buf, 0.2, 0.4), 0.7)


def make_lock():
    """Deadbolt sliding home."""
    t = env_t(0.4)
    r = np.random.default_rng(41)
    slide = lin_filter(r.standard_normal(t.size), lo=800, hi=4000) * (t < 0.12) * np.minimum(1, t / 0.02) * 0.3
    out = slide
    th = thump(240, 120, 0.1, click=0.6) * 0.6
    at = int(SR * 0.12)
    out[at: at + th.size] += th[: out.size - at]
    return normalize(lin_reverb(stereo(out), 0.2, 0.5), 0.75)


def make_glass_break():
    """A window smashing: impact, crash and tinkling shards."""
    r = np.random.default_rng(51)
    t = env_t(2.2)
    out = np.zeros_like(t)
    th = thump(140, 70, 0.2, click=0.9) * 0.6
    out[: th.size] += th
    crash = lin_filter(r.standard_normal(t.size), lo=1500) * np.exp(-t / 0.12)
    out += crash * 0.9
    shard_t = env_t(0.12)
    for i in range(28):  # shards landing
        at = int(SR * (0.05 + r.exponential(0.35)))
        if at + shard_t.size >= t.size:
            continue
        f = r.uniform(2500, 7500)
        ping = np.sin(2 * np.pi * f * shard_t) * np.exp(-shard_t / r.uniform(0.01, 0.04))
        out[at: at + shard_t.size] += ping * r.uniform(0.15, 0.5)
    return normalize(lin_reverb(stereo(out), 0.3, 1.2), 0.9)


def make_radio():
    """Walkie-talkie: squelch burst, then a double beep."""
    r = np.random.default_rng(61)
    t = env_t(0.9)
    static = lin_filter(r.standard_normal(t.size), lo=600, hi=3500) * (t < 0.25) * 0.45
    out = static
    for i, f in enumerate([1400, 1800]):
        b = beep(f, 0.08, 0.5) * 0.5
        at = int(SR * (0.32 + i * 0.12))
        out[at: at + b.size] += b
    return normalize(lin_reverb(stereo(out), 0.1, 0.3), 0.7)


def make_board():
    """Three hammer knocks on wood."""
    buf = np.zeros((int(SR * 1.3), 2))
    for i in range(3):
        knock = thump(220 - i * 10, 110, 0.15, click=0.8)
        knock = lin_filter(knock, hi=4000)
        place(buf, stereo(knock * (0.8 + 0.1 * i)), 0.05 + i * 0.28, wrap=False)
    return normalize(lin_reverb(buf, 0.25, 0.6), 0.8)


def make_pry():
    """Boards being levered off: a low, strained wooden creak."""
    out = creak(0.8, lambda u: 18 + 30 * u, resonances=(260, 520, 900), seed=71)
    return normalize(lin_reverb(stereo(out), 0.3, 0.8), 0.75)


def make_intercom():
    """Apartment intercom: harsh buzz, then a two-note chime."""
    t = env_t(0.6)
    buzz = np.sign(np.sin(2 * np.pi * 220 * t)) * 0.3 + np.sin(2 * np.pi * 440 * t) * 0.2
    buzz = lin_filter(buzz * np.minimum(1, t / 0.01) * np.minimum(1, (0.6 - t) / 0.02), hi=3000)
    buf = np.zeros((int(SR * 1.8), 2))
    place(buf, stereo(buzz), 0.0, wrap=False)
    place(buf, stereo(bell(note("G5"), 0.9) * 0.6), 0.7, wrap=False)
    place(buf, stereo(bell(note("D5"), 0.9) * 0.6), 0.95, wrap=False)
    return normalize(lin_reverb(buf, 0.15, 0.5), 0.75)


def make_shutter():
    """Roll-down shutter: ratcheting metal rattle ending in a clang."""
    r = np.random.default_rng(81)
    t = env_t(1.4)
    rattle = np.zeros_like(t)
    tick_t = env_t(0.02)
    for i in range(int(1.0 / 0.035)):
        at = int(SR * i * 0.035)
        tick = lin_filter(r.standard_normal(tick_t.size), lo=900, hi=5000) * np.exp(-tick_t / 0.006)
        rattle[at: at + tick.size] += tick * r.uniform(0.3, 0.6)
    clang_t = env_t(0.4)
    clang = sum(np.sin(2 * np.pi * f * clang_t) for f in (310, 520, 790)) * np.exp(-clang_t / 0.12)
    rattle[int(SR * 1.0): int(SR * 1.0) + clang.size] += clang * 0.4
    return normalize(lin_reverb(stereo(rattle), 0.3, 1.0), 0.8)


def make_shutter_force():
    """Shutter being forced: a straining metal screech."""
    t = env_t(1.0)
    f = 900 + 250 * np.sin(2 * np.pi * 3.0 * t) + 120 * np.sin(2 * np.pi * 11 * t)
    screech = np.sin(2 * np.pi * np.cumsum(f) / SR)
    screech += 0.4 * np.sin(2 * np.pi * np.cumsum(f * 2.01) / SR)
    env = np.minimum(1, t / 0.05) * np.minimum(1, (1.0 - t) / 0.2)
    return normalize(lin_reverb(stereo(lin_filter(screech * env, lo=300, hi=6000)), 0.3, 0.9), 0.7)


def make_machine_loop():
    """Factory machine running: a loopable thumping, whining drone (LOOP-safe 4 s)."""
    secs = 4.0
    n = int(SR * secs)
    t = np.arange(n) / SR
    def qq(f):  # whole cycles in 4 s
        return round(f * secs) / secs
    hum = sum(np.sin(2 * np.pi * qq(f) * t) / i for i, f in enumerate((55, 110, 165, 330), start=1))
    whine = np.sin(2 * np.pi * qq(1250) * t) * 0.08
    pump = np.zeros(n)
    th = thump(90, 45, 0.25, click=0.4)
    for k in range(8):  # 2 strokes per second
        at = int(SR * k * 0.5)
        idx = (np.arange(th.size) + at) % n
        np.add.at(pump, idx, th * 0.7)
    r = np.random.default_rng(91)
    grit = circ_filter(r.standard_normal(n), lo=1500, hi=6000) * 0.05
    out = (hum * 0.35 + whine + pump + grit) * (0.85 + 0.15 * np.sin(2 * np.pi * qq(2) * t))
    return normalize(stereo(out), 0.8)


def make_overheat():
    """Overheat klaxon: two-tone alarm, three times."""
    buf = np.zeros((int(SR * 2.6), 2))
    for i in range(6):
        f = 520 if i % 2 == 0 else 390
        b = beep(f, 0.36, 0.8) * 0.6
        place(buf, stereo(b), i * 0.4, wrap=False)
    return normalize(lin_reverb(buf, 0.3, 1.0), 0.85)


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
        "door_creak": make_door_creak(),
        "door_swing": make_door_swing(),
        "door_slam": make_door_slam(),
        "alarm_arm": make_alarm_arm(),
        "alarm_chime": make_alarm_chime(),
        "alarm_cut": make_alarm_cut(),
        "breaker": make_breaker(),
        "lockpick": make_lockpick(),
        "lock": make_lock(),
        "glass_break": make_glass_break(),
        "radio": make_radio(),
        "board": make_board(),
        "pry": make_pry(),
        "intercom": make_intercom(),
        "shutter": make_shutter(),
        "shutter_force": make_shutter_force(),
        "machine_loop": make_machine_loop(),
        "overheat": make_overheat(),
    }
    for i in range(4):
        stingers[f"step_{i + 1}"] = make_step(100 + i)
    for i in range(3):
        stingers[f"sneak_{i + 1}"] = make_sneak(200 + i)
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
