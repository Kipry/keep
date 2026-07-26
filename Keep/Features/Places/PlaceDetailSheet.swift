import SwiftUI

/// What you get when you tap a place on the map: the clips recorded *there*.
///
/// Previously a tap jumped straight into the whole project, which threw away
/// the place context the user had just navigated to. The place is the subject
/// here — its clips come first, and the project is offered as a follow-up.
struct PlaceDetailSheet: View {
    let place: Place
    /// Human label for when the place was first visited ("3 days ago").
    let relativeLabel: String
    let onOpenProject: (Project) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewerIndex: Int?

    private let columns = [GridItem(.adaptive(minimum: 72, maximum: 96), spacing: 10)]

    /// Distinct projects represented at this place, in chronological order.
    private var projects: [Project] {
        var seen = Set<UUID>()
        return place.clips.compactMap(\.project).filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    subtitleRow

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                        ForEach(Array(place.clips.enumerated()), id: \.element.id) { idx, clip in
                            ClipThumbCell(clip: clip) { viewerIndex = idx }
                        }
                    }

                    if !projects.isEmpty {
                        Divider().overlay(.white.opacity(0.1))
                        projectLinks
                    }
                }
                .padding(.horizontal, Layout.gutter)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(place.displayName ?? String(localized: "Unknown place"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 30, height: 30)
                            .background(Theme.control, in: Circle())
                    }
                }
            }
            .toolbarBackground(Theme.background, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: Binding(
            get: { viewerIndex != nil },
            set: { if !$0 { viewerIndex = nil } }
        )) {
            ClipViewer(clips: place.clips, initialIndex: viewerIndex ?? 0)
        }
    }

    private var subtitleRow: some View {
        HStack(spacing: 6) {
            Text(place.clipCount == 1
                 ? String(localized: "1 clip")
                 : String(localized: "\(place.clipCount) clips"))
            Text(verbatim: "·")
            Text(relativeLabel)
        }
        .font(.mono(10, weight: .medium))
        .tracking(1)
        .foregroundStyle(Theme.amber)
    }

    /// One row per project that has clips here — a place can span several.
    private var projectLinks: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(projects) { project in
                Button {
                    dismiss()
                    onOpenProject(project)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.amber)
                            .frame(width: 30, height: 30)
                            .background(Theme.amber.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(project.name)
                                .font(.hand(18))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text("Open project")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .padding(10)
                    .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
