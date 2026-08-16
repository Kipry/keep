import SwiftUI
import SwiftData

struct ProjectListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppDeepLink.self) private var deepLink

    @Query(
        filter: #Predicate<Project> { !$0.isTrashed && !$0.isArchived },
        sort: \Project.updatedAt,
        order: .reverse
    )
    private var projects: [Project]

    @State private var isCreatingProject = false
    @State private var newProjectName = ""
    @State private var projectToDelete: Project?
    @State private var projectToRename: Project?
    @State private var renameText = ""
    @State private var selectedProject: Project?
    @State private var deepLinkMissing = false
    @State private var recordOnNextOpen = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Theme.background.ignoresSafeArea()

            // Header stays pinned; only the project grid scrolls underneath it,
            // dissolving softly at the top edge (same treatment as the streak view).
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, Layout.gutter)
                    .padding(.top, Layout.headerTop)
                    .padding(.bottom, 12)

                // Sits in the pinned region so it shows in the empty state as
                // well as the populated one — and it is the only screen every
                // user lands on.
                WidgetHintCard()
                    .padding(.horizontal, Layout.gutter)
                    .padding(.bottom, 12)

                if projects.isEmpty {
                    // Outside the ScrollView on purpose: a Spacer inside one has
                    // no free height to claim, which left the empty state stuck
                    // under the header instead of centred.
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 14),
                                    GridItem(.flexible(), spacing: 14)
                                ],
                                spacing: 14
                            ) {
                                ForEach(projects) { project in
                                    Button { selectedProject = project } label: {
                                        ProjectCard(project: project)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button {
                                            renameText = project.name
                                            projectToRename = project
                                        } label: {
                                            Label("Rename", systemImage: "pencil")
                                        }
                                        Button {
                                            duplicateProject(project)
                                        } label: {
                                            Label("Duplicate", systemImage: "plus.square.on.square")
                                        }
                                        Button {
                                            project.archive()
                                        } label: {
                                            Label("Archive", systemImage: "archivebox")
                                        }
                                        Button(role: .destructive) {
                                            projectToDelete = project
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, Layout.gutter)

                            Spacer(minLength: 110)
                        }
                        .padding(.top, 12)
                    }
                    .topEdgeFade()
                }
            }

            // ── Amber FAB ────────────────────────────────────────────────
            Button { isCreatingProject = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 58, height: 58)
                    .background(Theme.amber, in: Circle())
                    .shadow(color: Theme.ink.opacity(0.55), radius: 0, x: 2, y: 3)
            }
            .accessibilityLabel("New Project")
            .padding(.trailing, 20)
            .padding(.bottom, 36)
        }
        .preferredColorScheme(.dark)
        // ── Project detail — full-screen so it owns the entire layout ──
        .fullScreenCover(item: $selectedProject) { project in
            ProjectDetailView(project: project, recordOnAppear: recordOnNextOpen)
                .onDisappear { recordOnNextOpen = false }
        }
        // ── Widget snapshot: keep it fresh whenever projects change ──
        .onChange(of: projects) { _, _ in
            WidgetDataStore.refresh(context: modelContext)
            handlePendingDeepLink()
        }
        // ── Deep link: fired on cold launch and when already running ──
        // The refresh also runs here: onChange doesn't fire for the initial
        // query result, so a launch with unchanged projects would otherwise
        // never rewrite the snapshot (streak and week go stale overnight).
        .onAppear {
            WidgetDataStore.refresh(context: modelContext)
            WidgetInstallation.shared.refresh()
            handlePendingDeepLink()
            handlePendingOpen()
        }
        .onChange(of: deepLink.pendingRecordProjectID) { _, _ in handlePendingDeepLink() }
        .onChange(of: deepLink.pendingOpenProjectID)   { _, _ in handlePendingOpen() }
        .alert("Project Not Found", isPresented: $deepLinkMissing) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("That project has been archived or deleted. Your other projects are here in the library.")
        }
        .alert("New Project", isPresented: $isCreatingProject) {
            TextField("Project name", text: $newProjectName)
            Button("Create") { createProject() }
            Button("Cancel", role: .cancel) { newProjectName = "" }
        } message: {
            Text("Give your project a name — e.g. \"Summer 2026\".")
        }
        .alert("Rename Project", isPresented: Binding(
            get: { projectToRename != nil },
            set: { if !$0 { projectToRename = nil } }
        )) {
            TextField("Project name", text: $renameText)
            Button("Rename") { renameProject() }
            Button("Cancel", role: .cancel) { projectToRename = nil }
        } message: {
            Text("Enter a new name for \"\(projectToRename?.name ?? "")\".")
        }
        .confirmationDialog(
            "Delete \"\(projectToDelete?.name ?? "")\"?",
            isPresented: Binding(
                get: { projectToDelete != nil },
                set: { if !$0 { projectToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let p = projectToDelete { p.softDelete(); projectToDelete = nil }
            }
            Button("Cancel", role: .cancel) { projectToDelete = nil }
        } message: {
            Text("The project will be moved to trash and can be restored at any time.")
        }
    }

    // MARK: - Pinned header

    private var header: some View {
        ScreenHeader(eyebrow: Text("YOUR LIBRARY"), title: "keep")
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "film.stack")
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.12))
            VStack(spacing: 8) {
                Text("No projects yet")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text("Tap + to create your first project\nand start capturing moments.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.38))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.bottom, 60)
    }

    // MARK: - Actions

    /// An empty `projects` means the query hasn't delivered yet, so a miss is
    /// worth retrying. A miss against a populated list means the project is
    /// archived, trashed or gone — retrying forever would just re-scan on every
    /// mutation for the rest of the session while the user sees nothing at all.
    private func resolveDeepLink(_ id: UUID) -> Project?? {
        if let project = projects.first(where: { $0.id == id }) { return project }
        return projects.isEmpty ? nil : .some(nil)
    }

    private func handlePendingOpen() {
        guard let id = deepLink.pendingOpenProjectID else { return }
        guard let outcome = resolveDeepLink(id) else { return }   // retry later
        deepLink.pendingOpenProjectID = nil
        guard let project = outcome else { deepLinkMissing = true; return }
        if selectedProject?.id != id { selectedProject = project }
    }

    private func handlePendingDeepLink() {
        guard let id = deepLink.pendingRecordProjectID else { return }
        guard let outcome = resolveDeepLink(id) else { return }   // retry later
        guard let project = outcome else {
            deepLink.pendingRecordProjectID = nil
            deepLinkMissing = true
            return
        }
        // Always arm the flag so ProjectDetailView opens the camera regardless
        // of whether the project was already selected.
        recordOnNextOpen = true
        if selectedProject?.id != id {
            selectedProject = project
        }
        // Don't nil out pendingID here — ProjectDetailView will consume it.
    }

    private func renameProject() {
        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let project = projectToRename else { return }
        project.name = name
        project.updatedAt = Date()
        projectToRename = nil
    }

    /// Saved immediately: the copy owns new files on disk from the moment
    /// `duplicate` returns, so leaving the records unsaved would strand them
    /// if the app were killed before the next autosave.
    private func duplicateProject(_ project: Project) {
        project.duplicate(context: modelContext)
        try? modelContext.save()
    }

    private func createProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        modelContext.insert(Project(name: name))
        newProjectName = ""
    }
}

// MARK: - Project Card

struct ProjectCard: View {
    let project: Project
    /// Decoded once per cover rather than on every body evaluation — at cover
    /// size that is a real cost, and the grid re-evaluates on any data change.
    @State private var cover: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let cover {
                        Image(uiImage: cover)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(.white.opacity(0.07))
                            .overlay {
                                Image(systemName: "film")
                                    .font(.title)
                                    .foregroundStyle(.white.opacity(0.18))
                            }
                    }
                }
                .frame(height: 196)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.cardTitle)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(project.updatedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.monoCaption)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(10)
            }

            Text("\(project.activeClips.count)")
                .font(.clipBadge)
                .foregroundStyle(Theme.paper)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.black.opacity(0.55), in: Capsule())
                .overlay(Capsule().stroke(Theme.paper.opacity(0.4), lineWidth: 1))
                .padding(8)
        }
        .task(id: project.coverThumbnailData) {
            cover = project.coverThumbnailData.flatMap(UIImage.init(data:))
        }
    }
}
