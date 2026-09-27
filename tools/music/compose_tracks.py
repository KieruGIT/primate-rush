import os
"""The five Primate Rush tracks. Run: python3 songs.py [name ...]"""
import sys
from soundfont_engine import Song, render, chord, near, midi

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out") + os.sep

# GM drum keys
KICK, STICK, SNARE, CLAP, HAT, PHAT, OHAT = 36, 37, 38, 39, 42, 44, 46
TOM_L, TOM_M, TOM_H, CRASH, RIDE, TAMB, COWBELL = 45, 47, 50, 49, 51, 54, 56
BONGO_H, BONGO_L, CONGA_MH, CONGA_OH, CONGA_L = 60, 61, 62, 63, 64
TIMB_H, TIMB_L, AGOGO_H, AGOGO_L, CABASA, MARACA = 65, 66, 67, 68, 69, 70
WHISTLE_S, GUIRO, CLAVES, WB_H, WB_L, CUICA_M, CUICA_O, TRI = 71, 73, 75, 76, 77, 78, 79, 81


def chord_notes(sym, around=62, spread=False):
    pc, iv = chord(sym)
    root = near(pc, around - 4)
    notes = [root + i for i in iv]
    if spread and len(notes) >= 3:
        notes[1] += 12
    return notes


def bass_root(sym, around=40):
    return near(chord(sym)[0], around)


# ---------------------------------------------------------------- LOBBY
def lobby():
    """Banana Lounge: laid-back tropical groove in F, 102 bpm, swung."""
    s = Song(102, 32, swing=0.22, seed=11)
    s.inst(0, 12, vol=92, pan=44, rev=45)            # marimba
    s.inst(1, 24, vol=70, pan=86, rev=40)            # nylon guitar
    s.inst(2, 33, vol=104, pan=64, rev=15)           # fingered bass
    s.inst(3, 73, vol=88, pan=60, rev=70, cho=20)    # flute lead
    s.inst(4, 11, vol=74, pan=70, rev=70)            # vibraphone double
    s.inst(5, 89, vol=46, pan=64, rev=80, cho=40)    # warm pad
    s.inst(9, 0, vol=96, bank=128, rev=30)           # standard kit

    A = ["Fmaj7", "Dm7", "Gm7", "C7", "Fmaj7", "Dm7", "Bbmaj7", "C7"]
    B = ["Bbmaj7", "Am7", "Gm7", "C7", "Bbmaj7", "A7", "Dm7", "Gm7"]
    form = A + A + B + A
    for bar, sym in enumerate(form):
        b = bar * 4
        nxt = form[(bar + 1) % len(form)]
        tones = chord_notes(sym, 66)
        # marimba: bouncy broken chord
        for t, k, v in [(0, 0, 90), (0.75, 2, 70), (1.5, 1, 80), (2, 3 % len(tones), 76),
                        (2.75, 2, 68), (3.5, 1, 74)]:
            s.note(0, b + t, 0.4, tones[k % len(tones)] + (12 if t in (2,) else 0), v)
        # guitar: soft offbeat skank
        for t in (0.5, 1.5, 2.5, 3.5):
            for n in chord_notes(sym, 60)[:3]:
                s.note(1, b + t, 0.22, n, 62)
        # bass
        r = bass_root(sym, 41)
        fifth = r + 7 if r + 7 <= 50 else r - 5
        nr = bass_root(nxt, 41)
        s.note(2, b, 0.7, r, 100)
        s.note(2, b + 0.75, 0.2, r, 60)
        s.note(2, b + 1.5, 0.45, fifth, 84)
        s.note(2, b + 2, 0.45, r + 12, 88)
        s.note(2, b + 2.75, 0.2, fifth, 66)
        s.note(2, b + 3.5, 0.45, nr - 1 if bar % 2 else nr + 2, 80)
        # pad
        for n in chord_notes(sym, 60):
            s.note(5, b, 3.9, n, 50)
        # drums
        s.hit(b, KICK, 96); s.hit(b + 1.75, KICK, 64); s.hit(b + 2.5, KICK, 84)
        s.hit(b + 1, STICK, 80); s.hit(b + 3, STICK, 84)
        for i in range(16):
            s.hit(b + i * 0.25, MARACA, 58 if i % 2 else 76)
        for t, k, v in [(0.5, CONGA_MH, 70), (1.5, CONGA_OH, 80), (1.75, CONGA_OH, 62),
                        (2.5, CONGA_L, 82), (3.5, CONGA_OH, 74), (3.75, CONGA_MH, 60)]:
            s.hit(b + t, k, v)
        if bar % 4 == 3:
            for t, k in [(3.0, BONGO_H), (3.25, BONGO_H), (3.5, BONGO_L), (3.75, BONGO_L)]:
                s.hit(b + t, k, 84)
        if bar % 8 == 0:
            s.hit(b, TRI, 60)

    melA = [
        "r/.5 C5/.5 F5/.5 A5/.5 G5/.75 F5/.25 E5/1",
        "D5/1.5 r/.5 F5/.5 E5/.5 D5/.5 C5/.5",
        "Bb4/.5 D5/.5 F5/1 E5/.5 F5/.5 G5/1",
        "A5/.75 G5/.25 E5/.5 C5/.5 r/1 C5/.25 D5/.25 E5/.5",
        "F5/.5 A5/.5 C6/1 A5/.5 G5/.5 F5/1",
        "D5/.5 F5/.5 A5/1.5 G5/.5 F5/1",
        "D5/.5 F5/.5 A5/.5 Bb5/.5 A5/.5 F5/.5 D5/1",
        "E5/1 G5/.5 Bb5/.5 A5/.75 G5/.25 E5/.5 C5/.5",
    ]
    melB = [
        "F5/1.5 D5/.5 F5/.5 A5/1.5",
        "G5/1 E5/.5 C5/.5 E5/2",
        "D5/.5 F5/.5 Bb5/1 A5/.5 G5/.5 F5/1",
        "E5/2 r/1 C5/.5 E5/.5",
        "D5/.5 F5/.5 A5/.5 C6/1.5 Bb5/.5 A5/.5",
        "C#6/1 A5/.5 E5/.5 G5/1.5 r/.5",
        "F5/.5 E5/.5 D5/.5 F5/.5 A5/.5 G5/.5 F5/.5 E5/.5",
        "G5/1 Bb5/1 A5/.5 G5/.5 E5/1",
    ]
    endA = melA[:7] + ["E5/.5 G5/.5 Bb5/.5 A5/.5 G5/1 r/1"]
    for sec, mel in [(8, melA), (16, melB), (24, endA)]:
        for i, line in enumerate(mel):
            s.mel(3, (sec + i) * 4, line, 90, shift=-12 if sec == 24 and i < 4 else 0)
            s.mel(4, (sec + i) * 4, line, 64, legato=0.6)
    return s


