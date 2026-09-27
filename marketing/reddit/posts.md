# keep. auf Reddit: Subreddits und Post-Entwürfe

Stand September 2026. **Vor jedem Post die Regeln des Subreddits lesen.** Sie
ändern sich oft, und viele Subreddits erlauben Eigenwerbung nur an bestimmten
Tagen, mit bestimmtem Flair oder gar nicht. Die Angaben unten sind meine
Einschätzung und nicht geprüft.

`[LINK]` = App-Store-Link, vor dem Posten einsetzen.

## Grundregeln, damit Posts nicht gelöscht oder abgestraft werden

- Offen sagen, dass du die App gemacht hast. Verschleierte Werbung fliegt auf.
- Nicht am selben Tag in mehrere Subreddits denselben Text posten. Reddit
  erkennt das als Spam. Lieber einen pro Tag, jeweils angepasst.
- Nach dem Posten die erste Stunde da sein und auf Kommentare antworten. Das
  entscheidet mehr als der Text.
- Um Feedback bitten, nicht um Downloads.
- Ein Video wirkt stärker als Text: der Clip „Bens Sommer“
  (`marketing/urlaub/keep-urlaub-24s-ton.mp4`) oder eine echte
  Bildschirmaufnahme vom Sperrbildschirm.
- Keine erfundenen Zahlen, keine Übertreibungen. Reddit prüft nach.

## Reihenfolge

| Tag | Subreddit | Warum | Eigenwerbung erlaubt? |
|---|---|---|---|
| 1 | r/SideProject | genau dafür da, freundlich zu Erstlingen | ja |
| 2 | r/iOSProgramming | technische Geschichte, Entwickler als Multiplikatoren | nur mit echtem Inhalt, meist an einem festen Tag („App Saturday“), Regeln prüfen |
| 3 | r/iosapps | Nutzer suchen hier aktiv nach Apps | ja, mit Flair |
| 4 | r/SwiftUI | Showcase, technisches Publikum | Showcases meist erlaubt, Regeln prüfen |
| 5 | r/apfelwelt | deutschsprachig, Apple-Nutzer | Regeln prüfen |
| 6 | r/indiehackers | Gründer-Perspektive | ja |
| optional | r/1SecondEveryday | genau die Zielgruppe, aber Community rund um eine andere App | nur wenn die Regeln es ausdrücklich erlauben, sonst weglassen |

Nicht empfohlen: r/apple, r/iphone, r/productivity und r/journaling
verbieten Eigenwerbung in der Regel und sperren schnell.

---

## 1. r/SideProject

**Titel:**
```
I kept filming short moments and drowning my camera roll, so I built an app that turns them into one film
```

**Text:**
```
Hi! I made keep., a small iOS app for short video clips.

My problem: I'd film lots of tiny moments on a trip or just during the week, a few seconds each. They ended up scattered across my camera roll between screenshots and receipts, and I never did anything with them.

keep. keeps those clips out of your photo library. Each one goes into a project (a trip, a summer, everyday life), and when you're done, one tap turns the whole project into a single film.

To keep it fast, you can record straight from the Lock Screen by putting keep. where the camera button usually sits. The Action button and Control Center work too. Your projects still need an unlock to look at.

A few details:
- Clips of 1, 1.6, 3 or 5 seconds, or hold the shutter as long as you like
- Export in 1080p or 4K
- A timeline and an optional map of where your clips were shot
- No account, no tracking, no ads. Everything stays on the device

It's free on iOS 18+: [LINK]

I'd love honest feedback. Does the idea click for you, or do you just use the camera roll?
```

---

## 2. r/iOSProgramming

Technischer Beitrag. Die App kommt erst am Ende vor. So ein Post bringt
Leuten etwas und wird deshalb eher nicht gelöscht.

**Titel:**
```
Lessons from shipping a LockedCameraCapture extension (recording from the Lock Screen)
```

**Text:**
```
I shipped an app that records video from the Lock Screen via a LockedCameraCapture extension. The docs are thin, so here's what cost me the most time:

1. The extension needs its own NSCameraUsageDescription. I assumed it inherited the app's. It doesn't, and without it the system quietly opens the app (after unlocking) instead of your extension. No error, which makes it painful to debug.

2. Write recordings to session.sessionContentURL, not your own container. The extension's container is wiped when it's suspended, so anything written there is gone before the app sees it. The app picks the files up from the session content directory after unlock.

3. Don't make the camera wait for anything. If the viewfinder isn't up fast, the launch looks like a zoom-in on the Lock Screen that bounces back. I start the capture session first and do everything else (location, etc.) afterwards.

4. The app can't read the extension's data directly, so I pass metadata (e.g. an optional location) alongside the clip and import it on the app side.

5. For landscape clips, AVCaptureDevice.RotationCoordinator plus setting videoRotationAngle on the movie output's connection right before startRecording is all it takes. It only writes the track orientation, so it costs nothing.

Happy to answer questions. The app is keep., a small video diary, if you want to see it in action: [LINK]
```

