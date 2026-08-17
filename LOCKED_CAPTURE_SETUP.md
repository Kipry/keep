# Sperrbildschirm-Aufnahme — Einrichtung in Xcode

Der komplette Code ist geschrieben und im Projekt verdrahtet. **Ein Schritt fehlt
und muss in Xcode passieren:** das Extension-Target selbst anlegen.

## Warum nicht automatisch?

Apple dokumentiert den Extension-Point-Identifier für Capture-Extensions **nicht
öffentlich** — die offizielle Anleitung sagt ausdrücklich, dass die Xcode-Vorlage
die Info.plist erzeugt. Ein falscher Wert führt zu einer Extension, die sich
fehlerfrei baut, signiert und installiert — und einfach nie erscheint.

Inzwischen ist der Wert bekannt (aus der von Xcode erzeugten Info.plist):

```xml
<key>EXAppExtensionAttributes</key>
<dict>
    <key>EXExtensionPointIdentifier</key>
    <string>com.apple.securecapture</string>
</dict>
```

Also `EXAppExtensionAttributes` im ExtensionKit-Stil, **nicht** das ältere
`NSExtension`/`NSExtensionPointIdentifier`-Schema — Schlüssel *und* Wert wären
beim Raten danebengegangen. Genau deshalb kam der Schritt aus der Vorlage.

## Schritt 1 — Target anlegen

1. **File → New → Target…**
2. Gruppe **Application Extension** → **Capture Extension** → *Next*
3. Product Name: **`KeepCapture`**
4. Team: `3832YDF43A`, Embed in Application: **Keep**
5. *Finish* → *Activate* (falls gefragt)

Xcode legt einen Ordner `KeepCapture/` mit einer Beispiel-Datei und einer
korrekten `Info.plist` an.

## Schritt 2 — meine Dateien einsetzen

Im neu erzeugten Ordner liegen bereits meine zwei Dateien:

- `KeepCapture/CaptureExtension.swift` — der `@main`-Einstiegspunkt
- `KeepCapture/LockedCaptureView.swift` — die Aufnahme-Oberfläche

**Lösche die von Xcode erzeugte Beispiel-Swift-Datei** (typischerweise
`KeepCaptureExtension.swift` o. ä.) — sie enthält ein zweites `@main`, was einen
Compile-Fehler gibt. Die `Info.plist` von Xcode bleibt.

Falls Xcode meine Dateien nicht automatisch übernimmt: im Projektnavigator
rechtsklick auf den `KeepCapture`-Ordner → *Add Files to "Keep"…* → beide
Dateien, Target **KeepCapture** ankreuzen.

## Schritt 3 — geteilte Dateien dem Target zuordnen

Diese liegen schon im Projekt und müssen nur zusätzlich beim neuen Target
angehakt werden. Datei anklicken → rechts im *File Inspector* → *Target
Membership* → **KeepCapture** ✓

| Datei | Warum |
|---|---|
| `Keep/Core/Services/CameraService.swift` | die eigentliche Aufnahme |
| `Keep/Core/Services/ExportQuality.swift` | von `RecordingQuality` referenziert |
| `Keep/Core/Services/RecordingDuration.swift` | Clip-Länge |
| `Keep/Core/Services/KeepCaptureIntent.swift` | der geteilte Intent |
| `Keep/Features/Camera/CameraPreviewView.swift` | Kamera-Vorschau |
| `Keep/Features/Camera/CameraControls.swift` | Auslöser, Dauer-Pills, Belichtung, Fokusring |
| `Keep/Core/Services/LocationGranularity.swift` | Genauigkeit für den Standort-Vermerk |
| `Keep/Core/Theme.swift` | Farben |
| `Keep/Resources/Localizable.xcstrings` | deutsche Texte (sonst englisch) |

> Die letzte Zeile ist eine **Ressource**, keine Quelldatei — sie landet
> automatisch in *Copy Bundle Resources*, sobald das Häkchen gesetzt ist.

## Schritt 4 — Berechtigungen

`KeepCapture/Info.plist` **muss** `NSCameraUsageDescription` enthalten (und, weil
keep. mit Ton aufnimmt, `NSMicrophoneUsageDescription`). Steht schon drin — hier
nur, damit klar ist, warum sie da sind und nicht gelöscht werden dürfen.

