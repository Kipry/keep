import SwiftUI
import SwiftData
import AVKit
import PhotosUI

struct ProjectDetailView: View {
    @Bindable var project: Project
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isCameraPresented = false
    @State private var isPlayerPresented = false
    @State private var isExportOptionsPresented = false
    @State private var isExporting = false
    @State private var exportedURL: URL?
    @State private var exportError: String?

    @State private var importSelections: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var isReorderMode = false
    @State private var clipToDelete: Clip?

    @State private var selectedTransition: TransitionStyle = .crossFade
    @State private var selectedQuality: ExportQuality = .p1080

    private let composer = VideoComposer()

    // Clips in rows of 4 for the filmstrip layout
    private var filmRows: [[Clip]] {
        let clips = project.activeClips
        guard !clips.isEmpty else { return [] }
        return stride(from: 0, to: clips.count, by: 4).map {
            Array(clips[$0..<min($0 + 4, clips.count)])
        }
    }

    private var durationLabel: String {
        let t = project.totalDuration
        return t < 60
            ? String(format: "%.0fs", t)
            : String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                navBar
                titleBlock

                if project.activeClips.isEmpty {
                    emptyState
                } else if isReorderMode {
                    reorderList
                } else {
                    filmstripContent
                }
            }

            // Right-edge vertical toolbar (overlaid)
            if !isReorderMode && !project.activeClips.isEmpty {
                rightEdgeToolbar
            }

