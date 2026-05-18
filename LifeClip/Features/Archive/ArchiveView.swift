import SwiftUI
import SwiftData

struct ArchiveView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<Project> { $0.isArchived && !$0.isDeleted },
        sort: \Project.updatedAt,
        order: .reverse
    )
    private var archivedProjects: [Project]

    @State private var projectToDelete: Project?
    @State private var selectedProject: Project?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ARCHIVIERT")
                                .font(.eyebrow)
                                .tracking(2)
                                .foregroundStyle(.white.opacity(0.35))
                            Text("Archiv")
                                .font(.appWordmark)
                                .foregroundStyle(.white)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 24)

                    if archivedProjects.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)
                            ],
                            spacing: 10
                        ) {
                            ForEach(archivedProjects) { project in
                                Button { selectedProject = project } label: {
                                    ArchiveCard(project: project)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        project.unarchive()
                                    } label: {
                                        Label("Wiederherstellen", systemImage: "arrow.uturn.up")
                                    }
                                    Button(role: .destructive) {
                                        projectToDelete = project
                                    } label: {
                                        Label("Löschen", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 110)
                }
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $selectedProject) { project in
            ProjectDetailView(project: project, recordOnAppear: false)
        }
        .confirmationDialog(
            "Delete \"\(projectToDelete?.name ?? "")\"?",
            isPresented: Binding(get: { projectToDelete != nil }, set: { if !$0 { projectToDelete = nil } }),
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

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 80)
            Image(systemName: "archivebox")
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.12))
            VStack(spacing: 8) {
                Text("Noch kein Archiv")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text("Halte ein Projekt lang gedrückt und wähle\n„Archivieren", um es hier abzulegen.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.38))
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Archive card (compact, 3-column)

private struct ArchiveCard: View {
    let project: Project

    var body: some View {
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
                            Image(systemName: "archivebox")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.2))
                        }
                }
            }
            .frame(height: 116)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 1) {
                Text(project.name)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(project.updatedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .padding(7)
        }
        .overlay(alignment: .topTrailing) {
            Text("\(project.activeClips.count)")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.paper)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.black.opacity(0.55), in: Capsule())
                .overlay(Capsule().stroke(Theme.paper.opacity(0.4), lineWidth: 1))
                .padding(5)
        }
    }
}
