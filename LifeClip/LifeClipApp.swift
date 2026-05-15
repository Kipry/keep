import SwiftUI
import SwiftData
import CoreText

@main
struct LifeClipApp: App {

    @State private var deepLinkProjectID: UUID?

    init() { Self.registerFonts() }

    var body: some Scene {
        WindowGroup {
            ContentView(deepLinkProjectID: $deepLinkProjectID)
                .onOpenURL { url in handleDeepLink(url) }
        }
        .modelContainer(for: [Project.self, Clip.self])
    }

    // Handles: lifeclip://record/<UUID>
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "lifeclip",
              url.host == "record",
              let idString = url.pathComponents.dropFirst().first,
              let id = UUID(uuidString: idString) else { return }
        deepLinkProjectID = id
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
