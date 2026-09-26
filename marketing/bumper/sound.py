# Sound-Logo für den Signature-Clip, synthetisiert, ohne fremde Samples.
#
#   python3 sound.py
#     → bumper-ton.wav
#     → ../../Keep/Resources/Videos/BumperIntro.mp4   (bumper-video.mp4 + Ton)
#     → vorschau-hoch.mp4 / vorschau-quer.mp4 bekommen denselben Ton, falls vorhanden
#
# Zeitpunkte wie in keep-bumper.html. Pegel bewusst unter den Clips: die App
# gleicht Clips auf −20 dBFS RMS an (AudioLoudness.targetRMS), das Logo liegt
# bei etwa −26 dBFS, damit es den Film einleitet und nicht übertönt.
import os, shutil, subprocess, wave
import numpy as np
from scipy.signal import butter, sosfilt

# Etwas kürzer als das Bild (2,5 s): AAC hängt beim Kodieren ein paar Millisekunden
# an, und eine Tonspur, die länger ist als das Bild, verlängert den Clip in der App.
SR, DUR = 48000, 2.47
N = int(SR * DUR)
out = np.zeros((2, N))
rng = np.random.default_rng(3)
HERE = os.path.dirname(os.path.abspath(__file__))
FF = os.environ.get('FFMPEG', 'ffmpeg')

def tt(d): return np.arange(int(SR * d)) / SR
def noise(d): return rng.standard_normal(int(SR * d))
def bp(x, lo, hi): return sosfilt(butter(2, [lo, hi], 'band', fs=SR, output='sos'), x)
def lp(x, f): return sosfilt(butter(2, f, 'low', fs=SR, output='sos'), x)
def hp(x, f): return sosfilt(butter(2, f, 'high', fs=SR, output='sos'), x)
def env(n, a, r):
    t = np.arange(n) / SR
    return np.minimum(1, t / max(a, 1e-4)) * np.exp(-np.maximum(0, t - a) / r)
def sweep(f0, f1, d, curve=1.0):
    t = tt(d); u = (t / d) ** curve
    return np.sin(2 * np.pi * np.cumsum(f0 + (f1 - f0) * u) / SR)
def put(x, at, gain=1.0, pan=0.0):
    i = int(at * SR); x = x[:N - i]
    l, r = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
    out[0, i:i + len(x)] += x * gain * l * 1.414
    out[1, i:i + len(x)] += x * gain * r * 1.414

def bell(f, d, r):
    """Weicher Glockenton: Grundton plus leise, leicht unharmonische Obertöne."""
    t = tt(d); x = np.zeros(len(t))
    for m, a, rr in [(1, 1, r), (2.0, .28, r * .55), (3.01, .12, r * .35), (4.2, .05, r * .2)]:
        x += a * np.sin(2 * np.pi * f * m * t) * env(len(t), .003, rr)
    return x

# 0,02  Punkt erscheint: kurzer, runder Tupfer mit etwas Tiefe
put(sweep(820, 480, .09, .5) * env(int(.09 * SR), .002, .025), .02, .35)
put(np.sin(2 * np.pi * 110 * tt(.45)) * env(int(.45 * SR), .004, .07), .02, .3)

# 0,30–0,95  Ring läuft: leise ansteigender Hauch, der auf den Klick zuläuft
d = .65; t = tt(d)
rise = (t / d) ** 2.2
breath = bp(noise(d), 700, 3200) * rise
tone = sweep(330, 660, d, 1.6) * rise * .5
put((breath * .5 + tone) * np.minimum(1, (d - t) / .015), .3, .09)

# 0,95  Klick: zwei kurze Verschluss-Klicks, ein weicher Tiefton und ein Akkord
for off, g in [(0, 1), (.028, .6)]:
    c = hp(noise(.012), 2500) * env(int(.012 * SR), .0004, .0025)
    put(c, .95 + off, .5 * g)
put(np.sin(2 * np.pi * np.cumsum(90 * np.exp(-tt(.3) * 10) + 55) / SR) * env(int(.3 * SR), .002, .08), .95, .45)
for f, g, pan, dl in [(440, 1, 0, 0), (659.3, .7, -.25, .012), (880, .45, .25, .024)]:
    put(bell(f, 1.5, .55), .95 + dl, .2 * g, pan)

# 0,98–1,32  Linse rückt an ihren Platz: leiser Luftzug von links nach rechts
d = .4; t = tt(d)
wh = bp(noise(d), 900, 4000) * np.sin(np.pi * t / d) ** 2
for i, pan in enumerate(np.linspace(-.3, .5, 4)):
    seg = wh[i * len(wh) // 4:(i + 1) * len(wh) // 4]
    put(seg, .98 + i * d / 4, .05, pan)

# 1,1–1,4  „keep“ steigt auf: vier sehr leise Töne, aufsteigend, je Buchstabe
for i, f in enumerate([1318.5, 1568, 1760, 2093]):
    put(bell(f, .4, .09), 1.2 + i * .055, .045, -.35 + .23 * i)

# Master: weich begrenzen, auf Ziel-Pegel, sauber ausblenden
out = hp(out, 40)
out = np.tanh(out * 1.3) / np.tanh(1.3)
rms = np.sqrt(np.mean(out[:, :int(1.8 * SR)] ** 2))
out *= 10 ** (-26 / 20) / rms
peak = np.max(np.abs(out))
if peak > 10 ** (-6 / 20): out *= 10 ** (-6 / 20) / peak
out[:, -int(.35 * SR):] *= np.linspace(1, 0, int(.35 * SR)) ** 2
print(f'RMS {20 * np.log10(np.sqrt(np.mean(out ** 2))):.1f} dBFS, Spitze {20 * np.log10(np.max(np.abs(out))):.1f} dBFS')

wav = os.path.join(HERE, 'bumper-ton.wav')
with wave.open(wav, 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((out.T * 32767).astype('<i2').tobytes())

def mux(video, dest):
    tmp = dest + '.tmp.mp4'
    subprocess.run([FF, '-y', '-loglevel', 'error', '-i', video, '-i', wav, '-map', '0:v', '-map', '1:a',
                    '-c:v', 'copy', '-c:a', 'aac', '-b:a', '160k', '-movflags', '+faststart', tmp], check=True)
    shutil.move(tmp, dest)
    print(dest)

mux(os.path.join(HERE, 'bumper-video.mp4'), os.path.normpath(os.path.join(HERE, '../../Keep/Resources/Videos/BumperIntro.mp4')))
for name in ['vorschau-hoch.mp4', 'vorschau-quer.mp4']:
    p = os.path.join(HERE, name)
    if os.path.exists(p): mux(p, p)
