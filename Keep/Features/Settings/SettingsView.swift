import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultRecordingDuration") private var defaultDuration: Double = 1.0
    @AppStorage("locationGranularity") private var locationGranularity = "place"
    @AppStorage("didOnboard") private var didOnboard = true
    @Environment(\.dismiss) private var dismiss

    @State private var showArchive = false
    @State private var showTrash = false

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    recordingSection
                    locationSection
                    librarySection
                    tutorialSection
                    aboutSection
                }
                .padding(.top, 60)
                .padding(.bottom, 60)
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showArchive) { ArchiveView() }
        .fullScreenCover(isPresented: $showTrash) { TrashView() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Theme.control, in: Circle())
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Recording section

    private var recordingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Recording")

            VStack(spacing: 0) {
                row {
                    Text("Default Duration")
                        .foregroundStyle(.white)
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach([1.0, 3.0, 5.0], id: \.self) { d in
                            Button { defaultDuration = d } label: {
                                Text("\(Int(d))s")
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(defaultDuration == d ? Theme.ink : .white.opacity(0.6))
                                    .frame(width: 40, height: 30)
                                    .background(
                                        defaultDuration == d ? Theme.amber : Color(white: 0.22),
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(defaultDuration == d ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                }
            }
            .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Location section

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Location")

            VStack(spacing: 0) {
                row {
                    Text("Save Location")
                        .foregroundStyle(.white)
                    Spacer()
                    HStack(spacing: 6) {
                        granularityButton("Precise", value: "precise")
                        granularityButton("Nearby",  value: "place")
                        granularityButton("Off",     value: "off")
                    }
                }
                rowDivider
                row {
                    Text("Remembers where each clip was captured — shown on the Places map. \"Nearby\" stores only the rough area (~1 km). Everything stays on your device.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineSpacing(2)
                        .padding(.vertical, 10)
                }
            }
            .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
            .padding(.horizontal, 20)
        }
    }

    private func granularityButton(_ label: LocalizedStringKey, value: String) -> some View {
        Button {
            locationGranularity = value
            // Turning location off also discards the cached place names. They
            // are a location history in their own right and survived both the
            // setting and the clips they came from until now.
            if value == "off" { LocationService.shared.clearNameCache() }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(locationGranularity == value ? Theme.ink : .white.opacity(0.6))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    locationGranularity == value ? Theme.amber : Color(white: 0.22),
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(locationGranularity == value ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Library section
    //
    // The only way into the archive and the trash. Both screens existed (or,
    // for the trash, were promised by the delete dialog) with no entry point
    // anywhere in the app, which made archiving and deleting irreversible.

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Library")

            VStack(spacing: 0) {
                row {
                    Button { showArchive = true } label: {
                        HStack {
                            Text("Archive")
                                .foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Divider().overlay(.white.opacity(0.08)).padding(.horizontal, 16)
                row {
                    Button { showTrash = true } label: {
                        HStack {
                            Text("Trash")
                                .foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Tutorial section

    private var tutorialSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Tutorial")

            VStack(spacing: 0) {
                row {
                    Text("Show Introduction")
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        dismiss()
                        // Brief delay so the sheet dismisses before the gate fires
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            didOnboard = false
                        }
                    } label: {
                        Text("Restart")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.amber)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Theme.amber.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
            .padding(.horizontal, 20)
        }
    }

    // MARK: - About section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("About")

            VStack(spacing: 0) {
                row {
                    Text("keep.")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("Daily Moments")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.35))
                }
                rowDivider
                row {
                    Text("Version")
                        .foregroundStyle(.white)
                    Spacer()
                    Text(appVersion)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                }
                rowDivider
                row {
                    Text("Made by")
                        .foregroundStyle(.white)
                    Spacer()
                    Text("Kipry")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.amber)
            .tracking(0.8)
            .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func row<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack {
            content()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.07))
            .frame(height: 1)
            .padding(.horizontal, 16)
    }
}
