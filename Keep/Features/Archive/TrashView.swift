import SwiftUI
import SwiftData

/// The trash the app has always promised and never had.
///
/// `softDelete()` set `isDeleted` from the very first version, but every query
/// filtered those records out and `restore()` had no call site anywhere — so a
/// deletion was, from the user's side, permanent, while the confirmation
/// dialog said it "can be restored at any time". This is the screen that makes
/// that sentence true.
struct TrashView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Project> { $0.isDeleted }, sort: \Project.deletedAt, order: .reverse)
    private var deletedProjects: [Project]

    @Query(filter: #Predicate<Clip> { $0.isDeleted }, sort: \Clip.deletedAt, order: .reverse)
    private var deletedClips: [Clip]

    @State private var projectToPurge: Project?
    @State private var clipToPurge: Clip?
    @State private var showEmptyConfirm = false

    /// Clips whose parent project is itself trashed are listed under the
    /// project, not again on their own — otherwise deleting a project would
    /// flood the trash with all of its clips.
    private var looseClips: [Clip] {
        deletedClips.filter { !($0.project?.isDeleted ?? false) }
    }

    private var isEmpty: Bool { deletedProjects.isEmpty && looseClips.isEmpty }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        retentionNote

                        if !deletedProjects.isEmpty {
                            section("Projects") {
                                ForEach(deletedProjects) { project in
                                    row(title: project.name,
                                        subtitle: subtitle(for: project.deletedAt,
                                                           count: project.clips.count,
                                                           isProject: true),
                                        restore: { project.restore(); save() },
                                        purge: { projectToPurge = project })
                                }
                            }
                        }

                        if !looseClips.isEmpty {
                            section("Clips") {
                                ForEach(looseClips) { clip in
                                    row(title: clip.project?.name ?? String(localized: "Clip"),
                                        subtitle: subtitle(for: clip.deletedAt, count: nil, isProject: false),
                                        restore: { clip.restore(); save() },
                                        purge: { clipToPurge = clip })
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Layout.gutter)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
        }
        .safeAreaInset(edge: .top) { header }
        .preferredColorScheme(.dark)
        .confirmationDialog(
            "Delete permanently?",
            isPresented: Binding(get: { projectToPurge != nil }, set: { if !$0 { projectToPurge = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                if let p = projectToPurge { TrashSweep.deleteNow(p, in: modelContext) }
                projectToPurge = nil
            }
            Button("Cancel", role: .cancel) { projectToPurge = nil }
        } message: {
            Text("This project and its clips will be removed from your device. This cannot be undone.")
        }
        .confirmationDialog(
            "Delete permanently?",
            isPresented: Binding(get: { clipToPurge != nil }, set: { if !$0 { clipToPurge = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                if let c = clipToPurge { TrashSweep.deleteNow(c, in: modelContext) }
                clipToPurge = nil
            }
            Button("Cancel", role: .cancel) { clipToPurge = nil }
        } message: {
            Text("This clip will be removed from your device. This cannot be undone.")
        }
        .confirmationDialog(
            "Empty trash?",
            isPresented: $showEmptyConfirm,
            titleVisibility: .visible
        ) {
            Button("Empty Trash", role: .destructive) { emptyTrash() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Everything in the trash will be removed from your device. This cannot be undone.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .bottom) {
            ScreenHeader(eyebrow: Text("DELETED"), title: Text("Trash")) {
                if !isEmpty {
                    AmberChip(label: "EMPTY") { showEmptyConfirm = true }
                        .accessibilityLabel("Empty trash")
                }
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 32, height: 32)
                    .background(Theme.control, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .padding(.leading, 10)
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, Layout.headerTop)
        .padding(.bottom, 12)
        .background(Theme.background)
    }

    private var retentionNote: some View {
        Text("Items are removed automatically after \(TrashSweep.retentionDays) days.")
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.4))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Rows

    private func section<Content: View>(_ title: LocalizedStringKey,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.eyebrow)
                .tracking(2)
                .foregroundStyle(.white.opacity(0.35))
            content()
        }
    }

    private func row(title: String,
                     subtitle: String,
                     restore: @escaping () -> Void,
                     purge: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.hand(18))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(verbatim: subtitle)
                    .font(.monoCaption)
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)

            Button(action: restore) {
                Image(systemName: "arrow.uturn.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Restore")

            Button(action: purge) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete permanently")
        }
        .padding(.leading, 12)
        .padding(.trailing, 2)
        .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 14))
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "trash")
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.12))
            VStack(spacing: 8) {
                Text("Trash is empty")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text("Deleted projects and clips wait here\nfor \(TrashSweep.retentionDays) days before they're removed.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.38))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.bottom, 60)
    }

    // MARK: Actions

    private func subtitle(for date: Date?, count: Int?, isProject: Bool) -> String {
        var parts: [String] = []
        if let count, isProject {
            parts.append(count == 1 ? String(localized: "1 clip") : String(localized: "\(count) clips"))
        }
        if let date {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        return parts.joined(separator: " · ")
    }

    private func save() {
        try? modelContext.save()
        WidgetDataStore.refresh(context: modelContext)
    }

    private func emptyTrash() {
        for project in deletedProjects { TrashSweep.deleteNow(project, in: modelContext) }
        for clip in looseClips { TrashSweep.deleteNow(clip, in: modelContext) }
        WidgetDataStore.refresh(context: modelContext)
    }
}
