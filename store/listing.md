# App Store Listing — keep.

Copy-paste-Vorlage für App Store Connect. Zeichenlimits sind pro Feld angegeben.
Zwei Sprachen: **Deutsch (Primär)** und **English (U.S.)**.

---

## Allgemein (sprachunabhängig)

- **Bundle-ID:** `com.kipry.keep.app`
- **Primäre Kategorie:** Lifestyle (`public.app-category.lifestyle`, bereits im Projekt gesetzt)
- **Sekundäre Kategorie (optional):** Foto & Video
- **Preis:** kostenlos (empfohlen für v1)
- **Altersfreigabe:** 4+ (kein anstößiger Inhalt; siehe Checkliste)
- **Copyright:** `2026 Karl-Pierre Kipry`
  > Pflichtfeld in App Store Connect, sprachunabhängig. Ohne Jahr davor
  > akzeptiert Apple es zwar, zeigt es aber unvollständig an.

---

## Deutsch (de-DE)

**App-Name** (max. 30 Zeichen)
```
keep.
```

**Untertitel** (max. 30 Zeichen)
```
Dein Leben, ein Clip pro Tag
```
> 28 Zeichen. Alternativen: „Video-Tagebuch, ein Tap" (23), „Ein Tap. Aufgenommen." (21)

**Beschreibung** (max. 4000 Zeichen)
```
keep. ist ein tägliches Video-Tagebuch, gebaut für einen einzigen Tipp.

Ein Tipp auf den Aufnahme-Knopf im Sperrbildschirm, und der Moment ist festgehalten, ohne das Handy zu entsperren. Danach bist du wieder im Moment statt am Handy.

• Aufnehmen vom Sperrbildschirm, aus dem Kontrollzentrum oder mit der Action-Taste
• Clips mit 1, 1,6, 3 oder 5 Sekunden, oder den Auslöser halten, so lange du willst
• Clips in Projekte sortieren und aus jedem einen Film in 1080p oder 4K machen
• Auf deine Tage zurückblicken, in der Zeitachse und auf einer Karte

Alles bleibt auf deinem Gerät. Kein Konto, kein Tracking, keine Werbung.

Halt den Moment. Bevor er weg ist.
```

**Keywords** (max. 100 Zeichen, kommagetrennt, keine Leerzeichen nach Kommas)
```
tagebuch,video,journal,clip,sekunde,rückblick,erinnerung,vlog,widget,sperrbildschirm,karte,orte
```
> 95 Zeichen. „keep" nicht als Keyword nötig (App-Name deckt es ab).

**Werbetext / Promotional Text** (max. 170 Zeichen, jederzeit änderbar ohne Review)
```
Ein Tap auf dem Sperrbildschirm – ohne Entsperren – und der Moment ist festgehalten. Kein Umweg über die Kamera-App, kein Zögern.
```

**Neue Funktionen / What's New** (v1.2)
```
• Der Knopf für ein neues Projekt sitzt jetzt in der Leiste unten.
• Behoben: Ein Clip konnte verloren gehen, wenn die App direkt nach der Aufnahme beendet wurde.
• Behoben: Ein getrimmter Clip ließ sich erst öffnen, nachdem man das Projekt verlassen hatte.
• Behoben: Die Leiste über dem Auslöser stand mit der Frontkamera nicht mittig.
```

**Neue Funktionen / What's New** (v1.3, Entwurf für den nächsten Build)
```
• Querformat: keep. erkennt, wie du das Handy hältst.
• Exportierte Filme beginnen mit einem neuen Vorspann mit Projektname und Zeitraum.
```

---

## English (en-US)

> US-Schreibweise durchgehend (Control Center, vacation, off-center, canceled).
> Alle Aussagen gegen den Code geprüft, Stand v1.3.

**App Name** (max. 30 chars)
```
keep.
```

**Subtitle** (max. 30 chars)
```
Your life, one clip a day
```
> 25 chars.

**Description** (max. 4000 chars)
```
keep. is a daily video journal built around a single tap.

Tap the record button on your Lock Screen and the moment is saved, without unlocking your phone. Then you're back in the moment instead of behind your phone.

• Record from the Lock Screen, Control Center or the Action button
• Clips of 1, 1.6, 3 or 5 seconds, or hold the shutter for as long as you like
• Sort your clips into projects and turn each one into a film in 1080p or 4K
• Look back on your days in the timeline and on a map

Everything stays on your device. No account, no tracking, no ads.

Hold the moment. Before it's gone.
```

**Keywords** (max. 100 chars)
```
journal,video,diary,clip,seconds,memories,vlog,widget,lockscreen,map,places,capture,lookback
```
> 92 chars.

**Promotional Text** (max. 170 chars)
```
One tap from your Lock Screen — no unlocking — and the moment is saved. No detour through the camera app.
```

**What's New** (v1.2)
```
• The new-project button now sits in the bottom bar.
• Fixed: a clip could be lost if the app closed right after recording.
• Fixed: a trimmed clip wouldn't open until you left the project.
• Fixed: the bar above the shutter was off-center on the front camera.
```

**What's New** (v1.3, draft for the next build)
```
• Record in landscape: keep. knows which way you're holding your phone.
• Exported films open with a new intro showing your project's name and dates.
```

---

## Screenshots (Pflicht)

App Store Connect verlangt mindestens **ein 6.9"-iPhone-Set** (1320 × 2868 px, z.B. iPhone 16 Pro Max). Ein 6.5"-Set (1284 × 2778) ist optional als Fallback.

Empfohlene 6–7 Motive (jeweils am echten Gerät oder Simulator aufnehmen):
1. Sperrbildschirm mit dem keep.-Aufnahmeknopf unten rechts (der „Hero"-Moment —
   jetzt die Aufnahme ohne Entsperren, nicht mehr das REC-Widget)
2. Kamera-Aufnahme mit laufendem Ring
3. Projekt-Filmstreifen mit echten Clips
4. Tagebuch-Zeitachse
5. Orte-Karte mit Pins und Reiseroute
6. Chronik mit Jahresspirale und Streak
7. Fertiges Export-Video / Teilen-Sheet

Die vorhandenen Onboarding-Mocks (`OnboardingView.swift`) spiegeln 1–4 bereits pixelgenau und taugen als Bild-/Text-Vorlage.
