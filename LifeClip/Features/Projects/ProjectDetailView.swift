import SwiftUI
import SwiftData
import AVKit

struct ProjectDetailView: View {
    @Bindable var project: Project
    @Environment(\.modelContext) private var modelContext

    @State private var isCameraPresented = false
    @State private var isExporting = false
    @State private var exportedURL: URL?
    @State private var exportError: String?
    @State private var clipToDelete: Clip?
    @State private var isEditingOrder = false

    private let composer = VideoComposer()

    var body: some View {
        Group {
            if project.activeClips.isEmpty {
                emptyState
            } else {
                clipGrid
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarContent }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraView { url, duration in
                addClip(fileURL: url, duration: duration)
            }
        }
        .sheet(item: $exportedURL) { url in
            ShareSheet(url: url)
        }
        .confirmationDialog(
            "Delete this clip?",
            isPresented: Binding(get: { clipToDelete != nil },
                                 set: { if !$0 { clipToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let clip = clipToDelete { softDelete(clip) }
            }
            Button("Cancel", role: .cancel) { clipToDelete = nil }
        } message: {
            Text("You can restore it within 30 days.")
        }
        .overlay {
            if isExporting {
                exportOverlay
            }
        }
    }

    // MARK: - Subviews

    private var clipGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 4)], spacing: 4) {
                ForEach(project.activeClips) { clip in
                    ClipCell(clip: clip)
                        .contextMenu {
                            Button(role: .destructive) {
                                clipToDelete = clip
                            } label: {
                                Label("Delete Clip", systemImage: "trash")
                            }
                        }
                }
            }
            .padding(4)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No clips yet")
                .font(.title3.bold())
            Text("Tap the camera to record\nyour first clip.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                isCameraPresented = true
            } label: {
                Label("Record Clip", systemImage: "camera.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var exportOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
                Text("Compiling video…")
                    .foregroundStyle(.white)
                    .font(.subheadline)
            }
            .padding(32)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { isCameraPresented = true } label: {
                Image(systemName: "camera.fill")
            }
        }
        if !project.activeClips.isEmpty {
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    Task { await exportVideo() }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    // MARK: - Actions

    private func addClip(fileURL: URL, duration: Double) {
        let order = project.activeClips.count
        let clip = Clip(fileURL: fileURL, duration: duration, order: order)
        clip.project = project
        modelContext.insert(clip)

        // Generate thumbnail asynchronously
        Task {
            if let image = await composer.thumbnail(from: fileURL),
               let data = image.jpegData(compressionQuality: 0.7) {
                clip.thumbnailData = data
                if project.activeClips.count == 1 {
                    project.coverThumbnailData = data
                }
            }
        }
    }

    private func softDelete(_ clip: Clip) {
        clip.softDelete()
        clipToDelete = nil
    }

    private func exportVideo() async {
        isExporting = true
        defer { isExporting = false }
        let urls = project.activeClips.map { $0.fileURL }
        do {
            let url = try await composer.compose(clips: urls)
            exportedURL = url
        } catch {
            exportError = error.localizedDescription
        }
    }
}

// MARK: - URL Identifiable conformance for sheet(item:)

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

// MARK: - ShareSheet

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}