Das ist keine Formalie: iOS prüft die Usage-Descriptions der Extension, *bevor*
es entscheidet, ob es die Capture-Extension überhaupt startet. Fehlen sie, wird
sie nie gestartet — stattdessen verlangt das System Entsperren und öffnet die
App. Von außen sieht das aus, als gäbe es die Funktion gar nicht.
(WWDC24 „Build a great Lock Screen camera capture experience": *„your extension
and application should both include privacy usage descriptions for the Camera".*)

Die *erteilte* Berechtigung erbt die Extension weiterhin von der App — die App
muss also mindestens einmal gelaufen sein und Kamerazugriff bekommen haben.
Solange das nicht passiert ist, öffnet iOS ebenfalls die App statt der Extension.
Das ist dokumentiertes Verhalten, kein Fehler.

Kein Entitlement, keine Capability im Developer-Portal. `com.apple.developer.locked-camera-capture`
existiert nicht — wer das einträgt, zerschießt sich nur die Signatur.

## Schritt 5 — testen

Am **echten Gerät**, der Simulator kann den gesperrten Zustand nicht sinnvoll
nachstellen.

1. Bauen und installieren
2. **Einstellungen → Kontrollzentrum**, bzw. Kontrollzentrum bearbeiten →
   Steuerelement hinzufügen → *keep. · Aufnehmen*
   (Alternativ: **Einstellungen → Action-Taste → Steuerung → keep. · Aufnehmen**)
3. Gerät **sperren**
4. Control auslösen → die Kamera muss ohne Entsperren erscheinen
5. Aufnehmen → „Clip gesichert" muss erscheinen
6. Entsperren, App öffnen → der Clip liegt im zuletzt benutzten Projekt, **mit
   der Uhrzeit der Aufnahme**, nicht der des Entsperrens

### Wenn stattdessen die App aufgeht

Es gibt genau einen Fehlerfall, und der sieht immer gleich aus: iOS verlangt
Entsperren und öffnet danach die App. Das ist der dokumentierte Fallback für
„Capture-Extension nicht startbar". In dieser Reihenfolge prüfen:

1. **Usage-Descriptions im *gebauten* Produkt**, nicht in der Quelldatei:
   `plutil -p <DerivedData>/…/Keep.app/Extensions/KeepCapture.appex/Info.plist`
   muss `NSCameraUsageDescription` und `com.apple.securecapture` zeigen.
2. **Kamerazugriff erteilt?** Einstellungen → keep. → Kamera muss an sein.
   Ohne erteilte Berechtigung startet die Extension grundsätzlich nicht.
3. **Liegt die Extension am richtigen Ort?** `ls Keep.app/Extensions/` —
   dort, nicht in `PlugIns/`. (Das ist der Unterschied zwischen *Embed
   ExtensionKit Extensions* und *Embed Foundation Extensions*; das Widget
   gehört nach `PlugIns/`, die Capture-Extension nach `Extensions/`.)
4. **Wirklich gesperrt getestet?** Vom Homescreen oder aus dem
   Kontrollzentrum im entsperrten Zustand öffnet das Control korrekterweise
   die App — das ist kein Fehler.
5. **Registrierung hängt.** App löschen, Gerät neu starten, neu installieren,
   einmal öffnen, Kamera erlauben, sperren, testen. Bekanntes Problem seit
   iOS 18 Beta.

## Was bewusst *nicht* geht

Das ist kein Fehler, sondern Apples Sicherheitsgrenze — und genau das, was du
wolltest:

- Die Extension kann **die Projektliste nicht lesen**. Sie zeigt nur den Namen,
  den die App ihr zuletzt über den App-Context mitgegeben hat.
- Sie kann **keine bestehenden Clips anzeigen**. Dafür muss entsperrt werden.
- Sie hat **keinen Netzwerkzugriff** und **keinen Zugriff auf den App-Group-
  Container**.
- Der Clip wird deshalb **nicht** von der Extension einsortiert, sondern von
  `LockedCaptureImporter` in der App beim nächsten Entsperren.

## Offene Design-Entscheidung

Aktuell landet ein gesperrt aufgenommener Clip **im zuletzt bearbeiteten
Projekt** (Variante A aus unserem Gespräch). Wenn noch gar kein Projekt
existiert, wird eines namens „Meine Clips" angelegt.

Falls du lieber Variante B willst (fester Eingang, den du danach zuordnest),
ist das eine Änderung an genau einer Funktion:
`LockedCaptureImporter.targetProject(in:)`.
