#!/usr/bin/env python3
"""Composes the advert's soundtrack. Standard library only — no samples, no licences.

160 BPM in A minor, which is chosen rather than guessed: a bar is exactly 1.5 seconds, so drand's
three-second period is two bars. The beacon is the downbeat. Every cut in the video lands on a bar
line and the refusal lands on a beat, so the track and the edit agree without either being bent to
fit the other.

Arrangement across 20 bars:

    bars  0-3   intro      arpeggio and hats
    bars  4-6   build      bass and kick arrive
    bars  7-9   beacon     full groove, the pulse foregrounded while it is being explained
    bars 10-11  tension    stripped to the arpeggio over a riser
    bar  12     THE HIT    everything stops for the refusal, then the beat returns heavier
    bars 15-17  payout     lead an octave up, bells, the progression resolving major
    bars 18-19  outro      the last chord left ringing
"""
import math
import random
import struct
import wave

from synth import SAW, SINE, SQUARE, TRI, SR, midi, noise, play, sweep

BPM = 160
BEAT = 60.0 / BPM          # 0.375s
BAR = BEAT * 4             # 1.5s
BARS = 20
DUR = BARS * BAR           # 30.0s
N = int(SR * DUR)

rng = random.Random(0xC0FFEE)
buf = [0.0] * N


def mix(t: float, samples, gain: float = 1.0) -> None:
    i = int(t * SR)
    if i < 0:
        samples = samples[-i:]
        i = 0
    for k, v in enumerate(samples):
        j = i + k
        if j >= N:
            break
        buf[j] += v * gain


# ── harmony ──────────────────────────────────────────────────────────────────────────────────
# i - VI - III - VII in A minor. Four bars, looping for the whole piece.
ROOTS = [45, 41, 48, 43]                        # A2  F2  C3  G2
ARPS = [[69, 72, 76, 72],                       # A4 C5 E5 C5
        [65, 69, 72, 69],                       # F4 A4 C5 A4
        [67, 72, 76, 72],                       # G4 C5 E5 C5
        [67, 71, 74, 71]]                       # G4 B4 D5 B4
PADS = [[57, 60, 64], [53, 57, 60], [55, 60, 64], [55, 59, 62]]

# The hook: one four-bar phrase, two notes to a beat where it moves.
#   bar: [(beat, midi, beats_long), ...]
HOOK = [
    [(0, 81, 1), (1, 84, 1), (2, 83, 1), (3, 81, 1)],   # A5 C6 B5 A5
    [(0, 79, 1), (1, 81, 1), (2, 77, 2)],               # G5 A5 F5
    [(0, 76, 1), (1, 79, 1), (2, 84, 1), (3, 79, 1)],   # E5 G5 C6 G5
    [(0, 74, 1), (1, 79, 1), (2, 83, 2)],               # D5 G5 B5
]


def bar_t(bar: int, beat: float = 0.0) -> float:
    return bar * BAR + beat * BEAT


# ── drums ────────────────────────────────────────────────────────────────────────────────────
def kick(t: float, amp: float = 0.62) -> None:
    mix(t, sweep(140, 48, 0.42, amp, 0.17))
    mix(t, noise(0.012, amp * 0.3, 0.004, rng, colour=0.35))


def clap(t: float, amp: float = 0.22) -> None:
    # Three near-copies a few milliseconds apart is what makes a clap sound like hands.
    for off in (0.0, 0.009, 0.019):
        mix(t + off, noise(0.16, amp * (1.0 - off * 18), 0.045, rng, colour=0.12))


def hat(t: float, amp: float = 0.07, open_: bool = False) -> None:
    mix(t, noise(0.12 if open_ else 0.045, amp, 0.05 if open_ else 0.013, rng, colour=0.02))


def beacon(t: float, amp: float = 0.5) -> None:
    """The three-second pulse. Deliberately sub-heavy so it is felt under everything else."""
    mix(t, sweep(92, 42, 1.0, amp, 0.30))


