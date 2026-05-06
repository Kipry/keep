# LifeClip

A daily life capture iOS app — record short clips and compile them into a video.
Built as a technically superior alternative to Glimpse, fixing its critical audio bug and adding backup, import, and soft-delete.

## Requirements

- Xcode 15+
- iOS 17+ deployment target
- Real device for camera testing (Simulator has no camera)

## Xcode Setup

1. Open Xcode → **File › New › Project** → **iOS App**
   - Product Name: `LifeClip`
   - Bundle ID: `com.yourname.LifeClip`
   - Interface: SwiftUI
   - Language: Swift
   - **Uncheck** Core Data (we use SwiftData)

2. Delete the auto-generated `ContentView.swift` and `LifeClipApp.swift`.

3. Drag the `LifeClip/` folder from this repo into the Xcode project navigator.
   - Make sure **"Copy items if needed"** is checked.
   - Add to target: `LifeClip`.

4. In the project target settings:
   - **Deployment Info**: iOS 17.0
   - **Signing**: select your development team

5. Replace the auto-generated `Info.plist` entries with the ones from `LifeClip/Info.plist`,
   or merge the keys into your project's Info tab.

6. Build and run on a physical device.

## Architecture

```
LifeClip/
├── Core/
│   ├── Models/          # SwiftData: Clip, Project
│   └── Services/        # CameraService, VideoComposer
└── Features/
    ├── Projects/         # ProjectListView, ProjectDetailView
    ├── Camera/           # CameraView, CameraPreviewView
    └── Clips/            # ClipCell
```

## Key fixes over Glimpse

| Issue | Fix |
|---|---|
| Audio silent on clips 2+ | AVAudioSession configured before session start; audio connection verified before every recording |
| No soft-delete / undo | `isDeleted` + `deletedAt` on Clip and Project — 30-day trash window |
| No Camera Roll import | Phase 2: PhotosPicker integration |
| No backup | Phase 3: CloudKit sync |

## Phase Roadmap

- **Phase 1 (current)** — Camera, SwiftData persistence, project/clip management, export
- **Phase 2** — PhotosPicker import, transition effects, background music
- **Phase 3** — iCloud/CloudKit sync, WidgetKit, daily reminders + streaks
- **Phase 4** — Freemium model, App Store submission
