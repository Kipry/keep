# App-Store-Einreichung — Checkliste für keep.

Alles hier sind **manuelle Schritte in Apple-Konten / Xcode**, die nicht aus dem Repo erledigt werden können. Die Code-/Config-Seite (Teil A des Plans) ist bereits im Repo umgesetzt.

## Projekt-Fakten (zum Nachschlagen)
| | |
|---|---|
| App-Bundle-ID | `com.kipry.keep.app` |
| Widget-Bundle-ID | `com.kipry.keep.app.widget` |
| Capture-Extension-Bundle-ID | `com.kipry.keep.app.KeepCapture` |
| App-Gruppe | `group.com.kipry.keep.app` |
| Team-ID | `3832YDF43A` |
| Version / Build | `1.0` / `6` |
| Mindest-iOS | 18.0 |
| Kategorie | Lifestyle |
| Signing | Automatic |

---

## 0. Voraussetzungen
- [ ] **Apple Developer Program** aktiv ($99/Jahr). Prüfen, dass Team `3832YDF43A` Mitgliedschaft hat und die Rolle „Account Holder/Admin" vorhanden ist.
- [ ] Ein **Mac mit Xcode** (aktuelle Version). Der Archive-Build kann nur dort erstellt werden.

## 1. Identifiers & App-Gruppe im Developer-Portal
(developer.apple.com → Certificates, Identifiers & Profiles)
- [ ] **App Group** `group.com.kipry.keep.app` anlegen (falls noch nicht vorhanden).
- [ ] App-ID `com.kipry.keep.app` registrieren, Capability **App Groups** aktivieren und die Gruppe zuweisen.
- [ ] Widget-App-ID `com.kipry.keep.app.widget` registrieren, ebenfalls **App Groups** + Gruppe zuweisen.
- [ ] Capture-Extension-App-ID `com.kipry.keep.app.KeepCapture` registrieren. **Ohne** App Groups — eine Capture-Extension darf den geteilten Container ohnehin nicht lesen, und sie braucht kein eigenes Entitlement. `com.apple.developer.locked-camera-capture` existiert nicht; wer es einträgt, zerschießt nur die Signatur.
> Bei Automatic Signing legt Xcode die IDs meist selbst an — dann hier nur prüfen, dass die App-Gruppe bei **beiden** IDs gesetzt ist. Ohne das schlägt das Signing fehl.

## 2. Datenschutz- & Support-Seite hosten (GitHub Pages)
Die fertigen Seiten liegen in `docs/` — genau dort, wo GitHub Pages sie veröffentlichen kann
(Pages kann nur aus dem Repo-Wurzelverzeichnis oder aus `/docs` liefern, nicht aus `store/`).

- [x] GitHub → Repo `Kipry/keep` → **Settings** → **Pages**, Source = `main` / `/docs`. **Erledigt, Seiten sind online.**
- Datenschutz: `https://kipry.github.io/keep/privacy.html`
- Support: `https://kipry.github.io/keep/support.html`
> **Wichtig:** Bei jeder Änderung an `docs/` neu prüfen — die Datenschutz-URL muss zum
> Zeitpunkt der Review erreichbar sein *und* zum tatsächlichen Verhalten der App passen.
> Ein 404 oder eine veraltete Policy ist ein häufiger Ablehnungsgrund.

> Die Seiten sind zweisprachig (Deutsch oben, Englisch unten) — eine URL genügt Apple pro Sprache.
> `docs/.nojekyll` verhindert, dass GitHub die Dateien durch seinen Jekyll-Renderer schickt.

## 3. App-Datensatz in App Store Connect anlegen
(appstoreconnect.apple.com → Apps → +)
- [ ] Plattform iOS, Name **keep.**, Primärsprache **Deutsch**, Bundle-ID `com.kipry.keep.app`, SKU frei wählbar.
- [ ] Falls „keep." als Name belegt ist: Alternativname überlegen (der Anzeigename in der App bleibt „keep.").

## 4. Store-Listing füllen (aus `store/listing.md`)
- [ ] Untertitel, Beschreibung, Keywords, Werbetext für **de-DE** und **en-US** einfügen.
- [ ] **Support-URL** (Pflicht) und **Datenschutzrichtlinie-URL** eintragen (aus Schritt 2).
- [ ] Kategorie: Lifestyle (sekundär optional Foto & Video).
- [ ] **Screenshots** hochladen: mindestens ein **6.9"-iPhone-Set** (1320×2868). Motive siehe `store/listing.md`.