            if isExporting { progressOverlay(text: "Compiling video…") }
            if isImporting { progressOverlay(text: "Importing videos…") }
        }
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraView { url, dur in addClip(fileURL: url, duration: dur) }
        }
        .fullScreenCover(isPresented: $isPlayerPresented) {
            ProjectPlayerView(project: project)
        }
        .fullScreenCover(isPresented: $isExportOptionsPresented) {
            CompilationOptionsView(
                transition: $selectedTransition,
                quality: $selectedQuality,
                clipCount: project.activeClips.count
            ) { Task { await exportVideo() } }
        }
        .sheet(item: $exportedURL) { url in ShareSheet(url: url) }
        .confirmationDialog(
            "Delete this clip?",
            isPresented: Binding(get: { clipToDelete != nil }, set: { if !$0 { clipToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let c = clipToDelete { c.softDelete(); clipToDelete = nil }
            }
            Button("Cancel", role: .cancel) { clipToDelete = nil }
        } message: { Text("You can restore it within 30 days.") }
        .alert("Export Failed",
               isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(exportError ?? "") }
        .onChange(of: importSelections) { _, items in
            guard !items.isEmpty else { return }
            Task { await importVideos(from: items) }
        }
    }

    // MARK: - Nav bar

    private var navBar: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Library")
                        .font(.system(size: 17))
                }
                .foregroundStyle(.white)
            }

            Spacer()

            if !project.activeClips.isEmpty {
                Button { isPlayerPresented = true } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .padding(.trailing, 12)
            }

            Menu {
                PhotosPicker(selection: $importSelections, maxSelectionCount: 20, matching: .videos) {
                    Label("Import from Library", systemImage: "photo.on.rectangle")
                }
                if !project.activeClips.isEmpty {
                    Button {
                        withAnimation { isReorderMode.toggle() }
                    } label: {
                        Label(isReorderMode ? "Done Reordering" : "Reorder Clips",
                              systemImage: isReorderMode ? "checkmark" : "arrow.up.arrow.down")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    // MARK: - Title block

    private var titleBlock: some View {
        VStack(spacing: 4) {
            Text(project.name)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            Text("\(project.activeClips.count) CLIPS · \(durationLabel)")
                .font(.system(size: 10, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.38))
        }
        .padding(.bottom, 18)
    }

    // MARK: - Filmstrip scroll content

    private var filmstripContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(filmRows.indices, id: \.self) { i in
                        FilmstripRow(clips: filmRows[i]) { clip in
                            clipToDelete = clip
                        }
                    }

                    // Empty "add to the reel" slot
                    Button { isCameraPresented = true } label: {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: 1.4, dash: [6]))
                            .frame(height: 88)
                            .overlay {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus")
                                    Text("add to the reel")
                                        .font(.system(size: 15))
                                }
                                .foregroundStyle(.white.opacity(0.25))
                            }
                    }
                    .padding(.horizontal, 14)

                    Spacer(minLength: 20)
                }
                .padding(.top, 4)
                .padding(.bottom, 130)
            }

            // Fixed export bar
            exportBar
        }
    }

    // MARK: - Export bar

    private var exportBar: some View {
        VStack(spacing: 6) {
            Button { isExportOptionsPresented = true } label: {
                HStack {
                    Image(systemName: "film.stack")
                    Text("Wind the reel · Export")
                        .font(.system(size: 18, weight: .semibold))
                    Image(systemName: "arrow.right")
                }
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Theme.amber, in: RoundedRectangle(cornerRadius: 14))
            }

            Text("\(project.activeClips.count) CLIPS → 1 VIDEO · ~\(durationLabel)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
                .tracking(0.5)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 32)
        .padding(.top, 10)
        .background(
            LinearGradient(
                colors: [Theme.background.opacity(0), Theme.background],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Right-edge toolbar

    private var rightEdgeToolbar: some View {
        VStack(spacing: 10) {
            // Record (amber)
            Button { isCameraPresented = true } label: {
                Circle()
                    .fill(Theme.amber)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                    }
            }

            // Import
            PhotosPicker(selection: $importSelections, maxSelectionCount: 20, matching: .videos) {
                toolbarBtn(icon: "square.and.arrow.down")
            }

            // Reorder
            Button { withAnimation { isReorderMode = true } } label: {
                toolbarBtn(icon: "arrow.up.arrow.down")
            }

            // More (export options)
            Button { isExportOptionsPresented = true } label: {
                toolbarBtn(icon: "ellipsis")
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 7)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.ink.opacity(0.2), lineWidth: 1.2))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .offset(x: 6)
        .padding(.top, 100)
    }

    private func toolbarBtn(icon: String) -> some View {
        Circle()
            .fill(.white.opacity(0.0))
            .frame(width: 30, height: 30)
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
            }
    }

    // MARK: - Reorder list

    private var reorderList: some View {
        VStack {
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
                                .fill(Theme.cardSurface)
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

            Button("Done Reordering") { withAnimation { isReorderMode = false } }
                .buttonStyle(.borderedProminent)
                .padding()
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "camera.fill")
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.12))
            VStack(spacing: 8) {
                Text("No clips yet")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text("Record a clip or import from your library.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.38))
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                Button { isCameraPresented = true } label: {
                    Label("Record", systemImage: "camera.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.amber)

                PhotosPicker(selection: $importSelections, maxSelectionCount: 20, matching: .videos) {
                    Label("Import", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .padding()
    }

    // MARK: - Overlays

    private func progressOverlay(text: String) -> some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().tint(.white).scaleEffect(1.4)
                Text(text).foregroundStyle(.white).font(.subheadline)
            }
            .padding(32)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
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
        defer { isImporting = false; importSelections = [] }
        for item in items {
            guard let video = try? await item.loadTransferable(type: VideoTransferable.self) else { continue }
            addClip(fileURL: video.url, duration: video.duration)
        }
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

// MARK: - Filmstrip Row (2-b design)

private struct FilmstripRow: View {
    let clips: [Clip]
    let onDelete: (Clip) -> Void

    var body: some View {
        VStack(spacing: 0) {
            sprocketHoles
            HStack(spacing: 5) {
                ForEach(clips) { clip in
                    FilmCell(clip: clip)
                        .contextMenu {
                            Button(role: .destructive) { onDelete(clip) } label: {
                                Label("Delete Clip", systemImage: "trash")
                            }
                        }
                }
                // Pad to always fill 4 cells
                ForEach(0..<(4 - min(clips.count, 4)), id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.04))
                        .aspectRatio(4/5, contentMode: .fit)
                }
            }
            .padding(.horizontal, 6)
            sprocketHoles
        }
        .background(Theme.filmCard)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 14)
    }

    private var sprocketHoles: some View {
        HStack(spacing: 4) {
            ForEach(0..<16, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.background)
                    .frame(width: 8, height: 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
    }
}

// MARK: - Film Cell

private struct FilmCell: View {
    let clip: Clip
    @State private var isPreviewPresented = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let data = clip.thumbnailData, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(.white.opacity(0.06))
                        .overlay {
                            Image(systemName: "film")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.3))
                        }
                }
            }
            .aspectRatio(4/5, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 2))

            // Duration badge — bottom-right, dark bg, mono
            Text(clip.duration < 10
                 ? String(format: "%.0fs", clip.duration)
                 : String(format: "%.0fs", clip.duration))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 3))
                .padding(4)
        }
        .onTapGesture { isPreviewPresented = true }
        .sheet(isPresented: $isPreviewPresented) {
            VideoPlayer(player: AVPlayer(url: clip.fileURL))
                .presentationDetents([.medium, .large])
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
