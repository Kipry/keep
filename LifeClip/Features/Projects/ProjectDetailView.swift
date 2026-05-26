import SwiftUI
import SwiftData
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers

struct ProjectDetailView: View {
    @Bindable var project: Project
    let recordOnAppear: Bool
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppDeepLink.self) private var deepLink

    // Presentation
    @State private var isCameraPresented = false
    @State private var isPlayerPresented = false
    @State private var isExportOptionsPresented = false
    @State private var isExporting = false
    @State private var exportProgress: Double = 0
    @State private var exportError: String?
    @State private var importSelections: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var clipToDelete: Clip?
    @State private var clipToCopy: Clip?
    @State private var clipToTrim: Clip?
    @State private var showCopyToast = false
    @State private var selectedTransition: TransitionStyle = .cut
    @State private var selectedQuality: ExportQuality = .p1080
    @State private var missingClipCount = 0
    @State private var showMissingClipsAlert = false

    // Drag-and-drop reorder
    @State private var dragClips: [Clip] = []
    @State private var draggingClipID: UUID? = nil

    private let composer = VideoComposer()

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

            // Camera FAB — primary capture action, floating above the export bar
            if !project.activeClips.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button { isCameraPresented = true } label: {
                            Circle()
                                .fill(Theme.amber)
                                .frame(width: 64, height: 64)
                                .overlay {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(Theme.ink)
                                }
                                .shadow(color: Theme.amber.opacity(0.45), radius: 14, y: 4)
                        }
                        .padding(.trailing, 22)
                        .padding(.bottom, 116)  // clears the export bar
                    }
                }
            }

            if isExporting {
                ExportProgressOverlay(clips: project.activeClips, progress: exportProgress)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: isExporting)
            }
            if isImporting { progressOverlay(text: "Importing videos…") }

            if showCopyToast {
                VStack {
                    Spacer()
                    Label("Clip kopiert", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.black.opacity(0.85), in: Capsule())
                        .padding(.bottom, 120)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // fullScreenCover presentation — owns the full screen, no nav bar involved
        .preferredColorScheme(.dark)
        .onAppear {
            let shouldRecord = recordOnAppear || deepLink.pendingRecordProjectID == project.id
            if shouldRecord {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    isCameraPresented = true
                    deepLink.pendingRecordProjectID = nil
                }
            }
        }
        // Handles deep link when this view is already on screen
        .onChange(of: deepLink.pendingRecordProjectID) { _, id in
            guard let id, id == project.id else { return }
            deepLink.pendingRecordProjectID = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isCameraPresented = true
            }
        }
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
        .confirmationDialog(
            "Delete this clip?",
            isPresented: Binding(get: { clipToDelete != nil }, set: { if !$0 { clipToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Clip", role: .destructive) {
                if let c = clipToDelete {
                    modelContext.delete(c)
                    try? modelContext.save()
                    clipToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { clipToDelete = nil }
        }
        .alert("Export Failed",
               isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(exportError ?? "") }
        .alert(
            missingClipCount == 1
                ? "1 Clip nicht gefunden"
                : "\(missingClipCount) Clips nicht gefunden",
            isPresented: $showMissingClipsAlert
        ) {
            Button("Trotzdem exportieren") { isExportOptionsPresented = true }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Die Videodateien dieser Clips fehlen auf dem Gerät und werden beim Export übersprungen.")
        }
        .onChange(of: importSelections) { _, items in
            guard !items.isEmpty else { return }
            Task { await importVideos(from: items) }
        }
        .fullScreenCover(item: $clipToTrim) { clip in
            ClipTrimView(clip: clip) { clipToTrim = nil }
        }
        .sheet(item: $clipToCopy) { clip in
            ProjectPickerSheet(clip: clip, currentProjectID: project.id) {
                clipToCopy = nil
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showCopyToast = true }
                Task {
                    try? await Task.sleep(nanoseconds: 2_200_000_000)
                    withAnimation { showCopyToast = false }
                }
            }
        }
    }

    // MARK: - Nav bar

    private var navBar: some View {
        HStack(alignment: .center) {
            // Back
            Button { dismiss() } label: {
                Text("‹")
                    .font(.hand(28))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }

            // Centre: title + subtitle
            VStack(spacing: 2) {
                Text(project.name)
                    .font(.navTitle)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(project.activeClips.count) CLIPS · \(durationLabel)")
                    .font(.monoCaption)
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity)

            // Right actions
            HStack(spacing: 4) {
                if !project.activeClips.isEmpty {
                    Button { isPlayerPresented = true } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.white.opacity(0.1), in: Circle())
                    }
                }
                PhotosPicker(selection: $importSelections, maxSelectionCount: 20, matching: .videos) {
                    Image(systemName: "plus")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.1), in: Circle())
                }
            }
            .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Title block (collapsed into navBar — kept as spacer stub)

    private var titleBlock: some View {
        Color.clear.frame(height: 4)
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
                            if dragClips.isEmpty { dragClips = project.activeClips }
                            draggingClipID = clip.id
                        },
                        onReorder: reorderDragClips,
                        onDropFinish: commitDragOrder,
                        onDelete: { clipToDelete = $0 },
                        onCopyToProject: { clipToCopy = $0 },
                        onTrim: { clipToTrim = $0 },
                        onSetAsCover: { setClipAsCover($0) }
                    )
                }

                Button { isCameraPresented = true } label: {
                    Text("+ add to the reel")
                        .font(.scrawl(22))
                        .foregroundStyle(.white.opacity(0.25))
                        .frame(maxWidth: .infinity, minHeight: 88)
                        .background {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.white.opacity(0.12),
                                        style: StrokeStyle(lineWidth: 1.4, dash: [6]))
                        }
                }
                .padding(.horizontal, 14)
            }
            .padding(.top, 4)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { exportBar }
    }

    // MARK: - Export bar

    private var exportBar: some View {
        VStack(spacing: 6) {
            Button { openExportIfValid() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "film.stack")
                    Text("Wind the reel · Export")
                        .font(.handBody)
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
                .font(.monoCaption)
                .foregroundStyle(.white.opacity(0.3))
                .tracking(0.5)
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(
            LinearGradient(
                colors: [Theme.background.opacity(0), Theme.background],
                startPoint: .top,
                endPoint: .bottom
            )
        )
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

    private func openExportIfValid() {
        let missing = project.activeClips.filter { !$0.isAvailable }.count
        if missing > 0 {
            missingClipCount = missing
            showMissingClipsAlert = true
        } else {
            isExportOptionsPresented = true
        }
    }

    private func addClip(fileURL: URL, duration: Double) {
        let order = project.activeClips.count
        let clip = Clip(fileURL: fileURL, duration: duration, order: order)
        clip.project = project
        project.updatedAt = Date()
        modelContext.insert(clip)
        Task {
            if let img = await composer.thumbnail(from: fileURL),
               let data = img.jpegData(compressionQuality: 0.7) {
                clip.thumbnailData = data
                if project.activeClips.count == 1 { project.coverThumbnailData = data }
            }
            WidgetDataStore.save(project: project)
        }
    }

    private func setClipAsCover(_ clip: Clip) {
        let offset = CMTime(seconds: clip.trimStart, preferredTimescale: 600)
        let url = clip.fileURL
        Task { @MainActor in
            if let img = await composer.thumbnail(from: url, at: offset),
               let data = img.jpegData(compressionQuality: 0.75) {
                project.coverThumbnailData = data
                try? modelContext.save()
                WidgetDataStore.save(project: project)
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
        let box = ProgressBox()
        isExporting = true
        exportProgress = 0

        // Poll the shared box ~12 fps and reflect into UI state
        let pollTask = Task {
            repeat {
                exportProgress = box.value
                try? await Task.sleep(nanoseconds: 80_000_000)
            } while !Task.isCancelled
        }

        let clipInfos = project.activeClips
            .filter { $0.isAvailable }
            .map { VideoComposer.ClipInfo(url: $0.fileURL, trimStart: $0.trimStart, trimEnd: $0.trimEnd) }
        do {
            let out = try await composer.compose(
                clips: clipInfos,
                transition: selectedTransition,
                quality: selectedQuality,
                progressBox: box
            )
            pollTask.cancel()
            // Flash 100% briefly so the user sees the completed ring
            exportProgress = 1.0
            try? await Task.sleep(nanoseconds: 400_000_000)
            isExporting = false
            exportProgress = 0
            presentShareSheet(for: out)
        } catch {
            pollTask.cancel()
            isExporting = false
            exportProgress = 0
            exportError = error.localizedDescription
        }
    }

    // Presents UIActivityViewController directly from the key window, bypassing SwiftUI sheet
    private func presentShareSheet(for url: URL) {
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.keyWindow?.rootViewController else { return }
        var topVC = rootVC
        while let presented = topVC.presentedViewController { topVC = presented }
        activityVC.popoverPresentationController?.sourceView = topVC.view
        topVC.present(activityVC, animated: true)
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
    let onCopyToProject: (Clip) -> Void
    let onTrim: (Clip) -> Void
    let onSetAsCover: (Clip) -> Void

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
                        onDropFinish: onDropFinish,
                        onDelete: { onDelete(clip) },
                        onCopyToProject: { onCopyToProject(clip) },
                        onTrim: { onTrim(clip) },
                        onSetAsCover: { onSetAsCover(clip) }
                    )
                }
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
        HStack(spacing: 0) {
            ForEach(0..<18, id: \.self) { _ in
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.background)
                    .frame(width: 8, height: 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }
}

// MARK: - FilmCell

private struct FilmCell: View {
    let clip: Clip
    @Binding var draggingClipID: UUID?
    let onDragStart: () -> Void
    let onDropEntered: (UUID) -> Void
    let onDropFinish: () -> Void
    let onDelete: () -> Void
    let onCopyToProject: () -> Void
    let onTrim: () -> Void
    let onSetAsCover: () -> Void

    @State private var isPreviewPresented = false
    @State private var clipPlayer: AVPlayer?

    private var isDraggingMe: Bool { draggingClipID == clip.id }
    private var isDraggingOther: Bool { draggingClipID != nil && !isDraggingMe }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Thumbnail
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
                .font(.durBadge)
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 3))
                .padding(4)
        }
        // Missing-file overlay
        .overlay {
            if !clip.isAvailable {
                ZStack {
                    RoundedRectangle(cornerRadius: 2).fill(.black.opacity(0.72))
                    VStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.yellow)
                        Text("Fehlt")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }
        }
        // Delete badge — top-left corner
        .overlay(alignment: .topLeading) {
            Button { onDelete() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 18, height: 18)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(3)
        }
        .opacity(isDraggingMe ? 0.3 : 1.0)
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(Theme.amber.opacity(isDraggingOther ? 0.35 : 0), lineWidth: 1.5)
        )
        .animation(.easeInOut(duration: 0.18), value: isDraggingMe)
        .animation(.easeInOut(duration: 0.18), value: isDraggingOther)
        .contextMenu {
            Button { onTrim() } label: {
                Label("Trimmen", systemImage: "scissors")
            }
            Button { onSetAsCover() } label: {
                Label("Als Cover setzen", systemImage: "photo")
            }
            Button { onCopyToProject() } label: {
                Label("In Projekt kopieren …", systemImage: "doc.on.doc")
            }
        }
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
        // Clip preview — raw AVPlayerLayer, no AVKit chrome
        .fullScreenCover(isPresented: $isPreviewPresented) {
            ZStack {
                Color.black.ignoresSafeArea()
                if let p = clipPlayer {
                    VideoLayerView(player: p)
                        .ignoresSafeArea()
                        .onTapGesture {
                            p.seek(to: .zero)
                            p.play()
                        }
                }
                VStack {
                    HStack {
                        Button { isPreviewPresented = false } label: {
                            Image(systemName: "chevron.left")
                                .font(.title3.bold())
                                .foregroundStyle(.white)
                                .padding(12)
                                .background(.black.opacity(0.5), in: Circle())
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    Spacer()
                }
            }
            .onAppear {
                let p = AVPlayer(url: clip.fileURL)
                clipPlayer = p
                p.play()
            }
            .onDisappear {
                clipPlayer?.pause()
                clipPlayer = nil
            }
        }
    }
}

