import SwiftUI
import SwiftData

@main
struct LifeClipApp: App {

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Project.self, Clip.self])
    }
}
