import SwiftUI
import SwiftData
import AVFoundation
import CoreLocation
import Photos
import PhotosUI
import UniformTypeIdentifiers
import ImageIO

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
    @State private var showBulkDeleteConfirm = false
    @State private var clipToCopy: Clip?
    @State private var clipToTrim: Clip?
    @State private var clipToSetDuration: Clip?
    @State private var showCopyToast = false
    @State private var selectedTransition: TransitionStyle = .cut
    @State private var selectedQuality: ExportQuality = .p1080
    @State private var missingClipCount = 0
    @State private var showMissingClipsAlert = false

    // Drag-and-drop reorder
    @State private var dragClips: [Clip] = []
    @State private var draggingClipID: UUID? = nil

    // Multi-select
    @State private var isSelectMode = false
    @State private var selectedClipIDs: Set<UUID> = []

    // Clip preview carousel
    @State private var previewingClipIndex: Int? = nil

    // Bulk copy
    @State private var clipsToBulkCopy: [Clip]? = nil
    @State private var copyToastText = String(localized: "Clip Copied")

    // Interactive edge-swipe back
    @State private var backSwipeX: CGFloat = 0

    private let composer = VideoComposer()

    private var displayClips: [Clip] {
        dragClips.isEmpty ? project.activeClips : dragClips
    }

    private var selectedClips: [Clip] {
        displayClips.filter { selectedClipIDs.contains($0.id) }
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
            content
        }
        .offset(x: backSwipeX)
        .background(Theme.background.ignoresSafeArea())
        // Swipe in from the left edge to go back to the library.
        .simultaneousGesture(backSwipeGesture)
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
            Button("Move to Trash", role: .destructive) {
                if let c = clipToDelete {
                    // Was modelContext.delete(c): a permanent erase that also
                    // orphaned the video file, while the multi-select path right
                    // below soft-deletes. Same gesture, two different fates.
                    c.softDelete()
                    try? modelContext.save()
                    WidgetDataStore.refresh(context: modelContext)
                    clipToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { clipToDelete = nil }
        } message: {
            Text("The clip will be moved to trash and can be restored at any time.")
        }
        .confirmationDialog(
            selectedClipIDs.count == 1
                ? "Move 1 clip to trash?"
                : "Move \(selectedClipIDs.count) clips to trash?",
            isPresented: $showBulkDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                for clip in selectedClips { clip.softDelete() }
                try? modelContext.save()
                WidgetDataStore.refresh(context: modelContext)
                selectedClipIDs.removeAll()
                isSelectMode = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They can be restored from the trash at any time.")
        }
        .alert("Export Failed",
               isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(exportError ?? "") }
        .alert(
            missingClipCount == 1
                ? "1 Clip Not Found"
                : "\(missingClipCount) Clips Not Found",
            isPresented: $showMissingClipsAlert
        ) {
            Button("Export Anyway") { isExportOptionsPresented = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These clip files are missing from your device and will be skipped during export.")
        }
        .onChange(of: importSelections) { _, items in
            guard !items.isEmpty else { return }
            Task { await importMedia(from: items) }
        }
        .fullScreenCover(item: $clipToTrim) { clip in
            ClipTrimView(clip: clip) { clipToTrim = nil }
        }
        .sheet(item: $clipToSetDuration) { clip in
            PhotoDurationView(clip: clip, composer: composer) { clipToSetDuration = nil }
                .presentationDetents([.height(280)])
        }
        .sheet(item: $clipToCopy) { clip in
            ProjectPickerSheet(clip: clip, currentProjectID: project.id) {
                clipToCopy = nil
                copyToastText = String(localized: "Clip Copied")
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showCopyToast = true }
                Task {
                    try? await Task.sleep(nanoseconds: 2_200_000_000)
                    withAnimation { showCopyToast = false }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { clipsToBulkCopy != nil },
            set: { if !$0 { clipsToBulkCopy = nil } }
        )) {
            if let clips = clipsToBulkCopy {
                BulkProjectPickerSheet(clips: clips, currentProjectID: project.id) {
                    clipsToBulkCopy = nil
                    isSelectMode = false
                    selectedClipIDs.removeAll()
                    copyToastText = String(localized: "\(clips.count) Clips Copied")
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showCopyToast = true }
                    Task {
                        try? await Task.sleep(nanoseconds: 2_200_000_000)
                        withAnimation { showCopyToast = false }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { previewingClipIndex != nil },
            set: { if !$0 { previewingClipIndex = nil } }
        )) {
            if let idx = previewingClipIndex {
                ClipPreviewCarousel(clips: displayClips, initialIndex: idx)
            }
        }
    }

    // MARK: - Main content

    private var content: some View {
        ZStack(alignment: .topLeading) {
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
            if !project.activeClips.isEmpty && !isSelectMode {
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
            if isImporting { progressOverlay(text: "Importing…") }

            if showCopyToast {
                VStack {
                    Spacer()
                    Label(copyToastText, systemImage: "checkmark.circle.fill")
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
    }

    // MARK: - Back-swipe gesture

    private var backSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { v in
                // Only react to drags that begin at the very left edge.
                guard v.startLocation.x < 28, v.translation.width > 0 else { return }
                backSwipeX = min(v.translation.width, 220)
            }
            .onEnded { v in
                let committed = v.startLocation.x < 28
                    && v.translation.width > 90
                    && abs(v.translation.width) > abs(v.translation.height)
                if committed {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { backSwipeX = 0 }
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
            HStack(spacing: 2) {
                if isSelectMode {
                    Button("Done") {
                        isSelectMode = false
                        selectedClipIDs.removeAll()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                } else {
                    if !project.activeClips.isEmpty {
                        Button { isPlayerPresented = true } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(.white.opacity(0.1), in: Circle())
                        }
                        Button { isSelectMode = true } label: {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(.white.opacity(0.1), in: Circle())
                        }
                    }
                    PhotosPicker(selection: $importSelections, maxSelectionCount: 20,
                                 matching: .any(of: [.videos, .images])) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(.white.opacity(0.1), in: Circle())
                    }
                }
            }
            .frame(width: 100, alignment: .trailing)
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
                        isSelectMode: isSelectMode,
                        selectedClipIDs: $selectedClipIDs,
                        onDragStart: { clip in
                            if dragClips.isEmpty { dragClips = project.activeClips }
                            draggingClipID = clip.id
                        },
                        onReorder: reorderDragClips,
                        onDropFinish: commitDragOrder,
                        onDelete: { clipToDelete = $0 },
                        onCopyToProject: { clipToCopy = $0 },
                        onTrim: { clipToTrim = $0 },
                        onSetDuration: { clipToSetDuration = $0 },
                        onSetAsCover: { setClipAsCover($0) },
                        onPreview: { clip in
                            if let idx = displayClips.firstIndex(where: { $0.id == clip.id }) {
                                previewingClipIndex = idx
                            }
                        }
                    )
                }

                if !isSelectMode {
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
            }
            .padding(.top, 4)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isSelectMode {
                selectionActionBar
            } else {
                exportBar
            }
        }
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

    // MARK: - Selection action bar

    private var selectionActionBar: some View {
        VStack(spacing: 6) {
            if selectedClipIDs.isEmpty {
                Text("Tap clips to select")
                    .font(.monoCaption)
                    .foregroundStyle(.white.opacity(0.35))
                    .tracking(0.4)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            } else {
                HStack(spacing: 10) {
                    // Asks before deleting N clips. The single-clip path always
                    // confirmed; the bulk one — the more destructive of the two —
                    // deleted on the first tap with no way back.
                    Button {
                        showBulkDeleteConfirm = true
                    } label: {
                        Label("Delete \(selectedClipIDs.count)", systemImage: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.red.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        clipsToBulkCopy = selectedClips
                    } label: {
                        Label("Copy \(selectedClipIDs.count)", systemImage: "doc.on.doc")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Theme.amber, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            Text(selectedClipIDs.isEmpty
                 ? "0 SELECTED"
                 : "\(selectedClipIDs.count) OF \(displayClips.count) SELECTED")
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

                PhotosPicker(selection: $importSelections, maxSelectionCount: 20,
                             matching: .any(of: [.videos, .images])) {
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

    private func addClip(fileURL: URL, duration: Double, createdAt: Date? = nil,
                         location: CLLocationCoordinate2D? = nil) {
        // Commit any stale drag state so the display stays in sync
        if !dragClips.isEmpty { commitDragOrder() }
        // Use max existing order + 1 so deletions don't create duplicate order values
        let order = (project.activeClips.map(\.order).max() ?? -1) + 1
        let clip = Clip(fileURL: fileURL, duration: duration, order: order, createdAt: createdAt ?? Date())
        clip.project = project
        project.updatedAt = Date()
        modelContext.insert(clip)
        attachLocation(to: clip, imported: location)
        Task {
            if let img = await composer.thumbnail(from: fileURL),
               let data = img.jpegData(compressionQuality: 0.7) {
                clip.thumbnailData = data
                if project.activeClips.count == 1 { project.coverThumbnailData = data }
            }
            WidgetDataStore.refresh(context: modelContext)
        }
    }

    // Stamps the clip with its capture location: an imported asset's own
    // coordinate when available, otherwise the camera's one-shot fix (with a
    // 30s retroactive window for "opened camera, instantly recorded" saves).
    // Reverse geocoding fills placeName asynchronously.
    private func attachLocation(to clip: Clip, imported: CLLocationCoordinate2D?) {
        if let imported {
            clip.latitude = imported.latitude
            clip.longitude = imported.longitude
        } else if let fix = LocationService.shared.takeFix() {
            clip.latitude = fix.latitude
            clip.longitude = fix.longitude
        } else {
            LocationService.shared.onNextFix(within: 30) { coord in
                clip.latitude = coord.latitude
                clip.longitude = coord.longitude
                LocationService.shared.geocodeIfNeeded(clip)
            }
            return
        }
        LocationService.shared.geocodeIfNeeded(clip)
    }

    // Imports a still photo: stores the source image, renders it to a short
    // still-video so it composes like any other clip, and tags it as a photo.
    private func addPhotoClip(imageData: Data, phDate: Date? = nil,
                              location: CLLocationCoordinate2D? = nil) async {
        guard let ui = UIImage(data: imageData)?.normalizedUp() else { return }
        let imports = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Imports", isDirectory: true)
        try? FileManager.default.createDirectory(at: imports, withIntermediateDirectories: true)
        let imageURL = imports.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        guard let jpeg = ui.jpegData(compressionQuality: 0.92) else { return }
        try? jpeg.write(to: imageURL)

        // Priority: PHAsset date (most reliable) → EXIF in the raw image data → now.
        let created = phDate ?? Self.exifCreationDate(from: imageData) ?? Date()
        let duration = 3.0
        guard let movURL = try? await composer.renderStillVideo(from: imageURL, duration: duration) else { return }

        if !dragClips.isEmpty { commitDragOrder() }
        let order = (project.activeClips.map(\.order).max() ?? -1) + 1
        let clip = Clip(fileURL: movURL, duration: duration, order: order, createdAt: created)
        clip.isPhoto = true
        clip.photoDuration = duration
        clip.photoSourceURLString = imageURL.absoluteString
        clip.project = project
        project.updatedAt = Date()
        modelContext.insert(clip)
        if let location {
            clip.latitude = location.latitude
            clip.longitude = location.longitude
            LocationService.shared.geocodeIfNeeded(clip)
        }

        if let thumb = ui.downscaled(maxEdge: 320).jpegData(compressionQuality: 0.7) {
            clip.thumbnailData = thumb
            if project.activeClips.count == 1 { project.coverThumbnailData = thumb }
        }
        WidgetDataStore.refresh(context: modelContext)
    }

    // Reads the original capture date from a still image's EXIF metadata.
    private static func exifCreationDate(from data: Data) -> Date? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        else { return nil }
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let raw = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? (props[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFDateTime] as? String
        guard let stamp = raw else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: stamp)
    }

    private func setClipAsCover(_ clip: Clip) {
        let offset = CMTime(seconds: clip.trimStart, preferredTimescale: 600)
        let url = clip.fileURL
        Task { @MainActor in
            if let img = await composer.thumbnail(from: url, at: offset),
               let data = img.jpegData(compressionQuality: 0.75) {
                project.coverThumbnailData = data
                try? modelContext.save()
                WidgetDataStore.refresh(context: modelContext)
            }
        }
    }

    private func importMedia(from items: [PhotosPickerItem]) async {
        isImporting = true
        defer { isImporting = false; importSelections = [] }
        for item in items {
            // PHAsset carries the authoritative capture time AND location.
            // item.itemIdentifier is the PHAsset local identifier — fetching it is
            // synchronous and instant (Photos library cache, no I/O).
            let asset: PHAsset? = item.itemIdentifier.flatMap { id in
                PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
            }
            let phDate = asset?.creationDate
            // Imported coordinates respect the same granularity setting as live captures.
            let phLocation = asset?.location.flatMap {
                LocationGranularity.current.apply(to: $0.coordinate)
            }

            let types = item.supportedContentTypes
            if types.contains(where: { $0.conforms(to: .movie) }) {
                if let video = try? await item.loadTransferable(type: VideoTransferable.self) {
                    addClip(fileURL: video.url, duration: video.duration,
                            createdAt: phDate ?? video.creationDate, location: phLocation)
                }
            } else if types.contains(where: { $0.conforms(to: .image) }) {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await addPhotoClip(imageData: data, phDate: phDate, location: phLocation)
                }
            }
        }
    }

    // Builds the intro bumper — the project's title and recording date range
    // (first clip's date to last clip's date) burned into the bundled "keep."
    // bumper clip — as the first ClipInfo of the export. Returns nil if the
    // bumper couldn't be rendered so the export can proceed without it.
    private func makeBumperClipInfo() async -> VideoComposer.ClipInfo? {
        let dates = project.activeClips.map(\.createdAt)
        guard let first = dates.min(), let last = dates.max() else { return nil }
        guard let url = await composer.renderBumper(projectName: project.name, startDate: first, endDate: last) else {
            return nil
        }
        return VideoComposer.ClipInfo(url: url, trimStart: 0, trimEnd: nil)
    }

    private func exportVideo() async {
        let box = ProgressBox()
        isExporting = true
        exportProgress = 0

        // Render the intro bumper (title card + recording date range) up front,
        // before the progress ring starts moving. A rendering failure silently
        // falls back to exporting without it rather than blocking the export.
        let bumperClip = await makeBumperClipInfo()

        // Poll the shared box ~12 fps and reflect into UI state
        let pollTask = Task {
            repeat {
                exportProgress = box.value
                try? await Task.sleep(nanoseconds: 80_000_000)
            } while !Task.isCancelled
        }

        var clipInfos = project.activeClips
            .filter { $0.isAvailable }
            .map { VideoComposer.ClipInfo(url: $0.fileURL, trimStart: $0.trimStart, trimEnd: $0.trimEnd) }
        if let bumperClip { clipInfos.insert(bumperClip, at: 0) }
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
        // Whatever the user picked has taken its own copy by now (Photos, Files,
        // Messages…), so our render is dead weight — drop it rather than let
        // every export pile up in the container forever.
        activityVC.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: url)
        }
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
    let isSelectMode: Bool
    @Binding var selectedClipIDs: Set<UUID>
    let onDragStart: (Clip) -> Void
    let onReorder: (UUID, UUID) -> Void
    let onDropFinish: () -> Void
    let onDelete: (Clip) -> Void
    let onCopyToProject: (Clip) -> Void
    let onTrim: (Clip) -> Void
    let onSetDuration: (Clip) -> Void
    let onSetAsCover: (Clip) -> Void
    let onPreview: (Clip) -> Void

    var body: some View {
        VStack(spacing: 0) {
            sprocketHoles
            HStack(spacing: 5) {
                ForEach(clips) { clip in
                    FilmCell(
                        clip: clip,
                        draggingClipID: $draggingClipID,
                        isSelectMode: isSelectMode,
                        isSelected: selectedClipIDs.contains(clip.id),
                        onDragStart: { onDragStart(clip) },
                        onDropEntered: { srcID in onReorder(srcID, clip.id) },
                        onDropFinish: onDropFinish,
                        onDelete: { onDelete(clip) },
                        onCopyToProject: { onCopyToProject(clip) },
                        onTrim: { onTrim(clip) },
                        onSetDuration: { onSetDuration(clip) },
                        onSetAsCover: { onSetAsCover(clip) },
                        onPreview: { onPreview(clip) },
                        onToggleSelect: {
                            if selectedClipIDs.contains(clip.id) {
                                selectedClipIDs.remove(clip.id)
                            } else {
                                selectedClipIDs.insert(clip.id)
                            }
                        }
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
    let isSelectMode: Bool
    let isSelected: Bool
    let onDragStart: () -> Void
    let onDropEntered: (UUID) -> Void
    let onDropFinish: () -> Void
    let onDelete: () -> Void
    let onCopyToProject: () -> Void
    let onTrim: () -> Void
    let onSetDuration: () -> Void
    let onSetAsCover: () -> Void
    let onPreview: () -> Void
    let onToggleSelect: () -> Void

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

            // Duration badge — bottom right (photo gets a small icon prefix)
            HStack(spacing: 2) {
                if clip.isPhoto {
                    Image(systemName: "photo.fill").font(.system(size: 7))
                }
                Text(String(format: "%.0fs", clip.effectiveDuration))
                    .font(.durBadge)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 3))
            .padding(4)
        }
        // Date + time stamp — bottom left
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 1) {
                Text(clip.createdAt, format: .dateTime.day().month().locale(Locale.current))
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                Text(clip.createdAt, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 3))
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
                        Text("Missing")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }
        }
        // Top-left badge: delete (normal) or selection indicator (select mode)
        .overlay(alignment: .topLeading) {
            if isSelectMode {
                ZStack {
                    Circle()
                        .fill(isSelected ? Theme.amber : Color.black.opacity(0.45))
                    Circle()
                        .strokeBorder(isSelected ? Theme.amber : .white.opacity(0.6), lineWidth: 1.5)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.black)
                    }
                }
                .frame(width: 18, height: 18)
                .padding(4)
            } else {
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
        }
        .opacity(isDraggingMe ? 0.3 : (!isSelectMode || isSelected) ? 1.0 : 0.55)
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(
                    isSelectMode && isSelected ? Theme.amber :
                        !isSelectMode && isDraggingOther ? Theme.amber.opacity(0.35) : Color.clear,
                    lineWidth: isSelectMode && isSelected ? 2 : 1.5
                )
        )
        .animation(.easeInOut(duration: 0.18), value: isDraggingMe)
        .animation(.easeInOut(duration: 0.18), value: isDraggingOther)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .contextMenu {
            if !isSelectMode {
                if clip.isPhoto {
                    Button { onSetDuration() } label: {
                        Label("Display Duration…", systemImage: "timer")
                    }
                } else {
                    Button { onTrim() } label: {
                        Label("Trim", systemImage: "scissors")
                    }
                }
                Button { onSetAsCover() } label: {
                    Label("Set as Cover", systemImage: "photo")
                }
                Button { onCopyToProject() } label: {
                    Label("Copy to Project…", systemImage: "doc.on.doc")
                }
            }
        }
        .onTapGesture {
            if isSelectMode {
                onToggleSelect()
            } else if draggingClipID == nil {
                onPreview()
            }
        }
        .onDrag {
            guard !isSelectMode else { return NSItemProvider() }
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
            .navigationTitle("Copy to Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if otherProjects.isEmpty {
                    ContentUnavailableView(
                        "No Other Projects",
                        systemImage: "folder",
                        description: Text("Create another project to copy clips into.")
                    )
                }
            }
        }
    }
}

// MARK: - ClipPreviewCarousel

private struct ClipPreviewCarousel: View {
    let clips: [Clip]
    let initialIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    @State private var players: [UUID: AVPlayer] = [:]

    init(clips: [Clip], initialIndex: Int) {
        self.clips = clips
        self.initialIndex = initialIndex
        _currentIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(clips.indices, id: \.self) { idx in
                    playerPage(for: clips[idx], index: idx)
                        .tag(idx)
                        .ignoresSafeArea()
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            // Chrome overlay
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.black.opacity(0.5), in: Circle())
                    }
                    Spacer()
                    if clips.count > 1 {
                        Text("\(currentIndex + 1) / \(clips.count)")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.65))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.4), in: Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                Spacer()
                // Bottom bar: date/time left, replay button right
                HStack(alignment: .center) {
                    if currentIndex < clips.count {
                        let clip = clips[currentIndex]
                        HStack(spacing: 6) {
                            Text(clip.createdAt, format: .dateTime.day().month().locale(Locale.current))
                            Text(clip.createdAt, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                                .fontDesign(.monospaced)
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    Button { replayCurrentClip() } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.black.opacity(0.5), in: Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .onChange(of: currentIndex) { old, new in
            if old < clips.count { players[clips[old].id]?.pause() }
            if new < clips.count { seekAndPlay(clips[new]) }
        }
        .onAppear { PlaybackAudio.activate() }   // audible over the silent switch
        .onDisappear { PlaybackAudio.deactivate() }
    }

    private func replayCurrentClip() {
        guard currentIndex < clips.count else { return }
        seekAndPlay(clips[currentIndex])
    }

    private func seekAndPlay(_ clip: Clip) {
        guard let player = players[clip.id] else { return }
        let start = CMTime(seconds: clip.trimStart, preferredTimescale: 600)
        player.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
    }

    @ViewBuilder
    private func playerPage(for clip: Clip, index: Int) -> some View {
        if clip.isPhoto {
            // Show the original still image directly — always correctly oriented,
            // independent of how the backing still-video was rendered.
            Zoomable(isActive: index == currentIndex) {
                ZStack {
                    Color.black
                    if let img = photoImage(for: clip) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                    }
                }
            }
        } else {
            Zoomable(isActive: index == currentIndex) {
                ZStack {
                    Color.black
                    if let player = players[clip.id] {
                        VideoLayerView(player: player)
                            .onTapGesture {
                                if player.timeControlStatus == .playing { player.pause() }
                                else { player.play() }
                            }
                    }
                }
            }
            .onAppear {
                if players[clip.id] == nil {
                    let item = AVPlayerItem(url: clip.fileURL)
                    if let trimEnd = clip.trimEnd {
                        item.forwardPlaybackEndTime = CMTime(seconds: trimEnd, preferredTimescale: 600)
                    }
                    let p = AVPlayer(playerItem: item)
                    players[clip.id] = p
                    if index == currentIndex { seekAndPlay(clip) }
                }
            }
            .onDisappear {
                players[clip.id]?.pause()
            }
        }
    }

    // Loads the full still image for a photo clip, falling back to its thumbnail.
    private func photoImage(for clip: Clip) -> UIImage? {
        if let url = clip.photoSourceURL, let img = UIImage(contentsOfFile: url.path) {
            return img
        }
        if let data = clip.thumbnailData { return UIImage(data: data) }
        return nil
    }
}

// MARK: - BulkProjectPickerSheet

private struct BulkProjectPickerSheet: View {
    let clips: [Clip]
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
                    for clip in clips {
                        clip.copy(into: project, context: modelContext)
                    }
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
            .navigationTitle("Copy \(clips.count) Clips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if otherProjects.isEmpty {
                    ContentUnavailableView(
                        "No Other Projects",
                        systemImage: "folder",
                        description: Text("Create another project to copy clips into.")
                    )
                }
            }
        }
    }
}

