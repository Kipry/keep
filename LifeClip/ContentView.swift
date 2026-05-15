import SwiftUI

struct ContentView: View {
    @Binding var deepLinkProjectID: UUID?

    var body: some View {
        ProjectListView(deepLinkProjectID: $deepLinkProjectID)
    }
}
