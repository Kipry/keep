# Vertont keep-urlaub-24s.mp4: nur Geräusche, keine Musik.
#
#   python3 sound.py      → keep-urlaub-sfx.wav und keep-urlaub-24s-ton.mp4
#
# Alles wird hier synthetisiert, es gibt keine fremden Samples und damit keine
# Lizenzfragen. Die Zeitpunkte stammen aus keep-urlaub.html. Wird dort das
# Timing geändert, muss es hier nachgezogen werden.
# Braucht numpy und scipy. ffmpeg kommt aus FFMPEG oder dem Pfad.
import os, subprocess, wave
import numpy as np
from scipy.signal import butter, sosfilt

SR, DUR = 48000, 24.0
N = int(SR * DUR)
out = np.zeros((2, N))
rng = np.random.default_rng(7)
HERE = os.path.dirname(os.path.abspath(__file__))

# ─── Bausteine ──────────────────────────────────────────────────────────────
def tt(d): return np.arange(int(SR * d)) / SR
def noise(d): return rng.standard_normal(int(SR * d))
def bp(x, lo, hi, o=2): return sosfilt(butter(o, [lo, hi], 'band', fs=SR, output='sos'), x)
def lp(x, f, o=2): return sosfilt(butter(o, f, 'low', fs=SR, output='sos'), x)
def hp(x, f, o=2): return sosfilt(butter(o, f, 'high', fs=SR, output='sos'), x)
def env(n, a, r):
    """Attack in Sekunden, dann exponentielles Abklingen mit Zeitkonstante r."""
    t = np.arange(n) / SR
    return np.minimum(1, t / max(a, 1e-4)) * np.exp(-np.maximum(0, t - a) / r)
def fade(x, a=.01, b=.01):
    n = len(x); e = np.ones(n)
    ia, ib = min(n, int(a * SR)), min(n, int(b * SR))
    if ia: e[:ia] = np.linspace(0, 1, ia)
    if ib: e[n - ib:] *= np.linspace(1, 0, ib)
    return x * e
def sweep(f0, f1, d, curve=1.0):
    t = tt(d); u = (t / d) ** curve
    return np.sin(2 * np.pi * np.cumsum(f0 + (f1 - f0) * u) / SR)
def norm(x): return x / (np.max(np.abs(x)) + 1e-9)

def put(x, at, gain=1.0, pan=0.0):
    """Mischt x bei Sekunde `at` ein. pan −1 = links, +1 = rechts."""
    i = int(at * SR)
    if i >= N: return
    x = x[:N - i]
    l, r = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
    out[0, i:i + len(x)] += x * gain * l * 1.414
    out[1, i:i + len(x)] += x * gain * r * 1.414

def span(x, a, b, gain=1.0, pan=0.0, fin=.3, fout=.3):
    put(fade(x[:int((b - a) * SR)], fin, fout), a, gain, pan)

# ─── Geräusche ──────────────────────────────────────────────────────────────
def waves(d, seed=0):
    """Meeresrauschen: rosa-ähnliches Rauschen, langsam an- und abschwellend."""
    x = lp(noise(d), 900) + .5 * bp(noise(d), 900, 3000)
    t = tt(d)
    swell = .55 + .45 * np.sin(2 * np.pi * (t / 5.5) + seed) ** 2
    return norm(x * swell)

def chirp_bird(n=4, base=3800):
    s = []
    for i in range(n):
        f = base * (1 + .15 * rng.random())
        c = sweep(f, f * (1.35 + .2 * rng.random()), .055, .6) * env(int(.055 * SR), .004, .02)
        s.append(np.concatenate([c, np.zeros(int(.045 * SR))]))
    return np.concatenate(s)

def pop(f0=700, f1=260, d=.09):
    return sweep(f0, f1, d, .5) * env(int(d * SR), .002, .025)

def tap():
    x = hp(noise(.03), 1800) * env(int(.03 * SR), .0005, .004)
    return x + .6 * sweep(1300, 900, .03) * env(int(.03 * SR), .0005, .008)