// MARK: - PhotoDurationView

/// Lets the user set how long a photo is shown in the compiled video. On save
/// the backing still-video is re-rendered at the new duration.
private struct PhotoDurationView: View {
    @Bindable var clip: Clip
    let composer: VideoComposer
    let onDismiss: () -> Void

    @State private var duration: Double = 3
    @State private var isRendering = false

    private let range: ClosedRange<Double> = 1...15

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 18) {
                HStack {
                    Button("Cancel") { onDismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text("Display Duration")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button("Done") { Task { await save() } }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.amber)
                        .disabled(isRendering)
                }

                HStack(spacing: 14) {
                    if let data = clip.thumbnailData, let img = UIImage(data: data) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 70)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "%.1f seconds", duration))
                            .font(.mono(22, weight: .medium))
                            .foregroundStyle(.white)
                        Text("How long this photo stays on screen")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    Spacer()
                }

                Slider(value: $duration, in: range, step: 0.5)
                    .tint(Theme.amber)

                if isRendering {
                    ProgressView().tint(Theme.amber)
                }
            }
            .padding(22)
        }
        .presentationBackground(Theme.background)
        .onAppear { duration = clip.photoDuration }
    }

    private func save() async {
        isRendering = true
        if let src = clip.photoSourceURL,
           let newMov = try? await composer.renderStillVideo(from: src, duration: duration) {
            clip.setFile(newMov)
        }
        clip.photoDuration = duration
        clip.duration = duration
        clip.project?.updatedAt = Date()
        isRendering = false
        onDismiss()
    }
}

// MARK: - UIImage helpers

private extension UIImage {
    /// Returns a copy with the orientation baked into the pixels (`.up`).
    func normalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Returns a copy scaled so its longest edge is at most `maxEdge` points.
    func downscaled(maxEdge: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxEdge else { return self }
        let s = maxEdge / longest
        let newSize = CGSize(width: size.width * s, height: size.height * s)
        return UIGraphicsImageRenderer(size: newSize).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
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
