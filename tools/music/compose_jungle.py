"""JUNGLE MUSIC - writes assets/music/music_lobby.ogg and music_battle.ogg.

    python tools/music/compose_jungle.py [project_root]

Marimba, kalimba, bongos, conga slap, shaker, log drum, bass, a soft pad and
a flute lead, every note synthesized here with numpy (no samples, nothing to
license). Each track is about a minute with sections (intro, tune, chorus,
breakdown) and loops seamlessly: the tail of the last bar is wrapped onto
the first. Needs numpy, scipy and ffmpeg. Replaces the older chiptune
compose.py, which is kept for reference.
"""
import numpy as np
from scipy.signal import butter, lfilter
import subprocess, sys

SR = 44100
rng = np.random.default_rng(7)

NOTE = {'C': 0, 'C#': 1, 'D': 2, 'D#': 3, 'E': 4, 'F': 5, 'F#': 6, 'G': 7, 'G#': 8, 'A': 9, 'A#': 10, 'B': 11}


def hz(name):
    # "A4", "C#5"
    n, o = name[:-1], int(name[-1])
    return 440.0 * 2 ** ((NOTE[n] + 12 * (o + 1) - 69) / 12)


def env(n, attack, decay):
    t = np.arange(n) / SR
    e = np.exp(-t / decay)
    a = int(attack * SR)
    if a > 0:
        e[:a] *= np.linspace(0, 1, a)
    return e


def marimba(f, dur=0.9):
    n = int(dur * SR)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * f * t) * env(n, 0.002, 0.28)
    over = 0.35 * np.sin(2 * np.pi * f * 3.93 * t) * env(n, 0.001, 0.05)
    over2 = 0.12 * np.sin(2 * np.pi * f * 9.2 * t) * env(n, 0.001, 0.015)
    click = rng.normal(0, 1, n) * env(n, 0.0, 0.004) * 0.15
    return (body + over + over2 + click) * 0.5


def kalimba(f, dur=1.2):
    n = int(dur * SR)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * f * t) * env(n, 0.001, 0.5) + 0.25 * np.sin(2 * np.pi * f * 5.4 * t) * env(n, 0.001, 0.03)
    return s * 0.35


def bass(f, dur=0.5):
    n = int(dur * SR)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * 2 * f * t) * env(n, 0, 0.08)
    return s * env(n, 0.004, 0.25) * 0.55


def bongo(high=True):
    f0 = 420 if high else 280
    n = int(0.25 * SR)
    t = np.arange(n) / SR
    f = f0 * (1 + 0.5 * np.exp(-t / 0.01))
    ph = 2 * np.pi * np.cumsum(f) / SR
    s = np.sin(ph) * env(n, 0.0005, 0.07)
    s += rng.normal(0, 1, n) * env(n, 0, 0.006) * 0.3
    return s * 0.45


def conga_slap():
    n = int(0.12 * SR)
    s = rng.normal(0, 1, n) * env(n, 0, 0.018)
    b, a = butter(2, [900 / (SR / 2), 4000 / (SR / 2)], btype='band')
    return lfilter(b, a, s) * 0.5


def log_drum():
    n = int(0.45 * SR)
    t = np.arange(n) / SR
    f = 70 * (1 + 1.2 * np.exp(-t / 0.03))
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.001, 0.16)
    return s * 0.8


def shaker(accent=1.0):
    n = int(0.09 * SR)
    s = rng.normal(0, 1, n)
    b, a = butter(2, 5500 / (SR / 2), btype='high')
    s = lfilter(b, a, s)
    e = env(n, 0.012, 0.025)
    return s * e * 0.10 * accent


def flute(f, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.2 * t) * np.clip(t / 0.25, 0, 1)
    ph = 2 * np.pi * np.cumsum(f * vib) / SR
    s = np.sin(ph) + 0.18 * np.sin(2 * ph) + 0.06 * np.sin(3 * ph)
    breath = rng.normal(0, 1, n)
    b, a = butter(2, [f * 0.8 / (SR / 2), min(f * 4, 18000) / (SR / 2)], btype='band')
    s += lfilter(b, a, breath) * 0.08
    e = np.ones(n)
    a_n, r_n = int(0.05 * SR), int(min(0.12, dur * 0.4) * SR)
    e[:a_n] = np.linspace(0, 1, a_n)
    e[-r_n:] *= np.linspace(1, 0, r_n)
    return s * e * 0.22


