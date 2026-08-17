# TestFlight — Build 1.0 (5)

Der Build, der Build 4 den Rang abläuft: Aufnahme vom Sperrbildschirm, ohne
Entsperren. Dafür wurde die Store-Einreichung bewusst um eine Beta-Runde
verschoben.

## „Was soll getestet werden?" (What to Test)

Zum Kopieren in App Store Connect → TestFlight → Build 1.0 (5):

```
NEU IN DIESEM BUILD: AUFNEHMEN, OHNE DAS HANDY ZU ENTSPERREN

Das ist das große Ding dieses Builds – und es muss einmal eingerichtet
werden, sonst siehst du nichts davon:

  Sperrbildschirm gedrückt halten → Anpassen → Sperrbildschirm →
  eines der beiden unteren Symbole antippen → „keep. · Aufnehmen"

  Oder im Kontrollzentrum (Stift oben links → Steuerung hinzufügen).
  Oder Einstellungen → Action-Taste → Steuerung → „keep. · Aufnehmen".

Danach: Handy sperren, Knopf antippen, aufnehmen. Kein Face ID, kein Code.

Neu
• Aufnahme über Sperrbildschirm, Kontrollzentrum und Action-Taste, ohne
  Entsperren. Die Aufnahme dort kann alles, was die Kamera in der App
  auch kann: Dauer wählen (φ/1/3/5 s), gedrückt halten für freie Länge –
  inklusive nach links wischen zum Sperren für freihändig und hoch/runter
  ziehen zum Zoomen –, tippen zum Fokussieren mit Belichtungsregler,
  Pinch-Zoom, Kamerawechsel und Licht (vorne als Bildschirmblitz).
• Die Clips landen beim nächsten Entsperren automatisch im zuletzt
  benutzten Projekt – mit der Uhrzeit der AUFNAHME, nicht der des
  Entsperrens. Ein Clip von 23:40 zählt also für den Vortag, auch wenn du
  erst morgens entsperrst. Der Standort wird mit erfasst, sofern du ihn in
  den Einstellungen anhast, damit die Clips auch auf der Karte auftauchen.
• Ganze Projekte kopieren: in der Bibliothek auf eine Projektkachel
  gedrückt halten → „Duplizieren". Kopiert alle Clips samt Videodateien –
  die Kopie ist vollständig unabhängig vom Original.
• Die Karte unter „Orte" sieht wärmer aus und passt jetzt zum Rest der
  App. Die + / − Knöpfe sind weg – Pinch und Doppeltipp machen das
  ohnehin präziser, und die Knöpfe saßen genau über den nördlichen Pins.

Behoben
• Der graue Balken am oberen Bildschirmrand im Tagebuch.

Absichtlich so, damit du es nicht als Fehler meldest
• Pro Auslösen gibt es EINEN Clip. Für den nächsten den Knopf erneut
  antippen. (Sag Bescheid, wenn dir ein „Noch einen aufnehmen" fehlt.)
• Tippst du direkt nach der Aufnahme auf „keep. öffnen", hält der Knopf
  einen Moment und zeigt einen Ladekreis – er wartet auf die
  Standortbestimmung. Das ist gewollt, kein Hänger.
• Auf dem Sperrbildschirm siehst du Systemschriften statt der
  keep.-Schriften. Die Extension ist ein eigener Prozess und lädt die
  Schriften nicht mit.
• Vom Sperrbildschirm aus kommst du NICHT an deine Projekte und alten
  Clips – dafür musst du entsperren. Das ist Absicht und der ganze Punkt.

WORAUF ICH BESONDERS SCHAUE

1. Einrichten und dann bei GESPERRTEM Gerät mehrfach auslösen. Geht die
   Kamera jedes Mal direkt auf, ohne Face ID und ohne dass kurz was
   aufblitzt und wieder verschwindet?
2. Clip aufnehmen, Handy gesperrt liegen lassen, später entsperren und
   die App öffnen. Ist der Clip da, im richtigen Projekt – und mit der
   richtigen Uhrzeit und am richtigen Tag im Tagebuch?
3. Direkt nach der Aufnahme auf „keep. öffnen" tippen. Öffnet die App
   zügig, reagiert sie normal, und ist der Clip sofort sichtbar?
4. Tagebuch → „Orte": taucht ein vom Sperrbildschirm aufgenommener Clip
   auf der Karte auf? (Nur wenn Standort in den Einstellungen an ist.)
5. Mehrere Clips hintereinander aufnehmen, OHNE zwischendurch die App zu
   öffnen. Kommen später alle an, in der richtigen Reihenfolge?
6. Ein Projekt duplizieren, dann in der KOPIE Clips löschen oder trimmen.
   Bleibt das Original garantiert unangetastet?
7. Die Kamera in der App selbst – da hat sich unter der Haube einiges
   bewegt. Funktioniert alles wie gewohnt?

Wenn hier nichts Größeres auffällt, geht's als Nächstes in die echte
Store-Prüfung. Alles, was hakt oder komisch aussieht, gerne über den
Feedback-Knopf in den Einstellungen – der öffnet eine vorbereitete Mail
mit Geräteinfos.
```

