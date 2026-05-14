import SwiftUI
import SwiftData

struct ProjectListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<Project> { !$0.isDeleted },
        sort: \Project.createdAt,
        order: .reverse
    )
    private var projects: [Project]

    @State private var isCreatingProject = false
    @State private var newProjectName = ""
    @State private var projectToDelete: Project?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // ── Header ──────────────────────────────────────────
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("YOUR LIBRARY")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .tracking(2)
                                    .foregroundStyle(.white.opacity(0.35))
                                Text("LifeClip")
                                    .font(.system(size: 36, weight: .bold))
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
                                columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                                spacing: 14
                            ) {
                                ForEach(projects) { project in
                                    NavigationLink(destination: ProjectDetailView(project: project)) {
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

                // ── Amber FAB ─────────────────────────────────────────────
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
            .navigationBarHidden(true)
        }
        .preferredColorScheme(.dark)
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
        let project = Project(name: name)
        modelContext.insert(project)
        newProjectName = ""
    }
}

// MARK: - Project Card (1-a style)

struct ProjectCard: View {
    let project: Project

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack(alignment: .bottomLeading) {
                // Thumbnail
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

                // Gradient overlay (clear → black 72% at bottom)
                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))

                // Name + date
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(project.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(10)
            }

            // Clip count badge — top-right
            Text("\(project.activeClips.count)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.paper)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.black.opacity(0.55), in: Capsule())
                .overlay(Capsule().stroke(Theme.paper.opacity(0.4), lineWidth: 1))
                .padding(8)
        }
    }
}