# ── the arrangement ──────────────────────────────────────────────────────────────────────────
for bar in range(BARS):
    chord = bar % 4
    root = ROOTS[chord]
    arp = ARPS[chord]

    intro = bar < 4
    build = 4 <= bar < 7
    full = 7 <= bar < 10
    tension = 10 <= bar < 12
    heavy = 12 <= bar < 15
    payout = 15 <= bar < 18
    outro = bar >= 18

    # Arpeggio — eighth notes, present almost throughout, the spine of the piece.
    if not outro:
        amp = 0.075 if intro else 0.055 if tension else 0.105 if payout else 0.085
        for e in range(8):
            n = arp[e % 4] + (12 if payout else 0)
            mix(bar_t(bar, e * 0.5),
                play(n, BEAT * 0.46, amp=amp, table=SQUARE if intro else SAW,
                     a=0.004, d=0.06, s=0.28, r=0.04, detune=0.004))

    # Pad — quiet sustained chord, glues the whole thing together.
    if not intro:
        for n in PADS[chord]:
            mix(bar_t(bar), play(n, BAR * 0.98, amp=0.030, table=TRI,
                                 a=0.12, d=0.3, s=0.75, r=0.25, detune=0.009))

    # Bass.
    if build or full or heavy or payout:
        amp = 0.26 if (heavy or full) else 0.20
        pattern = [0, 0, 12, 0, 0, 12, 0, 7]
        for e, off in enumerate(pattern):
            mix(bar_t(bar, e * 0.5),
                play(root + off, BEAT * 0.44, amp=amp, table=SAW,
                     a=0.004, d=0.09, s=0.45, r=0.04))

    # Kick and clap.
    if build or full or heavy or payout:
        kick(bar_t(bar, 0))
        kick(bar_t(bar, 2), amp=0.55)
        if full or heavy or payout:
            clap(bar_t(bar, 1))
            clap(bar_t(bar, 3))
        if heavy:
            kick(bar_t(bar, 3.5), amp=0.42)

    # Hats.
    if not intro or bar >= 2:
        if not tension:
            for e in range(8):
                hat(bar_t(bar, e * 0.5), amp=0.055 if e % 2 else 0.078, open_=(e == 7))

    # The hook, once the groove is established and again, higher, over the payout.
    if full or heavy or payout:
        for beat_i, note, length in HOOK[chord]:
            mix(bar_t(bar, beat_i),
                play(note + (12 if payout else 0), BEAT * length * 0.92,
                     amp=0.115 if payout else 0.095, table=SAW,
                     a=0.008, d=0.10, s=0.55, r=0.08, detune=0.007))

    # Outro: the last chord, left to ring.
    if bar == 18:
        for n in (45, 57, 60, 64, 69):
            mix(bar_t(bar), play(n, BAR * 2.0, amp=0.075, table=SAW,
                                 a=0.01, d=0.5, s=0.5, r=1.4, detune=0.008))
        kick(bar_t(bar), amp=0.7)
        mix(bar_t(bar), noise(1.4, 0.10, 0.5, rng, colour=0.05))

# ── the beacon, every three seconds ──────────────────────────────────────────────────────────
for i in range(10):
    t = i * 3.0
    if t < DUR:
        beacon(t, amp=0.62 if 10.5 <= t < 15.0 else 0.46)

# ── the refusal at 18.0s, bar 12, on the beat ────────────────────────────────────────────────
REFUSED = 18.0
# A riser through the two tension bars, then silence for an instant, then the hit.
mix(REFUSED - 3.0, [v * (k / (3.0 * SR)) ** 2 for k, v in
                    enumerate(noise(3.0, 0.22, 99.0, rng, colour=0.55))])
for k in range(int((REFUSED - 0.06) * SR), int(REFUSED * SR)):
    buf[k] *= 0.25                                   # the gap before the impact
mix(REFUSED, sweep(260, 34, 1.9, 0.92, 0.45, curve=0.28))
mix(REFUSED, noise(0.9, 0.30, 0.24, rng, colour=0.06))

# ── the payout: bells over the brighter section ──────────────────────────────────────────────
for t, n in ((22.5 + BEAT * 2, 88), (22.5 + BAR + BEAT * 2, 91), (22.5 + BAR * 2, 93)):
    mix(t, play(n, 1.6, amp=0.085, table=SINE, a=0.004, d=0.9, s=0.0, r=0.4))

# ── master ───────────────────────────────────────────────────────────────────────────────────
print(f"peak before limiting: {max(abs(v) for v in buf):.3f}")
for k in range(N):
    buf[k] = math.tanh(buf[k] * 1.05) * 0.88
for k in range(int(29.3 * SR), N):
    buf[k] *= max(0.0, (N - k) / (0.7 * SR))

with wave.open("public/soundtrack.wav", "w") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767)) for v in buf))
print(f"peak after limiting:  {max(abs(v) for v in buf):.3f}")
print(f"{BARS} bars at {BPM} BPM = {DUR:.1f}s -> public/soundtrack.wav")