# ------------------------------------------------------------ JUNGLE RUN
def jungle_run():
    """Race: bright, driving, 'go go go'. A major, 156 bpm."""
    s = Song(156, 32, swing=0.0, seed=21)
    s.inst(0, 36, vol=100, pan=64, rev=10)           # slap bass
    s.inst(1, 12, vol=88, pan=40, rev=35)            # marimba ostinato
    s.inst(2, 61, vol=96, pan=76, rev=45)            # brass section
    s.inst(3, 13, vol=90, pan=54, rev=40)            # xylophone lead
    s.inst(4, 28, vol=64, pan=92, rev=20)            # muted guitar chugs
    s.inst(5, 48, vol=70, pan=64, rev=60)            # strings (build)
    s.inst(9, 16, vol=100, bank=128, rev=25)         # power kit

    groove = ["A", "A", "G", "D", "F", "G", "A", "A"]
    build = ["D", "D", "E", "E", "F", "F", "G", "G"]
    form = groove * 3 + build
    for bar, sym in enumerate(form):
        b = bar * 4
        sect = bar // 8
        r = bass_root(sym, 38)
        tones = chord_notes(sym, 70)
        # bass: galloping octaves
        if sect < 3:
            for i, t in enumerate([0, 0.5, 0.75, 1.5, 2, 2.5, 2.75, 3.5]):
                s.note(0, b + t, 0.22, r + (12 if i in (2, 6) else 0), 96 if t % 1 == 0 else 78)
        else:
            s.note(0, b, 1.8, r, 96); s.note(0, b + 2, 1.8, r, 88)
        # marimba 16th arpeggio
        pat = [0, 1, 2, 1, 3, 2, 1, 2]
        for i in range(16):
            n = tones[pat[i % 8] % len(tones)] + (12 if pat[i % 8] == 3 else 0)
            s.note(1, b + i * 0.25, 0.2, n, 82 if i % 4 == 0 else 62)
        # guitar chugs
        if sect in (1, 2):
            for i in range(8):
                for n in chord_notes(sym, 52)[:2] + [chord_notes(sym, 52)[0] + 12]:
                    s.note(4, b + i * 0.5, 0.18, n, 70)
        # brass stabs
        if sect == 0 and bar % 4 == 3 or sect in (1, 2) and bar % 2 == 1:
            for n in chord_notes(sym, 64):
                s.note(2, b + 2.5, 0.3, n, 96); s.note(2, b + 3.5, 0.4, n, 104)
        # drums
        if sect < 3:
            for t in (0, 1, 2, 3):
                s.hit(b + t, KICK, 104)
            s.hit(b + 1, SNARE, 100); s.hit(b + 3, SNARE, 104)
            for i in range(8):
                s.hit(b + i * 0.5, OHAT if i == 7 else HAT, 70 if i % 2 else 84)
            for t, k in [(0.25, CONGA_MH), (0.75, CONGA_OH), (1.5, CONGA_L), (2.25, CONGA_MH), (2.75, CONGA_OH), (3.5, CONGA_L)]:
                s.hit(b + t, k, 70)
            if bar % 8 == 0:
                s.hit(b, CRASH, 100)
            if bar % 8 == 7:
                for i, k in enumerate([TOM_H, TOM_H, TOM_M, TOM_M, TOM_L, TOM_L, SNARE, SNARE]):
                    s.hit(b + 2 + i * 0.25, k, 90 + i * 3)
        else:
            j = bar - 24
            s.hit(b, KICK, 100); s.hit(b + 2, SNARE, 96)
            for i in range(4):
                s.hit(b + i + 0.5, HAT, 70)
            if j >= 4:
                for i in range(8 if j < 6 else 16):
                    step = 4 / (8 if j < 6 else 16)
                    s.hit(b + i * step, SNARE if j >= 6 else TOM_M, 60 + i * (4 if j < 6 else 3))
            if j == 0:
                s.hit(b, CRASH, 96)
            # strings rising line
            s.note(5, b, 3.9, tones[0] - 12 + (2 if j % 2 else 0), 78)
            s.note(5, b, 3.9, tones[2] - 12, 70)

    theme = [
        "E5/.5 A5/.5 C#6/.5 B5/.5 A5/1 E5/1",
        "F#5/.5 E5/.5 C#5/.5 E5/.5 A5/2",
        "D5/.5 G5/.5 B5/.5 A5/.5 G5/1 D5/1",
        "F#5/.5 A5/.5 D6/1 C#6/.5 B5/.5 A5/1",
        "C6/1 A5/.5 F5/.5 A5/.5 C6/.5 D6/1",
        "B5/1 G5/.5 D5/.5 G5/.5 B5/.5 D6/1",
        "E6/1.5 C#6/.5 A5/1 E5/1",
        "A5/.5 B5/.5 C#6/.5 E6/.5 A6/1 r/1",
    ]
    var = theme[:4] + [
        "F5/.5 A5/.5 C6/.5 A5/.5 F5/1 C5/1",
        "D5/.5 G5/.5 B5/.5 D6/.5 G6/1.5 r/.5",
        "E6/.5 D6/.5 C#6/.5 B5/.5 A5/.5 B5/.5 C#6/1",
        "A5/2 r/2",
    ]
    for sec, mel in [(8, theme), (16, var)]:
        for i, line in enumerate(mel):
            s.mel(3, (sec + i) * 4, line, 96, legato=0.7)
            s.mel(2, (sec + i) * 4, line, 84, shift=-12, legato=0.85)
    return s


