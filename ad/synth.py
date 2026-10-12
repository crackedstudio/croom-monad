#!/usr/bin/env python3
"""A tiny wavetable synthesiser. Standard library only.

Additive synthesis straight to samples was the obvious approach and far too slow: a band-limited
saw needs a dozen sine calls per sample, and at 48kHz across thirty seconds of polyphony that runs
into hundreds of millions of them. So each waveform is built once into a 2048-point table and
played back by a phase accumulator with linear interpolation, which turns a dozen transcendental
calls per sample into two lookups and a multiply.
"""
import math

SR = 48_000
TABLE = 2048


def _table(harmonics) -> list[float]:
    """One cycle, built from a harmonic series. Band-limited by construction."""
    out = []
    for i in range(TABLE):
        t = i / TABLE
        v = sum(a * math.sin(2 * math.pi * h * t) for h, a in harmonics)
        out.append(v)
    peak = max(abs(v) for v in out) or 1.0
    return [v / peak for v in out]


# A saw is 1/n on every harmonic; a square is 1/n on the odd ones. Both stop well short of
# Nyquist for the register these parts sit in.
SAW = _table([(h, 1.0 / h) for h in range(1, 24)])
SQUARE = _table([(h, 1.0 / h) for h in range(1, 24, 2)])
TRI = _table([(h, (1.0 / (h * h)) * (1 if (h // 2) % 2 == 0 else -1)) for h in range(1, 16, 2)])
SINE = _table([(1, 1.0)])


def midi(n: float) -> float:
    """MIDI note number to Hz. A4 = 69 = 440."""
    return 440.0 * (2.0 ** ((n - 69) / 12.0))


def adsr(n: int, a: float, d: float, s: float, r: float) -> list[float]:
    """A straightforward envelope, in seconds, clamped to the note length."""
    att = max(1, int(a * SR))
    dec = max(1, int(d * SR))
    rel = max(1, int(r * SR))
    out = []
    for i in range(n):
        if i < att:
            v = i / att
        elif i < att + dec:
            v = 1.0 + (s - 1.0) * ((i - att) / dec)
        else:
            v = s
        # Release is applied as a tail over the last `rel` samples.
        left = n - i
        if left < rel:
            v *= left / rel
        out.append(v)
    return out


def play(
    note: float,
    dur: float,
    amp: float = 0.2,
    table: list[float] = SAW,
    a: float = 0.005,
    d: float = 0.08,
    s: float = 0.7,
    r: float = 0.05,
    detune: float = 0.0,
    glide_to: float | None = None,
) -> list[float]:
    """One note. `detune` adds a second oscillator a few cents away, which gives width."""
    n = int(dur * SR)
    env = adsr(n, a, d, s, r)
    f0 = midi(note)
    f1 = midi(glide_to) if glide_to is not None else f0

    out = [0.0] * n
    phase = 0.0
    phase2 = 0.0
    voices = 2 if detune else 1
    for i in range(n):
        f = f0 + (f1 - f0) * (i / n) if glide_to is not None else f0
        step = f * TABLE / SR
        phase = (phase + step) % TABLE
        idx = int(phase)
        frac = phase - idx
        v = TABLE_LERP(table, idx, frac)
        if voices == 2:
            step2 = f * (1.0 + detune) * TABLE / SR
            phase2 = (phase2 + step2) % TABLE
            j = int(phase2)
            v = (v + TABLE_LERP(table, j, phase2 - j)) * 0.5
        out[i] = v * env[i] * amp
    return out


def TABLE_LERP(tbl: list[float], i: int, frac: float) -> float:
    a = tbl[i]
    b = tbl[(i + 1) % TABLE]
    return a + (b - a) * frac


def noise(dur: float, amp: float, decay: float, rng, colour: float = 0.6) -> list[float]:
    """Shaped noise, for hats and transients. `colour` low-passes it toward a knock."""
    n = int(dur * SR)
    prev = 0.0
    out = []
    for i in range(n):
        prev = prev * colour + rng.uniform(-1, 1) * (1 - colour)
        out.append(prev * math.exp(-(i / SR) / decay) * amp)
    return out


def sweep(f0: float, f1: float, dur: float, amp: float, decay: float, curve: float = 0.35) -> list[float]:
    """A pitch falling from f0 to f1 — the body of every kick and the refusal hit."""
    n = int(dur * SR)
    phase = 0.0
    out = []
    for i in range(n):
        x = i / n
        f = f0 + (f1 - f0) * (x ** curve)
        phase += 2 * math.pi * f / SR
        out.append(math.sin(phase) * math.exp(-(i / SR) / decay) * amp)
    return out