def pad(freqs, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    s = sum(np.sin(2 * np.pi * f * t + i) + 0.5 * np.sin(2 * np.pi * f * 1.004 * t) for i, f in enumerate(freqs))
    e = np.ones(n)
    a_n = int(min(0.6, dur / 3) * SR)
    e[:a_n] = np.linspace(0, 1, a_n)
    e[-a_n:] *= np.linspace(1, 0, a_n)
    b, a = butter(2, 1800 / (SR / 2))
    return lfilter(b, a, s * e) * 0.035


class Track:
    def __init__(self, bpm, bars):
        self.beat = 60.0 / bpm
        self.bar = self.beat * 4
        self.n = int(round(self.bar * bars * SR))
        self.buf = np.zeros(self.n + SR * 3)

    def put(self, sound, beat_pos, gain=1.0, pan=0.0):
        i = int(round(beat_pos * self.beat * SR))
        self.buf[i:i + len(sound)] += sound * gain

    def render(self):
        out = self.buf[:self.n].copy()
        tail = self.buf[self.n:]
        out[:len(tail)] += tail[:self.n]      # wrap the tail: seamless loop
        # soft room: two short echoes
        d1, d2 = int(0.11 * SR), int(0.23 * SR)
        wet = np.zeros_like(out)
        wet[d1:] += out[:-d1] * 0.18
        wet[d2:] += out[:-d2] * 0.10
        out = out + wet
        out = np.tanh(out * 1.3) / np.tanh(1.3)
        return out / (np.max(np.abs(out)) + 1e-9) * 0.85


# ---- harmony: A minor pentatonic-ish, progression Am - F - C - G ----
PROG = [('A2', ['A3', 'C4', 'E4']), ('F2', ['F3', 'A3', 'C4']), ('C3', ['C4', 'E4', 'G4']), ('G2', ['G3', 'B3', 'D4'])]


def groove(tr, bar, busy=1.0, kick=False):
    b0 = bar * 4
    # shaker 16ths
    for s in range(16):
        tr.put(shaker(1.4 if s % 4 == 2 else 0.8), b0 + s / 4)
    # bongo pattern (tumbao-ish)
    for pos, hi in [(0.5, True), (1.0, False), (1.75, True), (2.5, True), (3.0, False), (3.5, True), (3.75, True)]:
        if busy >= 1 or pos in (1.0, 3.0, 3.5):
            tr.put(bongo(hi), b0 + pos)
    if busy >= 1:
        tr.put(conga_slap(), b0 + 2.0, 0.7)
    if kick:
        for q in range(4):
            tr.put(log_drum(), b0 + q, 0.9)
    else:
        tr.put(log_drum(), b0, 0.8)
        tr.put(log_drum(), b0 + 2.5, 0.6)


def bassline(tr, bar, root, pattern=(0, 1.5, 2, 3.5)):
    f = hz(root)
    for i, p in enumerate(pattern):
        tr.put(bass(f * (2 if i == 2 else 1), 0.45), bar * 4 + p)


def marimba_ostinato(tr, bar, chord, density=8):
    notes = [hz(c) * 2 for c in chord]
    seq = [0, 1, 2, 1, 0, 2, 1, 2]
    for i in range(density):
        tr.put(marimba(notes[seq[i % 8]]), bar * 4 + i * (4 / density), 0.55)


def melody(tr, start_bar, notes, instr='marimba'):
    """notes: list of (name or None, beats)"""
    pos = start_bar * 4
    for name, length in notes:
        if name:
            if instr == 'marimba':
                tr.put(marimba(hz(name), 1.0), pos, 0.9)
                if length >= 1:
                    tr.put(marimba(hz(name), 0.6), pos + 0.25, 0.35)   # marimba roll feel
            elif instr == 'flute':
                tr.put(flute(hz(name), length * tr.beat * 0.95), pos, 1.0)
            else:
                tr.put(kalimba(hz(name)), pos, 0.9)
        pos += length


HOOK_A = [('E5', 1), ('G5', 0.5), ('A5', 1), ('G5', 0.5), ('E5', 1),
          ('D5', 1), ('C5', 0.5), ('D5', 0.5), ('E5', 2),
          ('C5', 1), ('D5', 0.5), ('E5', 1), ('G5', 0.5), ('A5', 1),
          ('G5', 1), ('E5', 0.5), ('D5', 0.5), ('D5', 2)]
HOOK_B = [('A5', 1.5), ('G5', 0.5), ('E5', 1), ('G5', 1),
          ('C6', 1.5), ('B5', 0.5), ('A5', 2),
          ('A5', 1), ('C6', 1), ('D6', 1), ('C6', 0.5), ('A5', 0.5),
          ('G5', 1.5), ('E5', 0.5), ('G5', 2)]


def lobby():
    tr = Track(bpm=100, bars=24)
    for bar in range(24):
        root, chord = PROG[bar % 4]
        sec = bar // 4
        tr.put(pad([hz(c) for c in chord], tr.bar), bar * 4)
        if sec == 0:                      # intro: kalimba + shaker only
            groove(tr, bar, busy=0)
            marimba_ostinato(tr, bar, chord, 4)
        elif sec in (1, 2):               # A: hook on marimba
            groove(tr, bar)
            bassline(tr, bar, root)
            marimba_ostinato(tr, bar, chord, 8)
        elif sec in (3, 4):               # B: flute chorus
            groove(tr, bar)
            bassline(tr, bar, root)
            marimba_ostinato(tr, bar, chord, 8)
        else:                             # breakdown
            groove(tr, bar, busy=0)
            bassline(tr, bar, root, (0, 2))
    melody(tr, 4, HOOK_A * 2, 'marimba')
    melody(tr, 12, HOOK_B * 2, 'flute')
    melody(tr, 20, HOOK_A, 'kalimba')
    return tr.render()


def battle():
    tr = Track(bpm=138, bars=32)
    prog = [PROG[0], PROG[0], PROG[1], PROG[3]]
    for bar in range(32):
        root, chord = prog[bar % 4]
        sec = bar // 8
        groove(tr, bar, kick=sec != 2)
        bassline(tr, bar, root, (0, 0.75, 1.5, 2, 2.75, 3.5))
        marimba_ostinato(tr, bar, chord, 8)
        if sec == 2:
            tr.put(pad([hz(c) for c in chord], tr.bar), bar * 4)
    fast_a = [('A5', 0.5), ('A5', 0.5), ('G5', 0.5), ('A5', 0.5), ('C6', 1), ('A5', 1),
              ('G5', 0.5), ('E5', 0.5), ('G5', 1), ('E5', 1), ('D5', 1),
              ('E5', 0.5), ('G5', 0.5), ('A5', 1), ('C6', 0.5), ('D6', 0.5), ('E6', 1),
              ('D6', 0.5), ('C6', 0.5), ('A5', 1), ('G5', 2)]
    melody(tr, 8, fast_a * 2, 'marimba')
    melody(tr, 16, HOOK_B * 2, 'flute')
    melody(tr, 24, fast_a * 2, 'marimba')
    melody(tr, 24, fast_a * 2, 'flute')
    return tr.render()


def save(data, name):
    stereo = np.stack([data, np.roll(data, int(0.008 * SR)) * 0.96], axis=1)
    pcm = (stereo * 32767).astype(np.int16)
    raw = '/tmp/%s.raw' % name.replace('/', '_')
    pcm.tofile(raw)
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-f', 's16le', '-ar', str(SR), '-ac', '2', '-i', raw,
                    '-c:a', 'libvorbis', '-q:a', '4', name], check=True)


if __name__ == '__main__':
    root = sys.argv[1] if len(sys.argv) > 1 else '.'
    # The lobby track is now a supplied song (assets/music/music_lobby.ogg);
    # pass --lobby to overwrite it with the generated jungle loop.
    if '--lobby' in sys.argv:
        save(lobby(), root + '/assets/music/music_lobby.ogg')
    save(battle(), root + '/assets/music/music_battle.ogg')
    print('done')
