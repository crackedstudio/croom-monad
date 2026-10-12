#!/usr/bin/env python3
"""Synthesises the ad's soundtrack. No samples, no licences, no dependencies.

The rhythm is not decoration. drand publishes a signed value every three seconds, so the track
pulses every three seconds, and the beat the viewer feels is the thing the product is built on.
At 30fps that is one pulse every 90 frames, landing on the same beats the Beacon scene animates.

Everything is a sine, a sweep, or shaped noise, written straight to PCM. Headroom is kept and a
soft limiter catches the one moment that would otherwise clip (the refusal, by design the loudest
thing here).
"""
import math
import random
import struct
import wave

SR = 48_000
DUR = 30.0
N = int(SR * DUR)

random.seed(0xC0FFEE)  # Deterministic: the same file every time it is generated.
buf = [0.0] * N


def at(t: float) -> int:
    return max(0, min(N - 1, int(t * SR)))


def add(t: float, samples) -> None:
    """Mixes a generator of samples in at time t, clipped to the buffer."""
    i = at(t)
    for k, v in enumerate(samples):
        j = i + k
        if j >= N:
            break
        buf[j] += v


def thump(freq_from: float, freq_to: float, length: float, amp: float, tau: float, click: float = 0.0):
    """A kick: a pitch sweeping down, an exponential decay, and an optional transient."""
    n = int(length * SR)
    phase = 0.0
    out = []
    for k in range(n):
        x = k / n
        f = freq_from + (freq_to - freq_from) * (x ** 0.35)
        phase += 2 * math.pi * f / SR
        env = math.exp(-(k / SR) / tau)
        v = math.sin(phase) * env * amp
        if click and k < int(0.010 * SR):
            v += random.uniform(-1, 1) * click * math.exp(-(k / SR) / 0.004)
        out.append(v)
    return out


def chime(freq: float, length: float, amp: float, tau: float = 0.5):
    """A soft bell: a fundamental plus a quiet octave and fifth."""
    n = int(length * SR)
    out = []
    for k in range(n):
        t = k / SR
        env = math.exp(-t / tau) * min(1.0, k / (0.004 * SR))
        out.append(
            (
                math.sin(2 * math.pi * freq * t)
                + 0.32 * math.sin(2 * math.pi * freq * 2 * t)
                + 0.16 * math.sin(2 * math.pi * freq * 3 * t)
            )
            * env
            * amp
        )
    return out


def tick(amp: float = 0.05, length: float = 0.035):
    """Punctuation for a scene change. Shaped noise, gone before it is noticed."""
    n = int(length * SR)
    prev = 0.0
    out = []
    for k in range(n):
        white = random.uniform(-1, 1)
        prev = prev * 0.72 + white * 0.28  # Crude low-pass, so it reads as a knock not a hiss.
        out.append(prev * math.exp(-(k / SR) / 0.009) * amp)
    return out


def swell(length: float, amp: float):
    """Rising shaped noise, for the lift into the end card."""
    n = int(length * SR)
    prev = 0.0
    out = []
    for k in range(n):
        x = k / n
        prev = prev * 0.9 + random.uniform(-1, 1) * 0.1
        out.append(prev * (x ** 2.2) * amp)
    return out


# ── the bed ──────────────────────────────────────────────────────────────────────────────────
# Three quiet sines a fifth and an octave apart. Low enough to feel rather than hear, which keeps
# the voice of the piece on the pulses.
for k in range(N):
    t = k / SR
    breathe = 0.55 + 0.45 * math.sin(2 * math.pi * t / 11.0)
    fade_in = min(1.0, t / 1.6)
    fade_out = 1.0 if t < 28.8 else max(0.0, (30.0 - t) / 1.2)
    buf[k] += (
        0.030 * math.sin(2 * math.pi * 55.0 * t)
        + 0.018 * math.sin(2 * math.pi * 82.5 * t)
        + 0.009 * math.sin(2 * math.pi * 110.0 * t)
    ) * breathe * fade_in * fade_out

# ── the beacon, every three seconds ──────────────────────────────────────────────────────────
for i in range(10):
    t = i * 3.0
    if t >= DUR:
        break
    # The pulses under the Beacon scene are the loudest, because that is when they are explained.
    loud = 1.25 if 10.0 <= t < 15.0 else 1.0
    add(t, thump(92, 55, 0.9, 0.42 * loud, 0.26, click=0.05))

# ── scene punctuation ────────────────────────────────────────────────────────────────────────
for t in (5.5, 10.0, 22.0):
    add(t, tick())

# ── the refusal: the loudest moment, and the point of the ad ─────────────────────────────────
REFUSED = 15.0 + 3.4
add(REFUSED - 0.5, swell(0.5, 0.16))
add(REFUSED, thump(240, 38, 1.5, 0.78, 0.42, click=0.22))

# ── the payout ───────────────────────────────────────────────────────────────────────────────
add(22.0 + 24 / 30, chime(392.0, 1.4, 0.085, tau=0.45))   # staked
add(22.0 + 38 / 30, chime(587.33, 2.0, 0.125, tau=0.75))  # received, a fifth above

# ── the end card ─────────────────────────────────────────────────────────────────────────────
add(26.5 - 0.7, swell(0.7, 0.2))
add(26.5, thump(110, 55, 2.0, 0.5, 0.75, click=0.07))
add(26.6, chime(220.0, 3.0, 0.07, tau=1.6))

# ── master: soft limit, then a clean tail ────────────────────────────────────────────────────
peak = max(abs(v) for v in buf)
print(f"peak before limiting: {peak:.3f}")
for k in range(N):
    v = buf[k] * 0.92
    # tanh rather than a hard clip: the refusal is meant to hit, not to crackle.
    buf[k] = math.tanh(v * 1.15) * 0.87

for k in range(int(29.4 * SR), N):  # Guarantee silence at the cut.
    buf[k] *= max(0.0, (N - k) / (0.6 * SR))

with wave.open("public/soundtrack.wav", "w") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767)) for v in buf))

print(f"peak after limiting:  {max(abs(v) for v in buf):.3f}")
print("public/soundtrack.wav")
