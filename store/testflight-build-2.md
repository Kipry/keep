# TestFlight — Build 1.0 (2)

## „Was soll getestet werden?" (What to Test)

Zum Kopieren in App Store Connect → TestFlight → Build 1.0 (2):

```
NEU IN DIESEM BUILD

Behoben
• ABSTURZ beim Löschen des letzten Clips in einem Projekt.
• Gelöschte Clips blieben manchmal ausgegraut im Filmstreifen stehen und
  verschwanden erst beim Neuöffnen des Projekts – oder ließen sich gar
  nicht mehr löschen, weder über das x noch über die Mehrfachauswahl. Im
  selben Zustand ließen sich Clips auch nicht mehr antippen.
• Sollte das Speichern einer Löschung fehlschlagen, sagt die App das
  jetzt, statt den Clip stillschweigend wiederkommen zu lassen.
• Das haptische Feedback beim Stoppen kam verzögert – es wartete darauf,
  dass die Videodatei fertig geschrieben war. Jetzt sitzt es im Moment
  des Stopps.
• Die Vorschaubilder in der Projektübersicht waren unscharf: sie wurden
  in einem Drittel der nötigen Auflösung erzeugt.

Neu
• Aufnahmedauer: neue Voreinstellung φ – der goldene Schnitt, 1,618
  Sekunden. 2 Sekunden ist entfallen.
• Projekte haben jetzt ein Filmplakat statt einer Kopfzeile: großer
  Abspielknopf, darunter Anzahl der Clips und Länge des fertigen Films.
• Export → „Video sichern" bestätigt jetzt animiert, wenn das Video
  wirklich in der Mediathek gelandet ist.
• Wer noch kein Widget eingerichtet hat, findet in der Bibliothek einen
  Hinweis mit lesbarer Anleitung – auch dauerhaft in den Einstellungen.
• „Rückblicke" heißt jetzt „Chronik" und zeigt deine Jahresspirale. Ein
  Tipp auf die Streak im Widget öffnet sie direkt.

WORAUF ICH BESONDERS SCHAUE

1. Der Löschfehler, in beiden Varianten:
   a) Ein Projekt mit nur EINEM Clip anlegen und diesen löschen – darf
      nicht mehr abstürzen.
   b) Einen Clip anfassen, verschieben und in einer LÜCKE loslassen
      (nicht auf einem anderen Clip) – und ihn dann löschen. Er muss
      sofort verschwinden, über das x wie über die Mehrfachauswahl.
2. Fühlt sich φ als Länge richtig an? Zu kurz, zu lang, genau richtig?
3. Findest du das Abspielen jetzt schneller als vorher?
4. Beim Scrollen im Projekt: wandert der Abspielknopf sauber nach oben in
   die Leiste, oder gibt es einen Moment ohne?

Alles, was hakt oder komisch aussieht, gerne über den Feedback-Knopf in
den Einstellungen – der öffnet eine vorbereitete Mail mit Geräteinfos.
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