## 5. App-Privacy-Fragebogen
(App Store Connect → App-Datenschutz)
- [ ] **„Es werden keine Daten erfasst"** wählen. Apple definiert „erfasst" als *vom Gerät an den Entwickler oder Dritte übertragen* — genau das passiert nicht: Videos, Projekte und Standorte bleiben lokal, es gibt keine eigenen Server und kein Tracking. Das deckt sich mit dem Privacy-Manifest (`NSPrivacyCollectedDataTypes` ist leer).
> **Zum Standort bewusst entschieden:** Die App speichert optional den Aufnahmeort (Voreinstellung: auf ~1,1 km gerundet) und fragt für den Ortsnamen eine Rückwärts-Geokodierung bei Apple an. Diese Anfrage läuft über die System-Ortungsdienste, nicht über uns — es werden also keine Daten an *uns* übertragen. Sollte die Review hier nachfragen, ist die Antwort: Standort wird nur lokal gespeichert, ist abschaltbar, und die Geokodierung ist eine reine Systemanfrage. Die Datenschutzerklärung beschreibt das im Abschnitt „Standort" ausdrücklich.

## 6. Altersfreigabe
- [ ] Fragebogen ausfüllen → Ergebnis **4+** (keine anstößigen Inhalte, kein nutzergenerierter Online-Content, da nichts geteilt/hochgeladen wird).

## 7. Preis & Verfügbarkeit
- [ ] Preis festlegen (empfohlen: **kostenlos**).
- [ ] Länder/Regionen wählen.

## 8. Build erstellen & hochladen (Xcode)
- [ ] In Xcode: Schema **Keep**, Ziel „Any iOS Device (arm64)".
- [ ] `Product → Archive`. Muss ohne Signing-/Entitlement-Fehler durchlaufen.
- [ ] Im Organizer: `Distribute App → App Store Connect → Upload`.
- [ ] Export-Compliance wird dank `ITSAppUsesNonExemptEncryption = false` **nicht** mehr abgefragt.
- [ ] Nach dem Upload erscheint der Build nach einigen Minuten in App Store Connect → dem Release zuweisen.

## 9. (Optional) TestFlight
- [ ] Build für internes TestFlight freigeben und auf einem **echten Gerät** testen, bevor du einreichst.

## 10. Hinweise für die App-Prüfung (App Review Information)

Das Feld **„Notes"** ist keine Formalie mehr, seit die Beschreibung mit
„Aufnehmen ohne Entsperren" wirbt: Der Prüfer sieht davon **nichts**, solange
er das Steuerelement nicht selbst hinzufügt. Eine beworbene Funktion, die
niemand findet, ist ein Ablehnungsgrund — und einer, der sich mit vier Zeilen
vermeiden lässt.

- [ ] Unter **App Review Information → Notes** eintragen (Englisch):

```
The headline feature — recording without unlocking — has to be enabled once,
because iOS never adds a third-party control by itself:

  Press and hold the Lock Screen → Customise → Lock Screen → tap one of the
  two buttons at the bottom → choose "keep. · Record".

Then lock the device and tap that button. The camera opens without Face ID or
a passcode. Recording is all it does: projects and existing clips still
require unlocking, by design.

The same control can be added to Control Centre or assigned to the Action
button (Settings → Action Button → Controls).

No account, no server, no login. Everything stays on the device.
```

- [ ] **Kein Demo-Account nötig** — Häkchen „Sign-in required" bleibt aus.

## 11. Einreichen
- [ ] Alle Abschnitte grün → **„Zur Prüfung hinzufügen" / Submit for Review**.
- [ ] Prüfungszeit i.d.R. 1–3 Tage. Bei Rückfragen antwortet man im „App Review"-Bereich.

---

## Vor dem Einreichen unbedingt auf echtem Gerät testen
Der Simulator kann Kamera/Widget/Haptik nicht abbilden. **Der gesamte Stand ist ungebaut** —
viele Änderungen entstanden ohne Compiler, also zuerst `Product → Build`, dann diese Liste.

**Aufnahme & Kamera**
- [ ] Aufnahme per Tap, per Halten, per **Lock** (nach links ziehen) und per **Lautstärketaste**.
- [ ] **Haptik sitzt im Moment des Stopps**, nicht verzögert — in allen fünf Fällen.
      Kamera-Wechsel während der Aufnahme darf **keinen** Stopp-Tick auslösen.
- [ ] Dauer-Picker zeigt **1s / φ / 3s / 5s**, φ ist vorbelegt und wird als Glyphe
      gerendert (kein Kästchen). Migrationsprobe: vorher 2 s einstellen, dann updaten.
- [ ] Ring läuft in **1,618 s** zu, gespeicherte Clipdauer liegt bei ~1,6 s.
- [ ] Einstellungen → Aufnahme → Auflösung auf **4K**, aufnehmen, exportieren, in Fotos die Auflösung prüfen.
- [ ] Einmal mit der **Frontkamera** aufnehmen (Fallback-Pfad, falls sie kein 4K kann).
- [ ] Berechtigungs-Ablehnung → „Open Settings"-Screen statt schwarzem Bild.