## Vor dem Archivieren

- [x] Build-Nummer auf **5** erhöht — **alle drei Targets**, Debug + Release.
      Das ist neu und nicht optional: App, Widget *und* KeepCapture müssen
      dieselbe `CFBundleVersion` tragen, sonst lehnt Xcode das Archiv ab.
      `MARKETING_VERSION` bleibt **1.0**.
- [ ] **Bauen.** Der gesamte Stand ist ungebaut.
- [ ] **Prüfen, dass die Extension wirklich im Archiv liegt.** Im Organizer
      das Archiv rechtsklicken → *Show in Finder* → Paketinhalt →
      `Products/Applications/Keep.app/Extensions/KeepCapture.appex`.
      Fehlt sie dort, ist das Feature für alle Tester unsichtbar und der
      Sperrbildschirm-Knopf öffnet stattdessen die App.
- [ ] Gerätedurchlauf der Liste oben, **mit tatsächlich gesperrtem Gerät** —
      der Simulator kann diesen Zustand nicht sinnvoll nachstellen.
- [ ] `Product → Archive` → Organizer → `Distribute App` → App Store Connect.

## Das Wichtigste an diesem Build

**Keine Schema-Änderungen.** An `Clip` und `Project` ist kein Feld
dazugekommen — reines Update, keine Migration.

**Ein neues Target.** `KeepCapture` ist eine Capture-Extension
(`com.apple.securecapture`). Sie braucht kein Entitlement und keine
Capability im Developer-Portal, aber ihre eigene `Info.plist` **muss**
`NSCameraUsageDescription`, `NSMicrophoneUsageDescription` und
`NSLocationWhenInUseUsageDescription` enthalten. Ohne die Kamera-Zeile
startet iOS die Extension gar nicht erst und öffnet stattdessen die App —
und genau das sieht aus wie „die Funktion gibt es nicht".

**Die Datenschutzgrenze bleibt, wo sie war.** Die Extension kann nicht ins
Netz, nicht an den App-Group-Container, nicht an SwiftData und nicht an die
Einstellungen. Sie schreibt ausschließlich die Videodatei plus einen
Standort-Vermerk in ihr Session-Verzeichnis; alles Weitere macht die App
beim Entsperren. Die Standort-Einstellung reist über den App-Context mit —
steht sie auf „Aus" oder ist unbekannt, wird kein Ort erfasst.

**Nichts an der Privacy-Nutzungsbeschreibung im Store ändert sich.** Es
kommen keine neuen Datenarten dazu; es ist derselbe Kameradatenfluss an
einem zweiten Ort.

**Danach:** Läuft dieser Build sauber, ist der nächste Schritt die echte
Einreichung — Screenshots, die Texte aus `store/listing.md`, Freigabe zur
Prüfung.