# ---------------------------------------------------------- CANOPY CLIMB
def canopy_climb():
    """Race up the trees: adventurous, rising. D major, 144 bpm."""
    s = Song(144, 32, seed=31)
    s.inst(0, 45, vol=92, pan=50, rev=45)            # pizzicato strings
    s.inst(1, 108, vol=78, pan=84, rev=55)           # kalimba sparkle
    s.inst(2, 60, vol=96, pan=58, rev=65)            # french horn lead
    s.inst(3, 61, vol=90, pan=70, rev=55)            # brass section
    s.inst(4, 48, vol=76, pan=64, rev=70)            # strings
    s.inst(5, 32, vol=100, pan=64, rev=20)           # acoustic bass
    s.inst(6, 47, vol=92, pan=64, rev=60)            # timpani
    s.inst(9, 0, vol=94, bank=128, rev=35)

    A = ["D", "C", "G", "D", "Bm", "G", "A", "A"]
    B = ["G", "A", "F#m", "Bm", "G", "A", "Bb", "C"]
    form = A + B + A + B
    for bar, sym in enumerate(form):
        b = bar * 4
        tones = chord_notes(sym, 66)
        r = bass_root(sym, 40)
        # pizz ostinato
        for i, k in enumerate([0, 2, 1, 2, 0, 2, 1, 2]):
            s.note(0, b + i * 0.5, 0.3, tones[k] + (12 if i >= 4 else 0), 84 if i % 2 == 0 else 66)
        # kalimba sparkle every other bar
        if bar % 2 == 1:
            for i, k in enumerate([0, 1, 2, 1, 2, 0]):
                s.note(1, b + i * 0.75, 0.5, tones[k] + 12, 70)
        # bass
        for t, n, v in [(0, r, 96), (1.5, r, 76), (2, r + 7, 84), (3, r + 12, 80), (3.5, r + 7, 70)]:
            s.note(5, b + t, 0.45, n if n < 55 else n - 12, v)
        # timpani on phrase starts
        if bar % 4 == 0:
            s.note(6, b, 1, r + 12 if r + 12 < 50 else r, 100)
        if bar % 8 == 7:
            for i in range(8):
                s.note(6, b + 2 + i * 0.25, 0.2, r + 7 - 12 if r + 7 > 50 else r + 7, 70 + i * 5)
        # strings pad
        for n in chord_notes(sym, 58):
            s.note(4, b, 3.95, n, 64 if bar < 16 else 76)
        # drums: driving, lighter than a battle
        s.hit(b, KICK, 96); s.hit(b + 1.5, KICK, 70); s.hit(b + 2, KICK, 90)
        s.hit(b + 1, SNARE, 84); s.hit(b + 3, SNARE, 90)
        for i in range(8):
            s.hit(b + i * 0.5, TAMB if i % 2 else HAT, 64 if i % 2 else 72)
        if bar % 8 == 0:
            s.hit(b, CRASH, 94)
        if bar % 8 == 7:
            for i, k in enumerate([TOM_H, TOM_M, TOM_L, SNARE]):
                s.hit(b + 3 + i * 0.25, k, 96)

    melA = [
        "A4/1 D5/1 E5/.5 F#5/.5 A5/1",
        "G5/1.5 E5/.5 C5/2",
        "B4/1 D5/1 G5/1 F#5/.5 E5/.5",
        "F#5/3 r/1",
        "B4/1 D5/.5 F#5/.5 B5/2",
        "A5/.5 G5/.5 F#5/.5 E5/.5 D5/1 B4/1",
        "C#5/1 E5/1 A5/1 G5/.5 F#5/.5",
        "E5/3 r/1",
    ]
    melB = [
        "D5/.5 G5/.5 B5/1.5 A5/.5 G5/1",
        "C#5/.5 E5/.5 A5/1.5 G5/.5 F#5/1",
        "C#5/.5 F#5/.5 A5/1.5 G#5/.5 F#5/1",
        "D5/.5 F#5/.5 B5/2 A5/1",
        "B5/1 A5/.5 G5/.5 D5/1 G5/1",
        "C#6/1 B5/.5 A5/.5 E5/1 A5/1",
        "D6/1.5 C6/.5 Bb5/1 F5/1",
        "E6/2 G5/.5 C6/.5 E6/1",
    ]
    for sec, mel, ch, sh, v in [(0, melA, 2, 0, 90), (8, melB, 3, -12, 92),
                                (16, melA, 2, 12, 84), (24, melB, 3, -12, 100)]:
        for i, line in enumerate(mel):
            s.mel(ch, (sec + i) * 4, line, v, shift=sh, legato=0.92)
            if sec >= 16:
                s.mel(4, (sec + i) * 4, line, 70, shift=0 if sec == 16 else 0, legato=0.95)
            if sec == 16:
                s.mel(2, (sec + i) * 4, line, 70, shift=0)
    return s


