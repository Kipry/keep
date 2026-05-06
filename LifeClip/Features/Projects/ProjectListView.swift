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
            Group {
                if projects.isEmpty {
                    emptyState
                } else {
                    projectGrid
                }
            }
            .navigationTitle("LifeClip")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isCreatingProject = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("New Project", isPresented: $isCreatingProject) {
                TextField("Project name", text: $newProjectName)
                Button("Create") { createProject() }
                Button("Cancel", role: .cancel) { newProjectName = "" }
            } message: {
                Text("Give your project a name, e.g. \"Summer 2026\".")
            }
            .confirmationDialog(
                "Delete \"\(projectToDelete?.name ?? "")\"?",
                isPresented: Binding(get: { projectToDelete != nil },
                                     set: { if !$0 { projectToDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Move to Trash", role: .destructive) {
                    if let p = projectToDelete { softDelete(p) }
                }
                Button("Cancel", role: .cancel) { projectToDelete = nil }
            } message: {
                Text("You can restore it from the Trash within 30 days.")
            }
        }
    }

    // MARK: - Subviews

    private var projectGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
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
            .padding(16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "film.stack")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No projects yet")
                .font(.title3.bold())
            Text("Tap + to create your first project\nand start capturing moments.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Create Project") { isCreatingProject = true }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Actions

    private func createProject() {
        guard !newProjectName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let project = Project(name: newProjectName.trimmingCharacters(in: .whitespaces))
        modelContext.insert(project)
        newProjectName = ""
    }

    private func softDelete(_ project: Project) {
        project.softDelete()
        projectToDelete = nil
    }
}

// MARK: - ProjectCard

private struct ProjectCard: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .aspectRatio(1, contentMode: .fit)

                if let thumbnail = project.clips.first(where: { !$0.isDeleted })?.thumbnailData,
                   let image = UIImage(data: thumbnail) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Image(systemName: "film")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }

                // Clip count badge
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("\(project.activeClips.count)")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(8)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(project.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
    }
}