**Export**
- [ ] Export mit **Cut** und mit **Kreuzblende**, jeweils mit Bumper (Projekttitel + Zeitraum).
- [ ] Während des Exports **Abbrechen** → App bleibt bedienbar.
- [ ] Bei Aufnahme-Einstellung 1080p: Qualitätskarte ist weg, Hinweiszeile steht da, Seite wirkt nicht leer.
- [ ] **Lautstärke-Angleich**: Projekt mit hörbar unterschiedlich lauten Clips abspielen und exportieren;
      Vorschau und Export müssen gleich klingen. Dann in den Einstellungen auf „Aus" → wieder wie aufgenommen.

**Ansicht & Navigation**
- [ ] Vollbild-Clip: zoomen, in **alle Richtungen schieben**, doppeltippen; bei 1× weiterwischen; einfacher Tipp pausiert weiterhin.
- [ ] **Orte:** weit rauszoomen — einzelne Pins und Reiseroute bleiben sichtbar; Scrubben zeigt den Flugbogen.
- [ ] Standort auf **„Aus"** → keine Abfrage, kein Ort gespeichert.

**Projekt & Wiedergabe**
- [ ] Projekt öffnen: **Filmplakat** oben, scharf, mit Papier-Abspielknopf und
      „N CLIPS · Dauer" darunter.
- [ ] Nach unten scrollen: der Knopf wandert **ohne Lücke** in die obere Leiste;
      Zurück, Auswählen und Import bleiben durchgehend erreichbar.
- [ ] **Löschen nach abgebrochenem Drag:** Clip anfassen, ziehen, **in einer Lücke**
      loslassen — dann löschen. Muss sofort verschwinden. Danach eine Zelle
      antippen: die Vorschau muss sich öffnen.
- [ ] **Export → „Video sichern"** → animierte Bestätigung erscheint.
      **→ „In Dateien sichern"** → es erscheint **keine**.

**Widget-Einrichtung**
- [ ] Widget entfernen → App öffnen → Hinweiskarte in der Bibliothek erscheint.
- [ ] Widget hinzufügen → zurück in die App → Karte ist weg.
- [ ] Karte wegklicken → bleibt weg; Anleitung weiterhin über Einstellungen → Widget.
- [ ] Tipp auf die **Streak im mittleren Widget** öffnet die Chronik.

**Bibliothek**
- [ ] Vorschaubilder der Projekte sind **scharf** (alte Cover werden beim ersten
      Start einmalig neu gerendert — kurz warten).
- [ ] **Papierkorb:** einzelne Clips eines Projekts löschen → wiederherstellen → sitzen an der richtigen Stelle im Filmstreifen.
      Projekt löschen → wiederherstellen. Endgültig löschen → Speicherbelegung in den iOS-Einstellungen prüfen.
- [ ] **Archiv:** Projekt archivieren → in Einstellungen sichtbar → wiederherstellen.
- [ ] Erststart mit 0 Projekten (Empty-States auf allen drei Tabs).

**Widget**
- [ ] In allen drei Homescreen-Stilen prüfen (normal, eingefärbt, transparent).
- [ ] **Über Nacht stehen lassen** und morgens vor der ersten Aufnahme prüfen: das heutige Kästchen der
      Wochenleiste darf **nicht** gefüllt sein. (Der Snapshot-Schlüssel ist auf `V3` gewandert — direkt
      nach dem Update ist das Widget kurz leer, bis die App einmal geöffnet wurde. Das ist erwartet.)

**Sprache & Bedienbarkeit**
- [ ] Gerätesprache auf **Englisch** → Tab-Leiste zeigt „Projects / Diary / Chronicle", Onboarding ist durchgängig englisch (inkl. Datum im Sperrbildschirm-Mock).
- [ ] **Textgröße auf Maximum** → Titel skalieren, Einstellungen brechen nicht um.
- [ ] **VoiceOver** → Aufnahme-Knopf und Tab-Leiste sind ansagbar.
- [ ] **Feedback-Knopf** in den Einstellungen öffnet die Mail-App mit vorbelegter Adresse und Geräteinfos.

## Mögliche Review-Nachfragen (vorbereitet)
- **Sperrbildschirm-Widget/Deep-Link:** legitim über WidgetKit + Custom-URL-Scheme; kein Missbrauch.
- **Lautstärketaste als Auslöser:** nutzt die offizielle `AVCaptureEventInteraction`-API (kein privater Hack).
- **Helligkeits-Override** beim Front-Blitz: nur temporär während der Aufnahme, danach zurückgesetzt.
- **Feedback-Funktion:** öffnet nur einen `mailto:`-Entwurf; die App überträgt selbst nichts. In der
  Datenschutzerklärung unter „Feedback per E-Mail" beschrieben.
- **Standortnutzung:** dient allein dazu, einem Clip seinen Aufnahmeort zuzuordnen (Karten-Ansicht „Orte"). Dreistufig einstellbar, standardmäßig auf ~1,1 km gerundet, komplett abschaltbar, keine Übertragung an uns. Der Zwecktext steht in `NSLocationWhenInUseUsageDescription`.
