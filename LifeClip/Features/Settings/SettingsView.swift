import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultRecordingDuration") private var defaultDuration: Double = 1.0
    @Environment(\.dismiss) private var dismiss

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    recordingSection
                    aboutSection
                }
                .padding(.top, 60)
                .padding(.bottom, 60)
            }
        }
        .preferredColorScheme(.dark)
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
                    .background(Color(white: 0.18), in: Circle())
            }
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
                        }
                    }
                }
            }
            .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.07), lineWidth: 1))
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
            .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.07), lineWidth: 1))
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
