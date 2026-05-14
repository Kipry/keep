import SwiftUI
import SwiftData
import AVKit
import PhotosUI
import UniformTypeIdentifiers

struct ProjectDetailView: View {
    @Bindable var project: Project
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Presentation
    @State private var isCameraPresented = false
    @State private var isPlayerPresented = false
    @State private var isExportOptionsPresented = false
    @State private var isExporting = false
    @State private var exportedURL: URL?
    @State private var exportError: String?
    @State private var importSelections: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var clipToDelete: Clip?
    @State private var selectedTransition: TransitionStyle = .crossFade
    @State private var selectedQuality: ExportQuality = .p1080

    // Drag-and-drop reorder state
    @State private var dragClips: [Clip] = []       // local order while dragging
    @State private var draggingClipID: UUID? = nil  // which clip is in flight

    private let composer = VideoComposer()

    // During drag use the local array; otherwise use persisted order
    private var displayClips: [Clip] {
        dragClips.isEmpty ? project.activeClips : dragClips
    }

    private var filmRows: [[Clip]] {
        let clips = displayClips
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
        ZStack(alignment: .topLeading) {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                navBar
                titleBlock

                if project.activeClips.isEmpty {
                    emptyState
                } else {
                    filmstripScrollView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // Right-edge floating toolbar
            if !project.activeClips.isEmpty {
                rightEdgeToolbar
            }

            if isExporting { progressOverlay(text: "Compiling video…") }
            if isImporting { progressOverlay(text: "Importing videos…") }
        }
        .ignoresSafeArea(edges: .bottom)
        .toolbar(.hidden, for: .navigationBar)
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
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 14)
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
        .padding(.bottom, 16)
    }

    // MARK: - Filmstrip scroll view

    private var filmstripScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filmRows.indices, id: \.self) { rowIdx in
                    FilmstripRow(
                        clips: filmRows[rowIdx],
                        draggingClipID: $draggingClipID,
                        onDragStart: { clip in
                            // Snapshot the current order into local array
                            if dragClips.isEmpty { dragClips = project.activeClips }
                            draggingClipID = clip.id
                        },
                        onReorder: reorderDragClips,
                        onDropFinish: commitDragOrder,
                        onDelete: { clipToDelete = $0 }
                    )
                }

                // ── Add-to-reel slot ─────────────────────────────────────
                Button { isCameraPresented = true } label: {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.white.opacity(0.12),
                                style: StrokeStyle(lineWidth: 1.4, dash: [6]))
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
            }
            .padding(.top, 4)
        }
        // Export bar floats above the scroll content, auto-insets the scroll area
        .safeAreaInset(edge: .bottom, spacing: 0) { exportBar }
    }

    // MARK: - Export bar

    private var exportBar: some View {
        VStack(spacing: 6) {
            Button { isExportOptionsPresented = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "film.stack")
                    Text("Wind the reel · Export")
                        .font(.system(size: 18, weight: .semibold))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 20)
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
        .padding(.top, 12)
        .padding(.bottom, 36)   // above home indicator
        .background(
            LinearGradient(
                colors: [Theme.background.opacity(0), Theme.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Right-edge toolbar

    private var rightEdgeToolbar: some View {
        VStack(spacing: 10) {
            // Record — amber accent
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
                toolbarIcon("square.and.arrow.down")
            }

            // Export options
            Button { isExportOptionsPresented = true } label: {
                toolbarIcon("arrow.up.circle")
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.ink.opacity(0.18), lineWidth: 1.2))
        // Float at the right edge, vertically centred in the filmstrip area
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .padding(.trailing, -4)
        .padding(.top, 140)     // clear nav bar + title
        .padding(.bottom, 140)  // clear export bar
        .allowsHitTesting(true)
    }

    private func toolbarIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 14))
            .foregroundStyle(Theme.ink)
            .frame(width: 30, height: 30)
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

    // MARK: - Progress overlay

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

    // MARK: - Drag-and-drop helpers

    private func reorderDragClips(srcID: UUID, dstID: UUID) {
        guard srcID != dstID,
              let fromIdx = dragClips.firstIndex(where: { $0.id == srcID }),
              let toIdx   = dragClips.firstIndex(where: { $0.id == dstID }) else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            dragClips.move(fromOffsets: IndexSet(integer: fromIdx),
                           toOffset: toIdx > fromIdx ? toIdx + 1 : toIdx)
        }
    }

    private func commitDragOrder() {
        for (i, clip) in dragClips.enumerated() { clip.order = i }
        dragClips = []
        draggingClipID = nil
    }

    // MARK: - Data actions

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

    private func exportVideo() async {
        isExporting = true
        defer { isExporting = false }
        let urls = project.activeClips.map { $0.fileURL }
        do {
            let out = try await composer.compose(clips: urls, transition: selectedTransition, quality: selectedQuality)
            exportedURL = out
        } catch {
            exportError = error.localizedDescription
        }
    }
}