// MARK: - ProjectPickerSheet

private struct ProjectPickerSheet: View {
    let clip: Clip
    let currentProjectID: UUID
    let onCopied: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(
        filter: #Predicate<Project> { !$0.isDeleted },
        sort: \Project.updatedAt,
        order: .reverse
    )
    private var allProjects: [Project]

    private var otherProjects: [Project] {
        allProjects.filter { $0.id != currentProjectID }
    }

    var body: some View {
        NavigationStack {
            List(otherProjects) { project in
                Button {
                    clip.copy(into: project, context: modelContext)
                    try? modelContext.save()
                    onCopied()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(project.name)
                                .font(.body.bold())
                                .foregroundStyle(.primary)
                            Text("\(project.activeClips.count) Clips")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("In Projekt kopieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .overlay {
                if otherProjects.isEmpty {
                    ContentUnavailableView(
                        "Keine weiteren Projekte",
                        systemImage: "folder",
                        description: Text("Erstelle ein weiteres Projekt, um Clips dorthin zu kopieren.")
                    )
                }
            }
        }
    }
}

// MARK: - FilmCellDropDelegate

private struct FilmCellDropDelegate: DropDelegate {
    @Binding var draggingClipID: UUID?
    let targetID: UUID
    let onEntered: (UUID) -> Void
    let onFinish: () -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func dropEntered(info: DropInfo) {
        guard let srcID = draggingClipID, srcID != targetID else { return }
        onEntered(srcID)
    }

    func performDrop(info: DropInfo) -> Bool {
        onFinish()
        return true
    }
}
