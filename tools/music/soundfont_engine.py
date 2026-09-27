import os
"""Tiny sequencer + FluidSynth renderer for Primate Rush music.

Songs are written note by note in Python, rendered through the GeneralUser GS
soundfont, and cut into a seamless loop (the loop is rendered twice and the
second pass is kept, so reverb/release tails from the end already ring into
the start).
"""
import random
import subprocess
import numpy as np
import fluidsynth

SR = 44100
SF2 = os.environ.get("SOUNDFONT", os.path.join(os.path.dirname(os.path.abspath(__file__)), "GeneralUser.sf2"))
NAMES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi(name):
    """'C4' -> 60, 'Bb3' -> 58, 'F#5' -> 78. Ints pass through."""
    if isinstance(name, int):
        return name
    n = NAMES[name[0]]
    i = 1
    while i < len(name) and name[i] in "#b":
        n += 1 if name[i] == "#" else -1
        i += 1
    return n + 12 * (int(name[i:]) + 1)


QUAL = {
    "": [0, 4, 7], "m": [0, 3, 7], "7": [0, 4, 7, 10], "m7": [0, 3, 7, 10],
    "maj7": [0, 4, 7, 11], "sus": [0, 5, 7], "dim": [0, 3, 6], "6": [0, 4, 7, 9],
    "m6": [0, 3, 7, 9], "add9": [0, 4, 7, 14], "5": [0, 7],
}


def chord(sym):
    """'Fmaj7' -> (root pitch class, intervals)."""
    root = sym[0]
    rest = sym[1:]
    pc = NAMES[root]
    if rest[:1] in ("#", "b"):
        pc += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    return pc % 12, QUAL[rest]


def near(pc, around):
    """Pitch class -> the MIDI note of that class nearest `around`."""
    base = around - ((around - pc) % 12)
    return base + 12 if around - base > 6 else base


class Song:
    def __init__(self, bpm, bars, swing=0.0, human=0.006, seed=1):
        self.bpm = bpm
        self.bars = bars
        self.swing = swing          # 0..~0.33 delay of off 16ths (in 16th units)
        self.human = human          # timing jitter (seconds)
        self.events = []            # (sec, order, kind, ch, a, b)
        self.rng = random.Random(seed)
        self.setup = {}

    @property
    def beats(self):
        return self.bars * 4

    def sec(self, beat):
        sixteenth = beat * 4.0
        idx = int(np.floor(sixteenth + 1e-6))
        frac = sixteenth - idx
        if self.swing and idx % 2 == 1 and frac < 1e-6:
            sixteenth += self.swing
        return sixteenth / 4.0 * 60.0 / self.bpm

    def inst(self, ch, program, vol=100, pan=64, rev=40, cho=0, bank=0):
        self.setup[ch] = (bank, program, vol, pan, rev, cho)

    def note(self, ch, beat, dur, pitch, vel=90, jitter=True):
        p = midi(pitch)
        t0 = self.sec(beat)
        t1 = self.sec(beat + dur) - 0.012
        j = self.rng.uniform(-self.human, self.human) if jitter else 0.0
        v = max(1, min(127, int(vel + self.rng.uniform(-6, 6))))
        self.events.append((max(0.0, t0 + j), 1, "on", ch, p, v))
        self.events.append((max(t0 + 0.02, t1 + j), 0, "off", ch, p, 0))

    def hit(self, beat, key, vel=90, dur=0.25):
        self.note(9, beat, dur, key, vel)

    def mel(self, ch, beat, text, vel=92, shift=0, legato=0.95):
        """'E5/.5 G5/1 r/.5' — pitch/duration in beats, r = rest."""
        for tok in text.split():
            p, d = tok.split("/")
            d = float(d)
            if p != "r":
                self.note(ch, beat, d * legato, midi(p) + shift, vel)
            beat += d
        return beat

    def cc(self, ch, beat, ctrl, val):
        self.events.append((self.sec(beat), -1, "cc", ch, ctrl, val))


def render(song, out_base, gain=0.55, room=(0.62, 0.35, 0.9, 0.55), lufs=-15.0):
    fs = fluidsynth.Synth(gain=gain, samplerate=SR)
    try:
        fs.set_reverb(*room)
    except Exception:
        pass
    sfid = fs.sfload(SF2)
    for ch, (bank, prog, vol, pan, rev, cho) in song.setup.items():
        fs.program_select(ch, sfid, bank, prog)
        fs.cc(ch, 7, vol)
        fs.cc(ch, 10, pan)
        fs.cc(ch, 91, rev)
        fs.cc(ch, 93, cho)

    loop_sec = song.beats * 60.0 / song.bpm
    loop_n = int(round(loop_sec * SR))
    evs = []
    for p in range(2):
        off = p * loop_sec
        for e in song.events:
            evs.append((e[0] + off,) + e[1:])
    evs.sort(key=lambda e: (e[0], e[1]))
    total = loop_n * 2 + SR  # one extra second so pass 2 isn't cut abruptly
    chunks = []
    pos = 0
    for t, _, kind, ch, a, b in evs:
        s = min(int(t * SR), total)
        if s > pos:
            chunks.append(fs.get_samples(s - pos))
            pos = s
        if kind == "on":
            fs.noteon(ch, a, b)
        elif kind == "off":
            fs.noteoff(ch, a)
        else:
            fs.cc(ch, a, b)
    if total > pos:
        chunks.append(fs.get_samples(total - pos))
    fs.delete()
    audio = np.concatenate(chunks).astype(np.float32).reshape(-1, 2) / 32768.0
    body = audio[loop_n:loop_n * 2]
    raw = out_base + ".f32"
    body.astype("<f4").tofile(raw)
    common = ["ffmpeg", "-y", "-loglevel", "error", "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", raw]
    # One gain for the whole file (measured, not dynamic), so the loop joint
    # stays seamless.
    peak = float(np.abs(body).max())
    rms = float(np.sqrt((body ** 2).mean()))
    target_rms = 10 ** ((lufs + 3.0) / 20.0)
    g = min(target_rms / max(rms, 1e-6), 1.8 / max(peak, 1e-6))
    def encode(gain, ext, codec):
        af = f"volume={gain:.4f},alimiter=limit=0.9:attack=2:release=60:level=false"
        subprocess.run(common + ["-af", af, "-c:a", codec, "-q:a", "5" if ext == "ogg" else "3",
                                 out_base + "." + ext], check=True)
    encode(g, "ogg", "libvorbis")
    meas = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", out_base + ".ogg", "-af",
                           "ebur128=framelog=quiet", "-f", "null", "-"], capture_output=True, text=True).stderr
    got = float([l for l in meas.splitlines() if l.strip().startswith("I:")][-1].split()[1])
    g *= 10 ** ((lufs - got) / 20.0)
    encode(g, "ogg", "libvorbis")
    encode(g, "mp3", "libmp3lame")
    return loop_sec
