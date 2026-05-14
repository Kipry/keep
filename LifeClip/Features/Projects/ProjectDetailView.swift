import SwiftUI
import SwiftData
import AVKit
import PhotosUI

struct ProjectDetailView: View {
    @Bindable var project: Project
    @Environment(\.modelContext) private var modelContext

    // Sheets & overlays
    @State private var isCameraPresented = false
    @State private var isExportOptionsPresented = false
    @State private var isExporting = false
    @State private var exportedURL: URL?
    @State private var exportError: String?

    // Import
    @State private var importSelections: [PhotosPickerItem] = []
    @State private var isImporting = false

    // Reorder
    @State private var isReorderMode = false

    // Delete
    @State private var clipToDelete: Clip?

    // Export options
    @State private var selectedTransition: TransitionStyle = .crossFade
    @State private var selectedQuality: ExportQuality = .p1080

    private let composer = VideoComposer()

    var body: some View {
        Group {
            if project.activeClips.isEmpty {
                emptyState
            } else if isReorderMode {
                reorderList
            } else {
                clipGrid
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarContent }
        // Camera
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraView { url, duration in addClip(fileURL: url, duration: duration) }
        }
        // PhotosPicker — library import
        .photosPicker(
            isPresented: .constant(false), // triggered via toolbar button below
            selection: $importSelections,
            maxSelectionCount: 20,
            matching: .videos
        )
        .onChange(of: importSelections) { _, items in
            guard !items.isEmpty else { return }
            Task { await importVideos(from: items) }
        }
        // Export options sheet
        .sheet(isPresented: $isExportOptionsPresented) {
            CompilationOptionsView(
                transition: $selectedTransition,
                quality: $selectedQuality,
                clipCount: project.activeClips.count
            ) {
                Task { await exportVideo() }
            }
        }
        // Share sheet
        .sheet(item: $exportedURL) { url in ShareSheet(url: url) }
        // Delete confirmation
        .confirmationDialog(
            "Delete this clip?",
            isPresented: Binding(get: { clipToDelete != nil }, set: { if !$0 { clipToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let c = clipToDelete { softDelete(c) }
            }
            Button("Cancel", role: .cancel) { clipToDelete = nil }
        } message: {
            Text("You can restore it within 30 days.")
        }
        // Error banner
        .alert("Export Failed", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        // Export progress overlay
        .overlay { if isExporting { exportOverlay } }
        // Import progress overlay
        .overlay { if isImporting { importOverlay } }
    }

    // MARK: - Subviews

    private var clipGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 4)], spacing: 4) {
                ForEach(project.activeClips) { clip in
                    ClipCell(clip: clip)
                        .contextMenu {
                            Button(role: .destructive) { clipToDelete = clip } label: {
                                Label("Delete Clip", systemImage: "trash")
                            }
                        }
                }
            }
            .padding(4)
        }
    }

    private var reorderList: some View {
        List {
            ForEach(project.activeClips) { clip in
                HStack(spacing: 12) {
                    if let data = clip.thumbnailData, let img = UIImage(data: data) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.secondarySystemBackground))
                            .frame(width: 56, height: 56)
                            .overlay { Image(systemName: "film").foregroundStyle(.secondary) }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(clip.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                        Text(String(format: "%.1fs", clip.duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onMove(perform: moveClips)
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(.active))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No clips yet")
                .font(.title3.bold())
            Text("Record a new clip or import\nvideos from your library.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button { isCameraPresented = true } label: {
                    Label("Record", systemImage: "camera.fill")
                }
                .buttonStyle(.borderedProminent)

                PhotosPicker(selection: $importSelections, maxSelectionCount: 20, matching: .videos) {
                    Label("Import", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    private var exportOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().tint(.white).scaleEffect(1.5)
                Text("Compiling video…").foregroundStyle(.white).font(.subheadline)
            }
            .padding(32)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private var importOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().tint(.white).scaleEffect(1.5)
                Text("Importing videos…").foregroundStyle(.white).font(.subheadline)
            }
            .padding(32)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Camera button
        ToolbarItem(placement: .primaryAction) {
            Button { isCameraPresented = true } label: {
                Image(systemName: "camera.fill")
            }
        }

        // Secondary actions menu
        ToolbarItem(placement: .secondaryAction) {
            PhotosPicker(selection: $importSelections, maxSelectionCount: 20, matching: .videos) {
                Label("Import from Library", systemImage: "photo.on.rectangle")
            }
        }

        if !project.activeClips.isEmpty {
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    withAnimation { isReorderMode.toggle() }
                } label: {
                    Label(isReorderMode ? "Done Reordering" : "Reorder Clips",
                          systemImage: isReorderMode ? "checkmark" : "arrow.up.arrow.down")
                }
            }

            ToolbarItem(placement: .secondaryAction) {
                Button { isExportOptionsPresented = true } label: {
                    Label("Export Video", systemImage: "square.and.arrow.up")
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
        Task {
            if let img = await composer.thumbnail(from: fileURL),
               let data = img.jpegData(compressionQuality: 0.7) {
                clip.thumbnailData = data
                if project.activeClips.count == 1 { project.coverThumbnailData = data }
            }
        }
    }

    private func importVideos(from items: [PhotosPickerItem]) async {
        isImporting = true
        defer {
            isImporting = false
            importSelections = []
        }
        for item in items {
            guard let video = try? await item.loadTransferable(type: VideoTransferable.self) else { continue }
            addClip(fileURL: video.url, duration: video.duration)
        }
    }

    private func softDelete(_ clip: Clip) {
        clip.softDelete()
        clipToDelete = nil
    }

    private func moveClips(from source: IndexSet, to destination: Int) {
        var ordered = project.activeClips
        ordered.move(fromOffsets: source, toOffset: destination)
        for (i, clip) in ordered.enumerated() { clip.order = i }
    }

    private func exportVideo() async {
        isExporting = true
        defer { isExporting = false }
        let urls = project.activeClips.map { $0.fileURL }
        do {
            let url = try await composer.compose(clips: urls, transition: selectedTransition, quality: selectedQuality)
            exportedURL = url
        } catch {
            exportError = error.localizedDescription
        }
    }
}

// MARK: - URL Identifiable

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