> Punkte 1 bis 5 stimmen mit dem überein, was wir im Projekt tatsächlich
> gebaut und behoben haben. Nur posten, was du selbst erklären kannst, falls
> jemand nachfragt.

---

## 3. r/iosapps

**Titel:**
```
[Free] keep. — collect short clips in projects instead of your camera roll, then export them as one film
```

**Text:**
```
I'm the developer. keep. is for people who film lots of short moments and don't want them cluttering their photo library.

- Clips go into projects (a trip, a month, everyday life), not your camera roll
- One tap turns a project into a finished film, 1080p or 4K
- Record from the Lock Screen, Action button or Control Center
- Clips of 1 to 5 seconds, or hold to record longer
- Timeline and optional places map to look back
- Free, no account, no tracking, no ads, everything stays on your phone

iOS 18+: [LINK]

Feedback very welcome, good or bad.
```

---

## 4. r/SwiftUI

Am besten als Video-Post mit einer Bildschirmaufnahme der Kamera (Linsen- und
Längen-Leiste, Halten zum Aufnehmen).

**Titel:**
```
The capture bar in my camera app: lens picker and clip length in one capsule
```

**Text:**
```
Built this for my video diary app. Only one group is open at a time; tapping the closed one opens it and folds the other away in the same spring, so it reads as two halves sliding past each other.

The trick that made it feel right: collapsing is a width animation, not a fade. A fading button leaves its space behind and the row looks like it's blinking. A button that shrinks to zero pushes its neighbors along. Labels fade on a shorter curve than the width, so text is never drawn squeezed.

Happy to share code if anyone's interested. The app is keep.: [LINK]
```

---

## 5. r/apfelwelt (Deutsch)

**Titel:**
```
Meine Galerie war voll mit kurzen Clips, also habe ich eine App gebaut, die daraus einen Film macht
```

**Text:**
```
Hallo zusammen, ich habe keep. entwickelt, eine kleine iOS-App für kurze Videoclips.

Mein Problem: Im Urlaub oder unter der Woche filme ich viele kleine Momente, jeweils ein paar Sekunden. Die lagen dann verstreut in der Galerie zwischen Screenshots und Kassenbons, und ich habe nie etwas daraus gemacht.

Bei keep. landen die Clips nicht in der Galerie, sondern in Projekten, zum Beispiel ein Urlaub, ein Sommer oder einfach der Alltag. Am Ende macht ein Tipp aus dem ganzen Projekt einen Film.

Damit es schnell geht, nimmt keep. auch direkt vom Sperrbildschirm auf: Man legt es dorthin, wo sonst unten rechts die Kamera sitzt. Action-Taste und Kontrollzentrum gehen auch. Die Projekte sieht man trotzdem nur entsperrt.

Außerdem:
- Clips mit 1, 1,6, 3 oder 5 Sekunden, oder den Auslöser halten
- Export in 1080p oder 4K
- Zeitachse und optional eine Karte, wo die Clips entstanden sind
- Kein Konto, kein Tracking, keine Werbung, alles bleibt auf dem Gerät

Kostenlos ab iOS 18: [LINK]

Über ehrliches Feedback freue ich mich sehr. Klingt das sinnvoll, oder reicht euch die Galerie?
```

---

## 6. r/indiehackers

**Titel:**
```
Shipped my first iOS app as a solo dev: what I'd do differently
```

**Text:**
```
I just shipped keep., a video diary you can record into from the Lock Screen. A few things I learned along the way:

- App Review rejected an early build because the onboarding didn't lay out properly on iPad, even though it's an iPhone app. iPhone apps run on iPads too, so test there before you submit.
- App names are unique per language. "keep." was free in the German store but taken in the US one, so the English listing needed a different name.
- Keep marketing copy boringly true. Every claim I cut ("sorts itself", "forever") was one a user could have called out.

Free on iOS: [LINK]. Happy to talk about any of it.
```

> Den Punkt „App-Name“ nur verwenden, wenn du den englischen Namen wirklich
> geändert hast. Die anderen Punkte stimmen so, wie sie hier stehen.

---

## 7. r/1SecondEveryday (nur wenn erlaubt)

Vorher unbedingt die Regeln lesen oder die Moderatoren anschreiben. Der
Subreddit dreht sich um eine andere App.

**Titel:**
```
Another take on the daily-clip habit: projects instead of one endless timeline
```

**Text:**
```
Mods, please remove if this isn't okay.

I built keep. for short clips too, but organized a bit differently: clips go into projects (a trip, a summer, everyday life), and each project exports as its own film. Clips of 1 to 5 seconds, and you can record from the Lock Screen or the Action button.

Not trying to pull anyone away from 1SE. It's a different take on the same habit. If you try it, I'd love to hear what's missing: [LINK]
```