# ----------------------------------------------------------- SLAP ISLAND
PHRY = [0, 1, 3, 5, 7, 8, 10]  # D phrygian steps


def slap_island():
    """Battle on the island: tribal drums, low brass, ape calls. D minor, 132 bpm."""
    s = Song(132, 32, seed=41)
    s.inst(0, 57, vol=104, pan=56, rev=35)           # trombone riff
    s.inst(1, 58, vol=100, pan=64, rev=30)           # tuba doubling
    s.inst(2, 48, vol=86, pan=78, rev=55)            # strings staccato
    s.inst(3, 61, vol=100, pan=60, rev=55)           # brass melody
    s.inst(4, 116, vol=110, pan=64, rev=60)          # taiko
    s.inst(5, 52, vol=78, pan=64, rev=85)            # choir aahs
    s.inst(6, 55, vol=84, pan=64, rev=70)            # orchestra hit
    s.inst(7, 44, vol=70, pan=40, rev=60)            # tremolo strings
    s.inst(9, 16, vol=104, bank=128, rev=30)

    prog = ["Dm", "Dm", "Bb", "Cm", "Dm", "Dm", "Eb", "A"]
    brk = ["Dm", "Dm", "Bb", "A", "Dm", "Dm", "Bb", "A"]
    form = prog + prog + brk + prog
    scale = [midi("D2") + x for x in PHRY]

    def deg_note(root_pc, step):
        # root's index in the phrygian scale, then walk `step` degrees
        idx = [x % 12 for x in scale].index(root_pc % 12) if root_pc % 12 in [x % 12 for x in scale] else 0
        k = idx + step
        return scale[k % 7] + 12 * (k // 7)

    for bar, sym in enumerate(form):
        b = bar * 4
        sect = bar // 8
        pc = chord(sym)[0]
        root = deg_note(pc, 0)
        if root > midi("A2"):
            root -= 12
        # low riff (scale degrees from chord root)
        if sect != 2:
            steps = [0, 0, 0, 2, 1, 0, -1, -3]
            times = [0, 0.75, 1.5, 2, 2.5, 2.75, 3, 3.5]
            durs = [0.5, 0.25, 0.5, 0.45, 0.25, 0.25, 0.45, 0.45]
            for st, t, d in zip(steps, times, durs):
                n = deg_note(pc, st)
                while n > root + 7:
                    n -= 12
                while n < root - 7:
                    n += 12
                if sym == "A" and n % 12 == midi("C2") % 12:
                    n += 1  # C# leading tone on the dominant
                v = 110 if t == 0 else 92
                s.note(0, b + t, d, n + 12, v)
                s.note(1, b + t, d, n, v - 6)
        else:
            s.note(1, b, 3.9, root, 90)
        # staccato strings 8ths / tremolo in the break
        tones = chord_notes(sym, 62)
        if sect != 2:
            for i in range(8):
                for n in tones[:3]:
                    s.note(2, b + i * 0.5, 0.2, n, 86 if i % 2 == 0 else 70)
        else:
            for n in tones[:3]:
                s.note(7, b, 3.95, n, 80)
        # choir
        if sect >= 2:
            for n in chord_notes(sym, 60)[:3]:
                s.note(5, b, 3.95, n, 70 if sect == 2 else 76)
        # orchestra hits
        if sect in (1, 3) and bar % 2 == 0:
            for n in chord_notes(sym, 60)[:3]:
                s.note(6, b, 0.5, n, 96)
        if sect in (1, 3) and bar % 8 == 7:
            for n in chord_notes(sym, 60)[:3]:
                s.note(6, b + 3.5, 0.5, n, 108)
        # taiko
        for t in ((0, 2.5) if sect != 2 else (0, 1, 2, 2.75, 3.5)):
            s.note(4, b + t, 0.6, 38, 118 if t == 0 else 100)
        # drums
        if sect != 2:
            s.hit(b, KICK, 112); s.hit(b + 0.75, KICK, 84); s.hit(b + 2, KICK, 106); s.hit(b + 2.5, KICK, 88)
            s.hit(b + 1, SNARE, 108); s.hit(b + 3, SNARE, 112)
            for i in range(16):
                if i % 4 == 2 or (sect == 3 and i % 2 == 1):
                    s.hit(b + i * 0.25, HAT, 70)
            # tribal toms
            for t, k in [(0.5, TOM_L), (1.5, TOM_M), (1.75, TOM_M), (3.5, TOM_L), (3.75, TOM_H)]:
                s.hit(b + t, k, 86)
            if bar % 8 == 0:
                s.hit(b, CRASH, 110)
            if bar % 8 == 7:
                for i in range(8):
                    s.hit(b + 2 + i * 0.25, [TOM_H, TOM_M, TOM_L][i % 3] if i < 6 else SNARE, 96 + i * 3)
        else:
            j = bar - 16
            for i in range(8):
                s.hit(b + i * 0.5, [TOM_L, TOM_L, TOM_M, TOM_L, TOM_H, TOM_L, TOM_M, TOM_M][i], 80 + (j * 3))
            if j in (1, 3, 5):
                # ape calls
                s.hit(b + 2.0, CUICA_O, 110, 0.5); s.hit(b + 2.5, CUICA_M, 100, 0.3); s.hit(b + 2.75, CUICA_O, 112, 0.5)
            if j == 7:
                for i in range(16):
                    s.hit(b + i * 0.25, SNARE, 70 + i * 3)

    theme = [
        "D5/1.5 A4/.5 D5/.5 F5/.5 A5/1",
        "G5/.5 F5/.5 Eb5/.5 F5/.5 D5/2",
        "D5/1 F5/.5 Bb5/1.5 A5/.5 G5/.5",
        "G5/1.5 Eb5/.5 C5/1 G4/1",
        "D5/.5 D5/.5 A5/1 G5/.5 F5/.5 Eb5/1",
        "D5/3 r/1",
        "Eb5/.5 G5/.5 Bb5/1 C6/1 Bb5/.5 G5/.5",
        "A5/1.5 G5/.5 F5/.5 E5/.5 C#5/1",
    ]
    for sec in (8, 24):
        for i, line in enumerate(theme):
            s.mel(3, (sec + i) * 4, line, 104 if sec == 24 else 96, legato=0.85)
            if sec == 24:
                s.mel(7, (sec + i) * 4, line, 80, shift=12)
    return s


# ---------------------------------------------------------- BANANA GROVE
def banana_grove():
    """Hoard: playful calypso bounce. C major, 116 bpm."""
    s = Song(116, 32, swing=0.12, seed=51)
    s.inst(0, 114, vol=96, pan=60, rev=50)           # steel drums lead
    s.inst(1, 12, vol=84, pan=42, rev=40)            # marimba comp
    s.inst(2, 58, vol=100, pan=64, rev=25)           # tuba bass
    s.inst(3, 24, vol=68, pan=88, rev=35)            # nylon guitar
    s.inst(4, 13, vol=84, pan=74, rev=45)            # xylophone lead (B)
    s.inst(5, 75, vol=80, pan=56, rev=65)            # pan flute (A')
    s.inst(9, 0, vol=94, bank=128, rev=30)

    A = ["C", "F", "G", "C", "C", "F", "G", "C"]
    B = ["F", "C", "G", "Am", "F", "C", "D7", "G"]
    form = A + B + A + B
    for bar, sym in enumerate(form):
        b = bar * 4
        tones = chord_notes(sym, 66)
        r = bass_root(sym, 38)
        # tuba oom-pah with walk
        s.note(2, b, 0.6, r, 100)
        s.note(2, b + 1, 0.4, r + 7 if r + 7 < 50 else r - 5, 80)
        s.note(2, b + 2, 0.6, r + 12 if r + 12 < 52 else r, 94)
        s.note(2, b + 3, 0.4, r + 7 if r + 7 < 50 else r - 5, 78)
        s.note(2, b + 3.5, 0.4, r + 4 if chord(sym)[1][1] == 4 else r + 3, 70)
        # marimba calypso strum rhythm
        for t in (0, 0.75, 1.5, 2, 2.75, 3.25):
            for n in tones[:3]:
                s.note(1, b + t, 0.2, n, 70 if t else 82)
        # guitar offbeats
        for t in (0.5, 1.5, 2.5, 3.5):
            for n in chord_notes(sym, 60)[:3]:
                s.note(3, b + t, 0.2, n, 60)
        # drums
        s.hit(b, KICK, 94); s.hit(b + 1.5, KICK, 76); s.hit(b + 2, KICK, 90)
        s.hit(b + 1, STICK, 76); s.hit(b + 3, CLAP, 80)
        for i in range(8):
            s.hit(b + i * 0.5, MARACA, 70 if i % 2 else 58)
        for t in (0, 0.75, 1.5, 2.5, 3.0):
            s.hit(b + t, COWBELL, 58)
        for t, k in [(0.5, BONGO_H), (0.75, BONGO_H), (1.5, BONGO_L), (2.5, BONGO_H), (3.5, BONGO_L), (3.75, BONGO_H)]:
            s.hit(b + t, k, 72)
        if bar % 8 == 7:
            for i, k in enumerate([TIMB_H, TIMB_H, TIMB_L, TIMB_L, TIMB_H, TIMB_L]):
                s.hit(b + 2.5 + i * 0.25, k, 94)
            s.hit(b + 3.5, WHISTLE_S, 70)
        if bar % 8 == 0:
            s.hit(b, CRASH, 76)

    melA = [
        "E5/.5 G5/.5 C6/.75 B5/.25 C6/.5 G5/.5 E5/1",
        "F5/.5 A5/.5 C6/.5 A5/.5 G5/.75 F5/.25 A5/1",
        "G5/.5 B5/.5 D6/.5 B5/.5 A5/.5 G5/.5 F5/.5 D5/.5",
        "E5/1.5 C5/.5 r/.5 G4/.5 A4/.5 B4/.5",
        "C5/.5 E5/.5 G5/.5 C6/.5 E6/.75 D6/.25 C6/1",
        "A5/.5 C6/.5 A5/.5 F5/.5 C6/.5 D6/.5 C6/1",
        "B5/.75 A5/.25 G5/.5 F5/.5 D5/.5 E5/.5 F5/.5 B4/.5",
        "C5/2 r/1 G4/.5 G4/.5",
    ]
    melB = [
        "A5/1 C6/.5 A5/.5 G5/.5 F5/.5 A5/1",
        "G5/1.5 E5/.5 C5/1 E5/1",
        "D5/.5 G5/.5 B5/.5 D6/.5 C6/.5 B5/.5 G5/1",
        "A5/1.5 E5/.5 C5/.5 E5/.5 A5/1",
        "C6/.5 A5/.5 F5/.5 A5/.5 C6/.5 D6/.5 C6/1",
        "E6/.5 D6/.5 C6/.5 G5/.5 E5/1 G5/1",
        "F#5/.5 A5/.5 C6/.5 A5/.5 F#5/.5 D5/.5 E5/.5 F#5/.5",
        "G5/1 B5/.5 D6/.5 B5/.5 G5/.5 F5/1",
    ]
    for sec, mel, ch, v in [(0, melA, 0, 96), (8, melB, 4, 92), (16, melA, 5, 88), (24, melB, 0, 98)]:
        for i, line in enumerate(mel):
            s.mel(ch, (sec + i) * 4, line, v, legato=0.8 if ch != 5 else 0.95)
            if sec == 16:
                s.mel(0, (sec + i) * 4, line, 64, shift=-12, legato=0.6)
            if sec == 24:
                s.mel(4, (sec + i) * 4, line, 62, shift=12, legato=0.5)
    return s


SONGS = {
    "lobby": (lobby, -17.0),
    "jungle_run": (jungle_run, -14.5),
    "canopy_climb": (canopy_climb, -14.5),
    "slap_island": (slap_island, -14.0),
    "banana_grove": (banana_grove, -15.0),
}

if __name__ == "__main__":
    import os
    os.makedirs(OUT, exist_ok=True)
    names = sys.argv[1:] or list(SONGS)
    for n in names:
        fn, lufs = SONGS[n]
        secs = render(fn(), OUT + "music_" + n, lufs=lufs)
        print(f"{n}: {secs:.1f}s")
