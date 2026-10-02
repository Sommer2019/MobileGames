"""Synthesises the game sounds (python3 tool/make_sounds.py).

Plain Python, no samples from anywhere: writes small 16-bit mono WAV files
to assets/sounds/.
"""
import math
import os
import random
import struct
import wave

RATE = 22050
OUT = 'assets/sounds'
random.seed(7)


def save(name, samples, gain=0.9):
    peak = max(1e-9, max(abs(s) for s in samples))
    data = b''.join(
        struct.pack('<h', int(max(-1, min(1, s / peak * gain)) * 32767))
        for s in samples
    )
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)


def n(seconds):
    return int(RATE * seconds)


def env(i, total, attack=0.002, decay=None):
    """Fast attack, exponential decay."""
    t = i / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    d = math.exp(-t / decay) if decay else 1 - i / total
    return a * d


def tone(freq, seconds, decay, harmonics=((1, 1.0),), noise=0.0, attack=0.002):
    total = n(seconds)
    out = []
    for i in range(total):
        t = i / RATE
        s = sum(a * math.sin(2 * math.pi * freq * h * t) for h, a in harmonics)
        s += noise * (random.random() * 2 - 1)
        out.append(s * env(i, total, attack, decay))
    return out


def lowpass(samples, k):
    out, y = [], 0.0
    for s in samples:
        y += k * (s - y)
        out.append(y)
    return out


def highpass(samples, k):
    return [s - l for s, l in zip(samples, lowpass(samples, k))]


def mix(*parts):
    length = max(len(p) for p, _ in parts)
    out = [0.0] * length
    for p, offset in parts:
        o = n(offset)
        for i, s in enumerate(p):
            if o + i < length:
                out[o + i] += s
    return out


def pad(samples, seconds):
    return samples + [0.0] * n(seconds)


os.makedirs(OUT, exist_ok=True)

# Billiard balls: hard, bright click with a short ring.
save('clack', tone(2400, 0.08, 0.012, ((1, 1), (1.6, 0.6), (2.9, 0.3)), noise=0.4))

# Ball drops into a pocket: low knock and a short roll.
roll = lowpass([random.random() * 2 - 1 for _ in range(n(0.25))], 0.05)
roll = [s * (1 - i / len(roll)) * 0.6 for i, s in enumerate(roll)]
save('pocket', mix((tone(140, 0.2, 0.06, ((1, 1), (2.1, 0.4)), noise=0.2), 0), (roll, 0.03)))

# Wooden piece on a board.
save('place', tone(520, 0.12, 0.025, ((1, 1), (2.3, 0.5), (4.1, 0.2)), noise=0.25))

# Short UI / tile click.
save('click', tone(1800, 0.04, 0.006, ((1, 1), (2.7, 0.4)), noise=0.3))

# Card flick: filtered noise burst.
card = highpass([random.random() * 2 - 1 for _ in range(n(0.07))], 0.2)
save('card', [s * env(i, len(card), 0.004, 0.018) for i, s in enumerate(card)], 0.7)

# Dice: several clicks with random pitch and timing.
parts = []
t = 0.0
for _ in range(9):
    f = random.uniform(900, 2200)
    parts.append((tone(f, 0.05, 0.008, ((1, 1), (2.2, 0.5)), noise=0.5), t))
    t += random.uniform(0.025, 0.06)
save('dice', pad(mix(*parts), 0.05))

# Dull hit (dart in the board, ball against a wall).
save('thud', tone(110, 0.15, 0.04, ((1, 1), (1.5, 0.5)), noise=0.35))

# Snake eats: quick rising blip.
blip = []
for i in range(n(0.09)):
    tt = i / RATE
    f = 600 + 6000 * tt
    blip.append(math.sin(2 * math.pi * f * tt) * env(i, n(0.09), 0.003, 0.04))
save('eat', blip, 0.6)

# Falling into a hole / game over: descending tone.
fall = []
phase = 0.0
for i in range(n(0.5)):
    tt = i / RATE
    f = 700 * math.exp(-3 * tt)
    phase += 2 * math.pi * f / RATE
    fall.append((math.sin(phase) + 0.3 * math.sin(2 * phase)) * (1 - tt / 0.5))
save('fall', fall, 0.6)


def note(freq, seconds):
    return tone(freq, seconds, 0.25, ((1, 1), (2, 0.35), (3, 0.15)), attack=0.005)


# Win: rising arpeggio C E G C.
save('win', pad(mix(
    (note(523.25, 0.4), 0.0),
    (note(659.25, 0.4), 0.11),
    (note(783.99, 0.4), 0.22),
    (note(1046.5, 0.7), 0.33),
), 0.05), 0.7)

# Lose: two falling notes.
save('lose', pad(mix(
    (note(392.0, 0.35), 0.0),
    (note(311.13, 0.6), 0.2),
), 0.05), 0.6)

print('ok', sorted(os.listdir(OUT)))

# --------------------------------------------------------------- 8-bit set
# Square waves and noise like an old console, used in the secret retro mode.
RETRO = os.path.join(OUT, 'retro')
os.makedirs(RETRO, exist_ok=True)


def square(freq_fn, seconds, volume=0.6, duty=0.5):
    out, phase = [], 0.0
    for i in range(n(seconds)):
        t = i / RATE
        phase = (phase + freq_fn(t) / RATE) % 1.0
        out.append(volume if phase < duty else -volume)
    return out


def noise(seconds, volume=0.5, hold=4):
    out, v = [], 0.0
    for i in range(n(seconds)):
        if i % hold == 0:
            v = random.choice((-volume, volume))
        out.append(v)
    return out


def fade(samples):
    total = len(samples)
    return [s * (1 - i / total) for i, s in enumerate(samples)]


def save_retro(name, samples):
    global OUT
    old, OUT = OUT, RETRO
    save(name, samples, 0.5)
    OUT = old


def seq(*notes):
    """Notes as (frequency, seconds); 0 = rest."""
    out = []
    for f, d in notes:
        out += square(lambda t, f=f: f, d) if f else [0.0] * n(d)
    return out


save_retro('clack', fade(square(lambda t: 1300, 0.03)))
save_retro('pocket', fade(square(lambda t: 500 * math.exp(-12 * t), 0.18)))
save_retro('place', fade(square(lambda t: 330, 0.05, duty=0.25)))
save_retro('click', fade(square(lambda t: 1600, 0.02)))
save_retro('card', fade(noise(0.045, hold=2)))
save_retro('dice', [s for _ in range(6)
                    for s in fade(square(lambda t, f=random.uniform(500, 1400): f, 0.035))
                    + [0.0] * n(0.015)])
save_retro('thud', fade([a + b for a, b in zip(noise(0.08, 0.4, 16),
                                                square(lambda t: 90, 0.08))]))
save_retro('eat', seq((880, 0.04), (1320, 0.05)))
save_retro('fall', fade(square(lambda t: 900 * math.exp(-4 * t), 0.45, duty=0.25)))
save_retro('win', seq((523, 0.08), (659, 0.08), (784, 0.08), (1047, 0.08),
                      (0, 0.04), (784, 0.08), (1047, 0.3)))
save_retro('lose', seq((392, 0.15), (370, 0.15), (349, 0.15), (330, 0.4)))
print('retro', sorted(os.listdir(RETRO)))
