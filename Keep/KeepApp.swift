import SwiftUI
import SwiftData
import CoreText

// MARK: - Deep-link state

/// Shared observable that any view in the hierarchy can read/write.
/// Set by KeepApp.onOpenURL; consumed by ProjectListView /
/// ProjectDetailView to navigate straight into the camera.
@Observable
final class AppDeepLink {
    var pendingRecordProjectID: UUID?
    var pendingOpenProjectID: UUID?
}

// MARK: - App entry point

@main
struct KeepApp: App {

    @State private var deepLink = AppDeepLink()

    init() { Self.registerFonts() }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(deepLink)
                .onOpenURL { url in handleDeepLink(url) }
        }
        .modelContainer(for: [Project.self, Clip.self])
    }

    // keep://record/<UUID>  →  open project + start recording
    // keep://open/<UUID>    →  just open project detail
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "keep",
              let idString = url.pathComponents.dropFirst().first,
              let id = UUID(uuidString: idString) else { return }
        switch url.host {
        case "record": deepLink.pendingRecordProjectID = id
        case "open":   deepLink.pendingOpenProjectID   = id
        default: break
        }
    }

    private static func registerFonts() {
        let files = [
            "PatrickHand-Regular.ttf",
            "JetBrainsMono-Regular.ttf",
            "JetBrainsMono-Medium.ttf",
            "Caveat-Regular.ttf",
        ]
        for file in files {
            guard let url = Bundle.main.url(forResource: file, withExtension: nil) else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
