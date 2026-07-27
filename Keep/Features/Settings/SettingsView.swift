import SwiftUI
import UIKit

struct SettingsView: View {
    @AppStorage("defaultRecordingDuration") private var defaultDuration: Double = 1.0
    @AppStorage("locationGranularity") private var locationGranularity = "place"
    // Key must match ClipAudioLevels.defaultsKey — spelled out here because a
    // property initialiser can't reach a main-actor-isolated static.
    @AppStorage("levelAudio") private var levelAudio = true
    @AppStorage("didOnboard") private var didOnboard = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var showArchive = false
    @State private var showTrash = false
    @State private var showMailFallback = false

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
                    audioSection
                    locationSection
                    librarySection
                    tutorialSection
                    aboutSection
                    feedbackSection
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
                stackedRow("Default Duration") {
                    ForEach([1.0, 2.0, 3.0, 5.0], id: \.self) { d in
                        Button { defaultDuration = d } label: {
                            Text(verbatim: "\(Int(d))s")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(defaultDuration == d ? Theme.ink : .white.opacity(0.6))
                                .frame(width: 44, height: 32)
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
            .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Audio section

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Audio")

            VStack(spacing: 0) {
                stackedRow("Match Volume") {
                    levellingButton("On",  value: true)
                    levellingButton("Off", value: false)
                }
                rowDivider
                row {
                    Text("Clips recorded weeks apart rarely sound equally loud. This evens them out during playback and export — quiet clips are lifted, loud ones held back. Your recordings themselves stay untouched.")
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

    private func levellingButton(_ label: LocalizedStringKey, value: Bool) -> some View {
        Button { levelAudio = value } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(levelAudio == value ? Theme.ink : .white.opacity(0.6))
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(
                    levelAudio == value ? Theme.amber : Color(white: 0.22),
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(levelAudio == value ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Location section

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Location")

            VStack(spacing: 0) {
                stackedRow("Save Location") {
                    granularityButton("Precise", value: "precise")
                    granularityButton("Nearby",  value: "place")
                    granularityButton("Off",     value: "off")
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
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(locationGranularity == value ? Theme.ink : .white.opacity(0.6))
                .padding(.horizontal, 12)
                .frame(height: 32)
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

    // MARK: - Feedback section

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Feedback")

            VStack(spacing: 0) {
                row {
                    Button { sendFeedback() } label: {
                        HStack {
                            Text("Send Feedback")
                                .foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "envelope")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.amber)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                rowDivider
                row {
                    Text("Opens your mail app with a message addressed to us. Your app and device version are filled in — they're what makes a bug report actionable.")
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
        .alert("No mail account", isPresented: $showMailFallback) {
            Button("Copy Address") { UIPasteboard.general.string = Self.feedbackAddress }
            Button("OK", role: .cancel) {}
        } message: {
            Text("This device has no mail account set up. Write to \(Self.feedbackAddress) from wherever you like.")
        }
    }

    private static let feedbackAddress = "keep.dailymoments@gmail.com"

    /// Hands the whole message off to the mail app pre-addressed. `mailto:`
    /// rather than `MFMailComposeViewController` on purpose: the composer needs
    /// a configured Mail account specifically, while `mailto:` reaches whatever
    /// mail client the user actually uses.
    private func sendFeedback() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Self.feedbackAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: "keep. Feedback"),
            URLQueryItem(name: "body", value: "\n\n—\n\(deviceSummary)")
        ]
        guard let url = components.url else { showMailFallback = true; return }
        openURL(url) { accepted in
            if !accepted { showMailFallback = true }
        }
    }

    /// Version and hardware, appended so a report arrives with the context that
    /// otherwise takes three emails to establish.
    private var deviceSummary: String {
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "—"
        return "keep. \(appVersion) (\(build)) · iOS \(UIDevice.current.systemVersion) · \(Self.deviceModel)"
    }

    /// Marketing names aren't available to apps, so this is the hardware
    /// identifier ("iPhone17,1") — still enough to tell the devices apart.
    private static var deviceModel: String {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { raw in
            raw.prefix { $0 != 0 }.map { Character(UnicodeScalar($0)) }
        }
        let name = String(machine)
        return name.isEmpty ? "unknown" : name
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

    /// Label above, segmented control below.
    ///
    /// Side by side, the German labels plus three or four segments overflow the
    /// card on a standard phone: "Genau" wrapped to "Gena / u" and the whole
    /// row looked broken. Stacking gives the segments the full card width, so
    /// the layout holds for any translation — and for the fourth duration
    /// segment this screen just gained.
    private func stackedRow<Content: View>(_ title: LocalizedStringKey,
                                           @ViewBuilder segments: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                segments()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.07))
            .frame(height: 1)
            .padding(.horizontal, 16)
    }
}
