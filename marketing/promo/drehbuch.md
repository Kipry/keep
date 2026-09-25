# keep. — Werbeclip 20 s · Drehbuch

**Format:** 1080 × 1920 (Hochformat, 9:16), 30 fps, ohne Ton.
**Gedacht für:** Instagram/TikTok Reels, Stories, Website.
**Nicht für:** App-Store-Vorschauvideos — Apple verlangt dort echte Bildschirmaufnahmen der App, keine animierten Nachbauten.

## Die Idee

Der Clip erzählt das Versprechen der App in der Reihenfolge, in der man es erlebt:
ein Moment, der gleich vorbei ist → ein Tipp, ohne zu entsperren → der Clip ist gesichert,
man ist wieder im Moment → aus vielen Tagen wird ein Film.

Jede Zeile beschreibt etwas, das die App wirklich tut. Wo es schon eine
abgesegnete Formulierung gab — Store-Screenshot, Onboarding —, wird sie
wortgleich übernommen, damit Werbung, Store und App dieselbe Sprache sprechen.

Die Endkarte ist der Ladescreen der App. Der Clip hört also genau dort auf, wo die App anfängt.

## Ablauf

| Zeit | Bild | Text |
|---|---|---|
| **0,0 – 2,6 s** | Schwarz. Ein warmes Licht glimmt auf, Wort für Wort erscheint eine Zeile. | **Der Moment ist gleich vorbei.** |
| **2,6 – 4,2 s** | Ein iPhone gleitet von unten ins Bild: Sperrbildschirm, 23:07. Unten rechts der keep.-Aufnahmeknopf. Ein Finger tippt darauf. | *SPERRBILDSCHIRM* — **Ein Tipp. Ohne Entsperren.** |
| **4,2 – 7,2 s** | Der Sucher öffnet sich direkt, kein Face ID. Der Ring um den Auslöser läuft in 1,6 Sekunden voll, oben zählt die Zeit mit. Dann: „Clip gesichert". | *AUFNEHMEN* — **Schneller als der Moment vorbei ist.** |
| **7,2 – 9,8 s** | Das Handy gleitet nach unten weg. Die Szene bleibt und füllt den Bildschirm: der Moment geht weiter. | **Halte ihn fest, ohne ihn zu verpassen.** |
| **9,8 – 14,6 s** | Ein Filmstreifen füllt sich Clip für Clip, immer schneller. Oben zählen die Tage hoch bis 212. | *TAG 1 … TAG 212* — **Jeden Tag ein Clip.** |
| **14,6 – 17,4 s** | Alle Clips ziehen sich in einen einzigen Filmrahmen zusammen. Ein Tipp auf Play, der Film läuft als Schnellmontage. Darunter: 212 CLIPS → 1 VIDEO. | *EXPORT* — **Clips rein. Film raus.** |
| **17,4 – 20,0 s** | Endkarte: der Ladescreen — keep., der Aufnahmepunkt, THE MOMENT. | *Jetzt im App Store* |

## Woher die Zeilen kommen

| Zeile | Quelle | Stimmt, weil |
|---|---|---|
| Ein Tipp. Ohne Entsperren. | Neu | Aufnahme über das Sperrbildschirm-Steuerelement, ohne Face ID |
| Schneller als der Moment vorbei ist. | Store-Screenshot | — |
| Halte ihn fest, ohne ihn zu verpassen. | Onboarding, Folie 3 | — |
| Jeden Tag ein Clip. | Neu | Tagebuch-Prinzip der App |
| Clips rein. Film raus. | Onboarding, Folie 6 | Export setzt alle Clips eines Projekts zu einem Film zusammen |
| 1,6 Sekunden | — | Voreingestellte Cliplänge (φ ≈ 1,618 s) |

## Bewusst nicht drin

- **Keine echten Menschen, keine echten Aufnahmen.** Die „Fotos" sind gezeichnete Motive im Stil des Onboardings. Keine Rechtefragen, und niemandes privates Material in einer Werbung.
- **Keine Musik.** Die kommt am besten beim Posten dazu, aus der Bibliothek der jeweiligen Plattform — dort ist sie für diesen Zweck lizenziert.
- **Kein App-Store-Badge.** Apples Badge hat eigene Nutzungsregeln und muss aus Apples offizieller Quelle kommen; der Text „Jetzt im App Store" ist die sichere Variante.

## Neu rendern

Die Animation ist eine HTML-Datei (`keep-promo.html`) mit einer Funktion `render(t)`, die jeden Zeitpunkt deterministisch zeichnet.
`render.mjs` fährt sie Bild für Bild durch Chromium und schreibt das MP4:

```
cd marketing/promo
npm i playwright
node render.mjs          # schreibt keep-promo-20s.mp4
```

Braucht ein `ffmpeg` im Pfad (oder `FFMPEG=/pfad/zu/ffmpeg`). Texte, Farben und Timing stehen oben in der HTML-Datei.
