import SwiftUI
import SwiftData
import CoreText

// MARK: - Deep-link state

/// Shared observable that any view in the hierarchy can read/write.
/// Set by LifeClipApp.onOpenURL; consumed by ProjectListView /
/// ProjectDetailView to navigate straight into the camera.
@Observable
final class AppDeepLink {
    var pendingRecordProjectID: UUID?
    var pendingOpenProjectID: UUID?
}

// MARK: - App entry point

@main
struct LifeClipApp: App {

    @State private var deepLink = AppDeepLink()

    // CloudKit sync via SwiftData. Falls back to local-only if iCloud is
    // unavailable (no account, simulator without sign-in, etc.).
    private static let container: ModelContainer = {
        do {
            let config = ModelConfiguration(cloudKitDatabase: .automatic)
            return try ModelContainer(for: Project.self, Clip.self, configurations: config)
        } catch {
            return try! ModelContainer(for: Project.self, Clip.self)
        }
    }()

    init() { Self.registerFonts() }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(deepLink)
                .onOpenURL { url in handleDeepLink(url) }
        }
        .modelContainer(Self.container)
    }

    // lifeclip://record/<UUID>  →  open project + start recording
    // lifeclip://open/<UUID>    →  just open project detail
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "lifeclip",
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
