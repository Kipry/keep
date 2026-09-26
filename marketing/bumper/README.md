# keep. — Signature-Clip vor dem Export

Läuft vor jedem exportierten Film: 2,5 s, 30 fps, dunkel wie der Ladescreen,
mit einem leisen Sound-Logo. Die fertige Datei liegt im App-Bundle als
`Keep/Resources/Videos/BumperIntro.mp4` (2160 × 3840, H.264 + AAC).

## Ablauf

| Zeit | Bild | Ton |
|---|---|---|
| 0,00–0,30 s | Der Amber-Punkt erscheint, darum die Linse, groß in der Bildmitte. | runder Tupfer mit etwas Tiefe |
| 0,30–0,95 s | Der Aufnahmering läuft einmal voll, gleichmäßig wie in der App. Der Punkt pulsiert wie bei REC. | ansteigender Hauch |
| 0,95 s | Klick: Das Glühen blüht auf, eine Druckwelle läuft nach außen. | Verschluss-Klick, weicher Tiefton, Akkord A–E–A |
| 0,98–1,32 s | Die Linse rückt an ihren Platz im Logo. | leiser Luftzug |
| 1,10–1,63 s | Dahinter steigt „keep“ Buchstabe für Buchstabe auf. | vier sehr leise, aufsteigende Töne |
| 1,28–1,68 s | Die Unterstreichung zieht sich durch. Das Endbild ist das Logo des Ladescreens, gleiche Maße, gleiche Farben. | Ausklang |
| 1,65–2,00 s | Die App blendet Projektname und Zeitraum unten links ein. | — |
| bis 2,50 s | stehen lassen, harter Schnitt in den Film | ausgeblendet |

## Was die App dazutut

`VideoComposer.renderBumper` brennt Projektname und Zeitraum ein. Das passiert
auf der Leinwand des Exports: Ein Querformat-Film bekommt eine Titelkarte im
Querformat, der Clip wird dabei auf sein mittleres Band beschnitten. Dort
liegt alles Wichtige der Animation. Der Titel blendet ab 1,65 s ein
(`titleFadeInStart`). Wird das Timing hier geändert, muss der Wert dort mit.

Pegel: Die App gleicht Clips auf −20 dBFS RMS an, das Sound-Logo liegt bei
etwa −27 dBFS (Spitze −9 dBFS), also bewusst darunter.

## Neu rendern

```
cd marketing/bumper
npm i && pip install numpy scipy
node render.mjs                   # bumper-video.mp4, 2160×3840, ohne Ton
node render.mjs --preview         # vorschau-hoch.mp4 mit Beispieltitel
node render.mjs --preview --wide  # vorschau-quer.mp4, Ausschnitt im Querformat
python3 sound.py                  # Ton dazu → Keep/Resources/Videos/BumperIntro.mp4
```
