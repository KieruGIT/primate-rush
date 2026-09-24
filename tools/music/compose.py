import numpy as np, subprocess
SR = 32000
rng = np.random.default_rng(7)

def note_hz(n):  # MIDI note -> Hz
    return 440.0 * 2 ** ((n - 69) / 12)

def env(n, a=0.005, d=0.08, s=0.6, r=0.05):
    t = np.arange(n) / SR
    e = np.ones(n) * s
    ai = int(a * SR); di = int(d * SR); ri = int(r * SR)
    if ai: e[:ai] = np.linspace(0, 1, ai)
    if di: e[ai:ai + di] = np.linspace(1, s, len(e[ai:ai + di]))
    if ri and n > ri: e[-ri:] *= np.linspace(1, 0, ri)
    return e

def square(hz, n, duty=0.5):
    ph = (np.arange(n) * hz / SR) % 1.0
    return np.where(ph < duty, 1.0, -1.0)

def tri(hz, n):
    ph = (np.arange(n) * hz / SR) % 1.0
    return 4 * np.abs(ph - 0.5) - 1

def noise(n):
    return rng.uniform(-1, 1, n)

class Track:
    def __init__(self, bpm, bars):
        self.beat = 60 / bpm
        self.n = int(round(bars * 4 * self.beat * SR))
        self.buf = np.zeros(self.n)
    def add(self, start_beat, sig, gain):
        i = int(round(start_beat * self.beat * SR)) % self.n
        end = i + len(sig)
        if end <= self.n:
            self.buf[i:end] += sig * gain
        else:  # wrap so the loop is seamless
            k = self.n - i
            self.buf[i:] += sig[:k] * gain
            self.buf[:end - self.n] += sig[k:] * gain
    def tone(self, beat, length, midi, kind='sq', gain=0.2, duty=0.5, **e):
        n = int(length * self.beat * SR)
        hz = note_hz(midi)
        w = square(hz, n, duty) if kind == 'sq' else tri(hz, n)
        self.add(beat, w * env(n, **e), gain)
    def kick(self, beat, gain=0.5):
        n = int(0.18 * SR); t = np.arange(n) / SR
        f = 120 * np.exp(-t * 25) + 45
        ph = np.cumsum(f) / SR
        self.add(beat, np.sin(2 * np.pi * ph) * np.exp(-t * 18), gain)
    def snare(self, beat, gain=0.25):
        n = int(0.16 * SR); t = np.arange(n) / SR
        self.add(beat, (noise(n) * 0.8 + np.sin(2*np.pi*190*t) * 0.4) * np.exp(-t * 22), gain)
    def hat(self, beat, gain=0.06, length=0.04):
        n = int(length * SR); t = np.arange(n) / SR
        w = noise(n); w = np.diff(np.concatenate([[0], w]))  # brighter
        self.add(beat, w * np.exp(-t * 90), gain)
    def render(self, path):
        x = self.buf
        # gentle low-pass to take the edge off raw squares
        k = np.array([0.25, 0.5, 0.25]); x = np.convolve(x, k, mode='same')
        x = x / (np.max(np.abs(x)) + 1e-9) * 0.8
        pcm = (x * 32767).astype(np.int16)
        wav = path.replace('.ogg', '.wav')
        import wave
        with wave.open(wav, 'wb') as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', wav, '-c:a', 'libvorbis', '-q:a', '3', path], check=True)

# chord roots (MIDI) and chord tones
C, Am, F, G, Dm, Em = [60,64,67], [57,60,64], [53,57,60], [55,59,62], [50,53,57], [52,55,59]

# ---------------- LOBBY: easy jungle groove, 100 bpm, 8 bars ----------
L = Track(100, 8)
prog = [C, Am, F, G, C, Am, Dm, G]
mel = [ (0,76,1),(1,74,0.5),(1.5,72,0.5),(2,69,1),(3,72,1),
        (4,72,1.5),(5.5,69,0.5),(6,67,2),
        (8,69,1),(9,72,1),(10,74,1),(11,72,0.5),(11.5,74,0.5),
        (12,71,2),(14,67,2),
        (16,76,1),(17,74,0.5),(17.5,72,0.5),(18,69,1),(19,72,1),
        (20,72,1.5),(21.5,76,0.5),(22,74,2),
        (24,72,1),(25,69,1),(26,74,1),(27,72,1),
        (28,71,1.5),(29.5,72,0.5),(30,74,2) ]
for bar, ch in enumerate(prog):
    b = bar * 4
    L.tone(b, 1.8, ch[0] - 24, 'tri', 0.45, a=0.01, d=0.2, s=0.7, r=0.1)
    L.tone(b + 2, 1.8, ch[0] - 24 + 7, 'tri', 0.4, a=0.01, d=0.2, s=0.7, r=0.1)
    for i in range(8):  # soft arpeggio
        L.tone(b + i * 0.5, 0.45, ch[i % 3] + (12 if i >= 4 else 0), 'sq', 0.05, duty=0.125, d=0.1, s=0.3, r=0.05)
    for i in range(4):
        L.hat(b + i + 0.5, 0.05)
    L.kick(b, 0.25); L.kick(b + 2.5, 0.18)
for beat, m, ln in mel:
    L.tone(beat, ln * 0.95, m, 'sq', 0.09, duty=0.25, a=0.01, d=0.1, s=0.55, r=0.06)
L.render('music_lobby.ogg')

# ---------------- BATTLE: driving, 150 bpm, 16 bars ----------------------
B = Track(150, 16)
prog = [Am, F, C, G, Am, F, C, G, Dm, F, Am, Em, Dm, F, G, G]
lead = [(0,69,.5),(.5,72,.5),(1,76,1),(2,74,.5),(2.5,72,.5),(3,74,1),
        (4,72,.5),(4.5,69,.5),(5,72,1),(6,77,1),(7,76,1),
        (8,76,.5),(8.5,79,.5),(9,76,1),(10,72,1),(11,74,1),
        (12,71,1.5),(13.5,74,.5),(14,79,1),(15,76,1)]
for bar, ch in enumerate(prog):
    b = bar * 4
    for i in range(8):  # pumping 8th bass
        B.tone(b + i * 0.5, 0.42, ch[0] - 24 + (12 if i % 4 == 3 else 0), 'sq', 0.16, duty=0.5, d=0.05, s=0.5, r=0.03)
    B.kick(b, 0.55); B.kick(b + 2, 0.55)
    if bar % 2 == 1: B.kick(b + 3.5, 0.35)
    B.snare(b + 1, 0.3); B.snare(b + 3, 0.3)
    for i in range(8):
        B.hat(b + i * 0.5, 0.07 if i % 2 else 0.04)
    for i in range(4):  # stabs
        B.tone(b + i + 0.5, 0.2, ch[1] + 12, 'sq', 0.04, duty=0.25, d=0.05, s=0.2, r=0.02)
for rep in range(4):  # lead phrase every 4 bars, varied on the last pass
    off = rep * 16
    shift = 0 if rep < 2 else (5 if rep == 2 else 2)
    if rep == 3:
        shift = 0
    for beat, m, ln in lead:
        B.tone(off + beat, ln * 0.9, m + (0 if rep != 2 else -2), 'sq', 0.08, duty=0.25, a=0.005, d=0.08, s=0.6, r=0.04)
B.render('music_battle.ogg')
print('done')
