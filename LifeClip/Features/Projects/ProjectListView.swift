import SwiftUI
import SwiftData

struct ProjectListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppDeepLink.self) private var deepLink

    @Query(
        filter: #Predicate<Project> { !$0.isDeleted },
        sort: \Project.updatedAt,
        order: .reverse
    )
    private var projects: [Project]

    @State private var isCreatingProject = false
    @State private var newProjectName = ""
    @State private var projectToDelete: Project?
    @State private var selectedProject: Project?
    @State private var recordOnNextOpen = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // ── Header ───────────────────────────────────────────
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("YOUR LIBRARY")
                                .font(.eyebrow)
                                .tracking(2)
                                .foregroundStyle(.white.opacity(0.35))
                            Text("LifeClip")
                                .font(.appWordmark)
                                .foregroundStyle(.white)
                        }
                        Spacer()
                        Button {} label: {
                            Image(systemName: "magnifyingglass")
                                .font(.body.bold())
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(.white.opacity(0.1), in: Circle())
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 24)

                    // ── Grid ─────────────────────────────────────────────
                    if projects.isEmpty {
                        emptyState
                    } else {
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
                                    Button(role: .destructive) {
                                        projectToDelete = project
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                    }

                    Spacer(minLength: 110)
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
        .onChange(of: projects) { _, updated in
            if let first = updated.first { WidgetDataStore.save(project: first) }
        }
        // ── Deep link: open the right project and start recording ──
        .onChange(of: deepLink.pendingRecordProjectID) { _, id in
            guard let id else { return }
            guard let project = projects.first(where: { $0.id == id }) else {
                deepLink.pendingRecordProjectID = nil; return
            }
            // If that project's detail is already open, ProjectDetailView handles it.
            // Otherwise open it now with camera auto-start.
            if selectedProject?.id != id {
                recordOnNextOpen = true
                selectedProject = project
            }
            // Don't nil out pendingID here — ProjectDetailView will consume it.
        }
        .alert("New Project", isPresented: $isCreatingProject) {
            TextField("Project name", text: $newProjectName)
            Button("Create") { createProject() }
            Button("Cancel", role: .cancel) { newProjectName = "" }
        } message: {
            Text("Give your project a name — e.g. \"Summer 2026\".")
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
            Text("You can restore it within 30 days.")
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 80)
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
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

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

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let data = project.coverThumbnailData,
                       let img = UIImage(data: data) {
                        Image(uiImage: img)
                            .resizable()
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
    }
}