// MARK: - FilmstripRow

private struct FilmstripRow: View {
    let clips: [Clip]
    @Binding var draggingClipID: UUID?
    let onDragStart: (Clip) -> Void
    let onReorder: (UUID, UUID) -> Void
    let onDropFinish: () -> Void
    let onDelete: (Clip) -> Void

    var body: some View {
        VStack(spacing: 0) {
            sprocketHoles
            HStack(spacing: 5) {
                ForEach(clips) { clip in
                    FilmCell(
                        clip: clip,
                        draggingClipID: $draggingClipID,
                        onDragStart: { onDragStart(clip) },
                        onDropEntered: { srcID in onReorder(srcID, clip.id) },
                        onDropFinish: onDropFinish
                    )
                    .contextMenu {
                        Button(role: .destructive) { onDelete(clip) } label: {
                            Label("Delete Clip", systemImage: "trash")
                        }
                    }
                }
                // Padding cells so every row is 4 wide
                let padCount = 4 - min(clips.count, 4)
                ForEach(0..<padCount, id: \.self) { _ in
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
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
    }
}

// MARK: - FilmCell

private struct FilmCell: View {
    let clip: Clip
    @Binding var draggingClipID: UUID?
    let onDragStart: () -> Void
    let onDropEntered: (UUID) -> Void
    let onDropFinish: () -> Void

    @State private var isPreviewPresented = false

    private var isDraggingMe: Bool { draggingClipID == clip.id }

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

            // Duration badge
            Text(String(format: "%.0fs", clip.duration))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 3))
                .padding(4)
        }
        // Ghost effect while dragging
        .opacity(isDraggingMe ? 0.3 : 1.0)
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(Theme.amber.opacity(isDraggingMe ? 0 : (draggingClipID != nil ? 0.4 : 0)),
                        lineWidth: 1.5)
        )
        .animation(.easeInOut(duration: 0.18), value: isDraggingMe)
        .onTapGesture { if draggingClipID == nil { isPreviewPresented = true } }
        .onDrag {
            onDragStart()
            return NSItemProvider(object: clip.id.uuidString as NSString)
        }
        .onDrop(
            of: [UTType.plainText],
            delegate: FilmCellDropDelegate(
                draggingClipID: $draggingClipID,
                targetID: clip.id,
                onEntered: onDropEntered,
                onFinish: onDropFinish
            )
        )
        .sheet(isPresented: $isPreviewPresented) {
            VideoPlayer(player: AVPlayer(url: clip.fileURL))
                .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - FilmCellDropDelegate

private struct FilmCellDropDelegate: DropDelegate {
    @Binding var draggingClipID: UUID?
    let targetID: UUID
    let onEntered: (UUID) -> Void
    let onFinish: () -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        guard let srcID = draggingClipID, srcID != targetID else { return }
        onEntered(srcID)
    }

    func performDrop(info: DropInfo) -> Bool {
        onFinish()
        return true
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
