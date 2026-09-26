# keep. — Signature-Clip vor dem Export

Läuft vor jedem exportierten Film: 2,5 s, 30 fps, dunkel wie der Ladescreen,
mit einem leisen Sound-Logo. Es gibt zwei Fassungen im App-Bundle, beide
H.264 + AAC:

- `Keep/Resources/Videos/BumperIntro.mp4`: hochkant, 2160 × 3840
- `Keep/Resources/Videos/BumperIntroWide.mp4`: quer, 3840 × 2160

Die App nimmt die Fassung, die zum ersten Clip des Projekts passt.

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

`VideoComposer.renderBumper` liest am ersten Clip des Projekts ab, ob er
hochkant oder quer aufgenommen wurde: Bildgröße samt Drehung, genau wie der
Export selbst. Danach wählt es die Fassung und brennt Projektname und Zeitraum
(erster bis letzter Clip) auf der Leinwand des Exports ein. In den Videos
steht also kein Titel, nur in den Vorschauen. Der Titel blendet ab 1,65 s ein
(`titleFadeInStart`). Wird das Timing hier geändert, muss der Wert dort mit.

Pegel: Die App gleicht Clips auf −20 dBFS RMS an, das Sound-Logo liegt bei
etwa −27 dBFS (Spitze −9 dBFS), also bewusst darunter.

## Neu rendern

```
cd marketing/bumper
npm i && pip install numpy scipy
node render.mjs                   # bumper-video.mp4, 2160×3840, ohne Ton
node render.mjs --wide            # bumper-video-quer.mp4, 3840×2160, ohne Ton
node render.mjs --preview         # vorschau-hoch.mp4 mit Beispieltitel
node render.mjs --preview --wide  # vorschau-quer.mp4 mit Beispieltitel
python3 sound.py                  # Ton dazu → Keep/Resources/Videos/BumperIntro(Wide).mp4
```