def whoosh(d, f0, f1, peak=.6):
    x = noise(d); t = tt(d); fc = f0 * (f1 / f0) ** (t / d)
    # Sweep durch blockweise Bandpässe
    y = np.zeros_like(x); blk = 1024
    for i in range(0, len(x), blk):
        c = fc[min(i + blk // 2, len(fc) - 1)]
        y[i:i + blk] = bp(x[max(0, i - 2048):i + blk], c * .7, min(c * 1.4, 20000))[-len(x[i:i + blk]):]
    e = np.where(t < d * peak, (t / (d * peak)) ** 2, ((d - t) / (d * (1 - peak))) ** 1.5)
    return norm(y * e)

def scribble(d, rate=11):
    """Filzstift auf Papier: raues Band-Rauschen mit schnellen Strich-Pulsen."""
    t = tt(d)
    strokes = .35 + .65 * np.abs(np.sin(np.pi * rate * t + 2 * np.sin(np.pi * 3.1 * t))) ** 1.5
    return norm(bp(noise(d), 1800, 7000) * strokes)

def rec_start():
    a = np.sin(2 * np.pi * 1320 * tt(.07)) * env(int(.07 * SR), .002, .03)
    b = np.sin(2 * np.pi * 1760 * tt(.09)) * env(int(.09 * SR), .002, .04)
    return np.concatenate([a, np.zeros(int(.03 * SR)), b])

def rec_stop():
    a = np.sin(2 * np.pi * 1760 * tt(.07)) * env(int(.07 * SR), .002, .03)
    b = np.sin(2 * np.pi * 1320 * tt(.09)) * env(int(.09 * SR), .002, .04)
    return np.concatenate([a, np.zeros(int(.03 * SR)), b])

def step():
    x = lp(noise(.08), 1400) * env(int(.08 * SR), .001, .018)
    return x + .8 * np.sin(2 * np.pi * 95 * tt(.08)) * env(int(.08 * SR), .001, .02)

def droplet(f=None, d=.07):
    """Klassischer Wassertropfen: Sinus mit schnell steigender Tonhöhe."""
    f = f or 900 + 1500 * rng.random()
    return sweep(f, f * 2.4, d, 2.2) * env(int(d * SR), .001, .018)

def splash():
    d = 2.6; t = tt(d)
    body = lp(noise(d), 5200) * env(len(t), .006, .22)
    thump = np.sin(2 * np.pi * np.cumsum(120 * np.exp(-t * 9) + 45) / SR) * env(len(t), .002, .12)
    crash = bp(noise(d), 1500, 9000) * env(len(t), .003, .09)
    x = .9 * body + 1.2 * thump + .6 * crash
    # herabfallendes Wasser: viele Tropfen, dichter am Anfang
    for _ in range(160):
        at = .15 + 2.1 * rng.random() ** 1.8
        dr = droplet(); i = int(at * SR)
        x[i:i + len(dr)] += dr[:len(x) - i] * (.25 + .35 * rng.random()) * np.exp(-at * .9)
    return norm(x)

def lens_hit():
    """Tropfen klatscht auf die Linse: dumpf und nah."""
    d = .14; t = tt(d)
    x = lp(noise(d), 2200) * env(len(t), .001, .02)
    dr = droplet(600 + 400 * rng.random(), .09)
    x[:len(dr)] += .7 * dr
    return norm(x)

def bubbles(d, n=40):
    x = np.zeros(int(d * SR))
    for _ in range(n):
        i = int(rng.random() * (len(x) - SR * .1)); dr = droplet(500 + 900 * rng.random(), .06)
        x[i:i + len(dr)] += dr * (.3 + .5 * rng.random())
    return x

def clink():
    """Gläser stoßen an: unharmonische Teiltöne, zwei Anschläge knapp nacheinander."""
    d = 1.4; t = tt(d); x = np.zeros(len(t))
    for off, g in [(0, 1), (.018, .7), (.041, .5)]:
        i = int(off * SR)
        for f, a, r in [(2350, 1, .45), (3710, .6, .3), (5480, .45, .2), (6890, .3, .14), (1480, .25, .5)]:
            f *= 1 + .01 * (rng.random() - .5)
            x[i:] += g * a * np.sin(2 * np.pi * f * t[:len(t) - i]) * env(len(t) - i, .0008, r)
    return norm(x)

def murmur(d):
    """Gedämpftes Stimmengewirr am Nebentisch: formantartig gefiltertes Rauschen."""
    t = tt(d); x = np.zeros(len(t))
    for lo, hi, rate in [(250, 700, 3.1), (600, 1400, 4.3), (1200, 2600, 5.7)]:
        am = .5 + .5 * np.sin(2 * np.pi * rate * t + 6 * rng.random()) * np.sin(2 * np.pi * rate * .37 * t)
        x += bp(noise(d), lo, hi) * am
    return norm(x)

def crickets(d):
    t = tt(d)
    chirp = (np.sin(2 * np.pi * 30 * t) > .2) * (np.sin(2 * np.pi * 1.6 * t) > .1)
    return norm(np.sin(2 * np.pi * 4300 * t) * lp(chirp.astype(float), 300))

def launch(d=.4):
    """Rakete steigt: zischen plus pfeifender Ton."""
    t = tt(d)
    hiss = bp(noise(d), 2500, 9000) * (t / d)
    whistle = sweep(1400, 2600, d, .8) * (.2 + .8 * t / d)
    return norm(hiss + .5 * whistle) * np.minimum(1, (d - t) / .03)

def boom():
    d = 2.2; t = tt(d)
    low = lp(noise(d), 300, 3) * env(len(t), .004, .35)
    body = lp(noise(d), 1800) * env(len(t), .002, .12)
    x = 2.2 * low + body
    for _ in range(90):   # Knistern der Funken
        at = .15 + 1.6 * rng.random(); i = int(at * SR); c = hp(noise(.006), 3000) * env(int(.006 * SR), .0003, .0015)
        x[i:i + len(c)] += c * (.4 + rng.random()) * np.exp(-at * 1.3)
    return norm(x)

def drop_fall(d=.26):
    """Amber-Tropfen fällt: fallender Pfeifton."""
    return sweep(1600, 500, d, 1.4) * np.minimum(1, tt(d) / .05) * np.minimum(1, (d - tt(d)) / .02)

def blop():
    """Tropfen schlägt auf: tiefes, rundes Blubb."""
    d = .35; t = tt(d)
    return sweep(180, 520, d, .35) * env(len(t), .002, .08) + .5 * lp(noise(d), 600) * env(len(t), .001, .03)

def sparkle(f):
    d = .5; t = tt(d)
    return (np.sin(2 * np.pi * f * t) + .4 * np.sin(2 * np.pi * f * 2.01 * t)) * env(len(t), .002, .12)

def projector(d):
    """Filmprojektor-Rattern, sehr leise unter dem Filmstreifen."""
    t = tt(d); clicks = (np.sin(2 * np.pi * 24 * t) > .92).astype(float)
    return norm(bp(clicks, 800, 5000) + .15 * lp(noise(d), 200))

def chime():
    """Endkarte: warmer, einzelner Glockenton."""
    d = 2.2; t = tt(d); x = np.zeros(len(t))
    for f, a, r in [(660, 1, .9), (1320, .35, .6), (1985, .2, .4), (990, .25, .7)]:
        x += a * np.sin(2 * np.pi * f * t) * env(len(t), .004, r)
    return norm(x)

# ─── Mischung entlang der Zeitleiste von keep-urlaub.html ───────────────────
# Durchgehend leise Brandung, damit zwischen den Ereignissen nie Totenstille ist
span(lp(waves(DUR, 4.0), 700), 0, DUR, .06, 0, .6, 1.0)

# Tag an der Küste: Meer, Vögel
span(waves(9.4), 0, 9.4, .12, 0, .4, .5)
for at, pan in [(.6, -.5), (1.9, .6), (5.0, .3)]: put(chirp_bird(3 + int(rng.random() * 2)), at, .05, pan)

# 3,0 Übergang zum Handy
put(whoosh(.45, 400, 2200), 2.9, .14)
# 3,3–4,0 Handschrift und Pfeil
span(scribble(.35, 14), 3.3, 3.62, .09, -.4, .02, .05)
span(scribble(.35, 14), 3.42, 3.72, .08, -.3, .02, .05)
span(scribble(.6, 9), 3.45, 4.0, .1, .1, .03, .08)
# 4,42 Tipp auf den keep.-Knopf
put(tap(), 4.42, .45, .2)
put(pop(900, 500, .07), 4.44, .12, .2)
# 4,6–6,0 Kamera öffnet, Zoom ins Handy
put(whoosh(.7, 300, 1400), 4.65, .1)
put(whoosh(.7, 200, 3000, .85), 5.3, .2)
put(tap(), 6.0, .25)

# 6,0 Anlauf: Schritte im Takt der Animation (|sin 13t| = 0)
for k in range(33, 38):
    at = k * np.pi / 13
    if 6.0 <= at < 6.95: put(step(), at, .3, -.2 + (at - 6) * .3)
put(step(), 6.93, .4)                          # Absprung
put(rec_start(), 6.95, .22)                    # Aufnahme 1,618 s
put(whoosh(.6, 500, 1500, .4), 7.0, .08)       # Flug
put(splash(), 7.6, .95)                        # Arschbombe
for i, (at, x) in enumerate([(7.78, 250), (7.84, 820), (7.9, 430), (7.95, 900), (8.0, 200), (8.03, 640), (8.08, 560), (8.12, 780)]):
    put(lens_hit(), at + .2, .35, (x - 540) / 540)
put(rec_stop(), 6.95 + 1.618, .2)

# 8,55–9,35 Wasserschwall wischt
put(whoosh(.8, 250, 1600, .45), 8.5, .45)
put(bubbles(.8, 30), 8.55, .12)
put(lp(noise(.8), 1200) * env(int(.8 * SR), .15, .25), 8.5, .25)

# 9,35–11,45 Abendessen
span(murmur(2.3), 9.3, 11.5, .07, 0, .25, .3)
span(waves(2.3, 1.3), 9.3, 11.5, .06, 0, .3, .3)
put(rec_start(), 9.55, .2)
put(clink(), 10.17, .55)
put(pop(700, 330, .08), 10.17, .1, .4)         # „Prost!"-Blase
put(rec_stop(), 9.55 + 1.618, .2)

# 11,0 Amber-Tropfen
put(drop_fall(), 11.0, .12)
put(blop(), 11.24, .5)
put(whoosh(.45, 300, 900, .3), 11.26, .15)

# 11,7–13,65 Feuerwerk
span(crickets(2.2), 11.5, 13.7, .03, 0, .3, .3)
span(waves(2.2, 2.1), 11.5, 13.7, .06, 0, .3, .3)
put(rec_start(), 11.85, .2)
for bt, x in [(11.8, 380), (12.2, 720), (12.6, 540)]:
    pan = (x - 540) / 540 * .8
    put(launch(.35), bt - .35, .12, pan)
    put(boom(), bt, .6, pan)
put(rec_stop(), 11.85 + 1.618, .2)

# 13,2 Tropfen zurück in die Creme-Fläche
put(drop_fall(), 13.2, .12)
put(blop(), 13.44, .5)
put(whoosh(.45, 300, 900, .3), 13.46, .15)

# 13,9–17,1 Filmstreifen, Pfeil, Clips werden zum Film
put(whoosh(.8, 300, 1200, .6), 13.85, .2, .5)
span(projector(1.5), 14.0, 15.4, .05, 0, .3, .3)
span(scribble(.45, 10), 15.2, 15.6, .1, .6, .03, .08)
for i in range(4): put(pop(500 + 90 * i, 250, .08), 15.4 + i * .1, .12, -.4 + .27 * i)
put(pop(420, 180, .13), 15.6, .25)             # Player erscheint
put(tap(), 16.08, .4)                          # Play
span(projector(1.2), 16.2, 17.2, .07, 0, .1, .3)

# 17,15 Markerstrich übermalt das Bild und gibt es frei
span(scribble(.35, 6), 17.15, 17.48, .22, 0, .02, .06)
span(scribble(.35, 6), 17.51, 17.85, .18, 0, .02, .08)

# 17,85–21,45 Die Freunde staunen
span(murmur(3.8), 17.7, 21.5, .045, 0, .4, .4)
for i, at in enumerate([18.1, 19.6, 20.4]): put(chirp_bird(2), at, .03, [-.7, .6, -.2][i])
for i in range(12):
    at = 18.7 + i * .16
    put(sparkle([1568, 1760, 2093, 2349][i % 4] * (1 if i % 3 else .75)), at, .05, [-.8, -.4, .4, .8][i % 4])
put(pop(650, 300, .1), 19.15, .2, .3)          # Sprechblase
put(whoosh(.4, 600, 1800, .7), 18.4, .06)      # Augen werden groß

# 21,45 Tropfen zur Endkarte
put(drop_fall(), 21.45, .12)
put(blop(), 21.69, .5)
put(whoosh(.45, 300, 900, .3), 21.71, .15)
put(chime(), 22.12, .22)                       # keep.

# ─── Master: leichtes Hochpass, weiche Begrenzung, Ausblenden ─────────────────
out = hp(out, 35)
out = np.tanh(out * 1.6) / np.tanh(1.6)
out /= max(1e-9, np.max(np.abs(out))) / .89
out[:, -int(.8 * SR):] *= np.linspace(1, 0, int(.8 * SR))

wav = os.path.join(HERE, 'keep-urlaub-sfx.wav')
with wave.open(wav, 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((out.T * 32767).astype('<i2').tobytes())

video, final = os.path.join(HERE, 'keep-urlaub-24s.mp4'), os.path.join(HERE, 'keep-urlaub-24s-ton.mp4')
subprocess.run([os.environ.get('FFMPEG', 'ffmpeg'), '-y', '-loglevel', 'error', '-i', video, '-i', wav,
                '-map', '0:v', '-map', '1:a', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k', '-shortest',
                '-movflags', '+faststart', final], check=True)
print(final)
