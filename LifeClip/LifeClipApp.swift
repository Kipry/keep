import SwiftUI
import SwiftData
import CoreText

@main
struct LifeClipApp: App {

    init() { Self.registerFonts() }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Project.self, Clip.self])
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
