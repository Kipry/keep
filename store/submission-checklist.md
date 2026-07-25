# App-Store-Einreichung — Checkliste für keep.

Alles hier sind **manuelle Schritte in Apple-Konten / Xcode**, die nicht aus dem Repo erledigt werden können. Die Code-/Config-Seite (Teil A des Plans) ist bereits im Repo umgesetzt.

## Projekt-Fakten (zum Nachschlagen)
| | |
|---|---|
| App-Bundle-ID | `com.kipry.keep.app` |
| Widget-Bundle-ID | `com.kipry.keep.app.widget` |
| App-Gruppe | `group.com.kipry.keep.app` |
| Team-ID | `<deine neue Team-ID>` |
| Version / Build | `1.0` / `1` |
| Mindest-iOS | 18.0 |
| Kategorie | Lifestyle |
| Signing | Automatic |

---

## 0. Voraussetzungen
- [ ] **Apple Developer Program** aktiv ($99/Jahr). Prüfen, dass Team `<deine neue Team-ID>` Mitgliedschaft hat und die Rolle „Account Holder/Admin" vorhanden ist.
- [ ] Ein **Mac mit Xcode** (aktuelle Version). Der Archive-Build kann nur dort erstellt werden.

## 1. Identifiers & App-Gruppe im Developer-Portal
(developer.apple.com → Certificates, Identifiers & Profiles)
- [ ] **App Group** `group.com.kipry.keep.app` anlegen (falls noch nicht vorhanden).
- [ ] App-ID `com.kipry.keep.app` registrieren, Capability **App Groups** aktivieren und die Gruppe zuweisen.
- [ ] Widget-App-ID `com.kipry.keep.app.widget` registrieren, ebenfalls **App Groups** + Gruppe zuweisen.
> Bei Automatic Signing legt Xcode die IDs meist selbst an — dann hier nur prüfen, dass die App-Gruppe bei **beiden** IDs gesetzt ist. Ohne das schlägt das Signing fehl.

## 2. Datenschutz- & Support-Seite hosten
- [ ] `store/privacy-policy.html` und `store/support.html` irgendwo öffentlich hosten (z.B. GitHub Pages, kostenlos).
- [ ] In beiden Dateien das Datum und die **Kontakt-E-Mail bestätigen/ersetzen** (aktuell `kpk.kipry@icloud.com`).
- [ ] Beide URLs notieren — sie kommen in Schritt 4.

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
- [ ] **„Es werden keine Daten erfasst"** wählen. Das entspricht dem Privacy-Manifest (kein Tracking, keine Datensammlung, alles on-device).

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

## 10. Einreichen
- [ ] Alle Abschnitte grün → **„Zur Prüfung hinzufügen" / Submit for Review**.
- [ ] Prüfungszeit i.d.R. 1–3 Tage. Bei Rückfragen antwortet man im „App Review"-Bereich.

---

## Vor dem Einreichen unbedingt auf echtem Gerät testen
Der Simulator kann Kamera/Widget/Haptik nicht abbilden. Auf einem echten iPhone prüfen:
- [ ] Aufnahme per Tap, per Halten, per **Lock** (nach links ziehen) und per **Lautstärketaste** — jeweils mit **Haptik** bei Start/Stopp.
- [ ] Berechtigungs-Ablehnung → „Open Settings"-Screen erscheint statt schwarzem Bild.
- [ ] Foto-Import (Hochkant bleibt korrekt orientiert).
- [ ] Export inkl. vorangestelltem **Bumper** mit Projekttitel + Zeitraum.
- [ ] **Sperrbildschirm-Widget** hinzufügen → Tap öffnet direkt die Aufnahme (Deep-Link `keep://record/<id>`).
- [ ] Erststart mit 0 Projekten (Empty-States).

## Mögliche Review-Nachfragen (vorbereitet)
- **Sperrbildschirm-Widget/Deep-Link:** legitim über WidgetKit + Custom-URL-Scheme; kein Missbrauch.
- **Lautstärketaste als Auslöser:** nutzt die offizielle `AVCaptureEventInteraction`-API (kein privater Hack).
- **Helligkeits-Override** beim Front-Blitz: nur temporär während der Aufnahme, danach zurückgesetzt.
