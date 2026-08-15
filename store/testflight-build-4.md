# TestFlight — Build 1.0 (4)

Letzter geplanter TestFlight-Build vor der echten App-Store-Einreichung.

## „Was soll getestet werden?" (What to Test)

Zum Kopieren in App Store Connect → TestFlight → Build 1.0 (4):

```
NEU IN DIESEM BUILD — letzter Test vor dem echten Store-Release!

Behoben
• Der Hinweis „Richte dein Widget ein" in der Bibliothek ließ sich nicht
  wegtippen – das x öffnete stattdessen die Anleitung, und die Meldung
  blieb einfach stehen.
• Wurde der Clip gelöscht, der als Projekt-Cover diente, blieb sein Bild
  trotzdem als Vorschau stehen (besonders sichtbar bei Projekten mit nur
  einem Clip).
• Projekt-Cover aus importierten breiten/querformatigen Bildern oder
  Videos sahen verzerrt bzw. falsch zugeschnitten aus. Cover werden jetzt
  immer im selben festen Format zugeschnitten – bestehende, betroffene
  Cover reparieren sich beim ersten Start dieses Builds automatisch.
• Rand-Wischgesten (Tab wechseln, im Projekt zurück) reagierten oft gar
  nicht, wenn man nicht exakt am Bildschirmrand ansetzte.
• Der Zurück-Wisch aus einem Projekt sah abgehackt aus – die Seite
  wechselte mitten in der Animation unvermittelt die Richtung.
• Der Scrollbalken im Filmstreifen war wieder sichtbar.
• Die „nächster Clip"-Markierung im Filmstreifen sprang in eine neue
  Zeile, obwohl in der letzten Zeile noch Platz gewesen wäre.
• Ruckeln beim Verschieben von Clips im Filmstreifen und ein kurzes
  Stocken beim Öffnen der Foto-Vorschau bei mehreren Bildern.

Neu
• Einzelne Clips lassen sich jetzt exportieren/teilen – im Kontextmenü
  im Filmstreifen oder über den Teilen-Button in der Vollbildvorschau.
• Komplett neue Typografie: klar lesbare, fette Überschriften statt der
  Handschrift-Schrift, mit dem amber-farbenen Punkt als durchgängigem
  Markenzeichen auf jeder Seite.
• Neuer Launch Screen beim App-Start, neues App-Icon.
• Neues Intro beim Video-Export.

WORAUF ICH BESONDERS SCHAUE

1. Der erste Eindruck: App-Icon, Launch Screen, die neue Schrift auf
   allen Seiten – wirkt das wie aus einem Guss?
2. Rand-Wischgesten: fühlt sich der Tab-Wechsel und der Zurück-Wisch aus
   einem Projekt jetzt zuverlässig an, auch wenn du nicht exakt am
   Rand ansetzt?
3. Ein Projekt mit z. B. 1, 3, 5 und 9 Clips anlegen – landet die
   „nächster Clip"-Markierung immer richtig in der letzten Zeile?
4. Einen einzelnen Clip exportieren – einmal ein Video, einmal ein
   importiertes Foto. Kommt jeweils das Richtige im Teilen-Menü an?
5. Ein Projekt mit einem breiten/importierten Bild als erstem Clip
   anlegen – sieht das Cover in der Bibliothek jetzt richtig aus?

Das ist der letzte geplante Beta-Build – wenn hier nichts Größeres
auffällt, geht's als Nächstes in die echte Store-Prüfung. Alles, was
hakt oder komisch aussieht, gerne über den Feedback-Knopf in den
Einstellungen – der öffnet eine vorbereitete Mail mit Geräteinfos.
```

## Vor dem Archivieren

- [x] Build-Nummer auf **4** erhöht (App + Widget, Debug + Release).
      `MARKETING_VERSION` bleibt **1.0** — zählt erst beim echten
      Store-Release hoch, nicht zwischen Beta-Builds.
- [ ] **Bauen.** Der gesamte Stand ist ungebaut; ohne erfolgreichen
      `Product → Build` ist alles Weitere sinnlos.
- [ ] Kurzer Gerätedurchlauf der Liste oben, besonders der neue
      Look (Icon/Launch Screen/Typografie) auf einem echten Gerät.
- [ ] `Product → Archive` → Organizer → `Distribute App` → App Store Connect.

## Das Wichtigste an diesem Build

**Keine Schema-Änderungen.** Seit Build 3 ist kein neues Feld an `Clip`
oder `Project` dazugekommen — reines Update, keine Migration, kein
Nachrüstlauf nötig.

**Automatische Cover-Reparatur.** Projekt-Cover mit falschem
Seitenverhältnis (Symptom: verzerrt wirkendes Vorschaubild) werden beim
ersten Start dieses Builds automatisch neu zugeschnitten — läuft im
selben Repair-Pass wie bisher schon, kein zusätzlicher Schritt.

**Danach:** Falls dieser Build sauber durchläuft, ist der nächste
Schritt die echte Einreichung — App-Store-Screenshots, die Store-Texte
aus `store/listing.md` eintragen, Freigabe für Prüfung.
