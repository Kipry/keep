# TestFlight — Build 1.0 (2)

## „Was soll getestet werden?" (What to Test)

Zum Kopieren in App Store Connect → TestFlight → Build 1.0 (2):

```
Danke fürs Weitertesten! Neu in diesem Build — und genau darauf hätte ich
gern Rückmeldung:

• BEHOBEN: Gelöschte Clips blieben manchmal ausgegraut im Filmstreifen
  stehen und verschwanden erst beim Neuöffnen. Bitte einmal gezielt
  ausprobieren: einen Clip anfassen, verschieben, in einer Lücke loslassen
  – und ihn dann löschen. Er muss sofort weg sein.

• Aufnahmedauer: neue Voreinstellung φ (der goldene Schnitt, 1,618 s).
  2 s ist entfallen. Fühlt sich die Länge richtig an?

• Haptik beim Stoppen sollte jetzt exakt im Moment des Stopps sitzen,
  nicht mehr verzögert.

• Projekt öffnen: der Kopfbereich ist jetzt ein Filmplakat mit großem
  Abspielknopf. Findest du das Abspielen schneller als vorher? Beim
  Scrollen wandert der Knopf nach oben in die Leiste.

• Projektübersicht: die Vorschaubilder sollten deutlich schärfer sein.

• Export → „Video sichern": es kommt eine animierte Bestätigung, wenn das
  Video wirklich in der Mediathek gelandet ist. Bei „In Dateien sichern"
  kommt bewusst keine.

• Widget: wer noch keins eingerichtet hat, sieht in der Bibliothek einen
  Hinweis mit Anleitung. Er sollte verschwinden, sobald das Widget da ist.

• Die Seite „Rückblicke" heißt jetzt „Chronik" und zeigt deine
  Jahresspirale. Ein Tipp auf die Streak im Widget öffnet sie direkt.

Alles, was hakt oder komisch aussieht, gerne über den Feedback-Knopf in
den Einstellungen.
```

## Vor dem Archivieren

- [x] Build-Nummer auf **2** erhöht (App + Widget, Debug + Release).
      `MARKETING_VERSION` bleibt **1.0** — 1.0 ist nie im Store erschienen,
      es zählt allein die Build-Nummer nach oben.
- [ ] **Bauen.** Der gesamte Stand ist ungebaut; ohne erfolgreichen
      `Product → Build` ist alles Weitere sinnlos.
- [ ] Eigenes Gerät: App-Group-Container sichern, falls du den Build über
      deine Installation legst (siehe unten).
- [ ] Kurzer Gerätedurchlauf der Liste unten.
- [ ] `Product → Archive` → Organizer → `Distribute App` → App Store Connect.

## Das Wichtigste an diesem Build

**Schema-Änderungen.** Seit Build 1 sind `Project.coverClipID`,
`Clip.toneHex` und `Clip.toneAnalyzed` dazugekommen — alle optional bzw.
mit Standardwert, also lightweight-migrierbar. Trotzdem ist das die erste
echte Migration deiner bestehenden Daten. Vorher sichern.

**Einmalige Arbeit beim ersten Start.** Zwei Nachrüstläufe laufen los:
Cover-Bilder werden neu gerendert (ein Videobild pro Projekt) und
Clip-Farbtöne nachgerechnet (ein Vorschaubild pro Tag). Bei vielen Clips
kann der erste Start dadurch kurz beschäftigt wirken. Danach nie wieder.

**Widget-Snapshot.** Der Schlüssel ist bereits in Build 1 auf `V3`
gewandert; hier ändert sich nichts mehr daran.
