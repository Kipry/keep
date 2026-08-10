import SwiftUI

// MARK: - Setup sheet

/// The lock-screen widget instructions, at a size you can actually read.
///
/// The onboarding already carries these three steps, but inside a `PhoneFrame`
/// that renders at `scale = 0.45` — the heading lands at 4.5 pt and the detail
/// lines at 5.2 pt. That is decoration, not instruction: there is nothing for
/// the eye to catch on, so people tap straight past the most important feature
/// in the app. This is the same content at full size, reachable from the
/// library card and from Settings.
struct WidgetSetupSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [(LocalizedStringKey, LocalizedStringKey)] = [
        ("Long-press the lock screen", "Tap “Customize”"),
        ("Add a widget",               "Choose keep. from the list"),
        ("Place the REC circle",       "Done — 1 tap to record")
    ]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 26) {
                        Text("One tap on your lock screen starts a recording — no unlocking, no hunting for the app. It takes about twenty seconds to set up, once.")
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(alignment: .leading, spacing: 20) {
                            ForEach(steps.indices, id: \.self) { i in stepRow(i) }
                        }
                    }
                    .padding(.horizontal, Layout.gutter)
                    .padding(.top, 4)
                    .padding(.bottom, 40)
                }
                Button { dismiss() } label: {
                    Text("Got it")
                        .font(.hand(21))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Capsule().fill(Theme.amber))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Layout.gutter)
                .padding(.bottom, 34)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        ScreenHeader(eyebrow: Text("YOUR TRIGGER"), title: "Set Up the Widget") {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 32, height: 32)
                    .background(Theme.control, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, Layout.headerTop)
        .padding(.bottom, 22)
    }

    private func stepRow(_ index: Int) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(Theme.amber).frame(width: 26, height: 26)
                Text(verbatim: "\(index + 1)")
                    .font(.mono(13, weight: .medium))
                    .foregroundStyle(Theme.ink)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(steps[index].0)
                    .font(.hand(21))
                    .foregroundStyle(.white)
                Text(steps[index].1)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Library card

/// Dismissible prompt shown in the library while no widget is installed.
///
/// It answers to `WidgetInstallation`, so it never appears for someone who
/// already has one and vanishes as soon as they add one — and once dismissed it
/// stays dismissed. Deliberately a card in the flow rather than a modal: the
/// widget is worth pointing at, not worth interrupting for.
struct WidgetHintCard: View {
    @AppStorage("didDismissWidgetHint") private var didDismiss = false
    @State private var showSheet = false

    private let installation = WidgetInstallation.shared

    var body: some View {
        if !didDismiss && !installation.hasWidget {
            // The × is a *sibling* of the card button, not an overlay on top of
            // it. A button nested inside another button's hit region never gets
            // the tap — the outer one claims it — so the close control used to
            // open the sheet instead of dismissing the card.
            ZStack(alignment: .topTrailing) {
                Button { showSheet = true } label: { cardBody }
                    .buttonStyle(.plain)

                Button { withAnimation(.easeOut(duration: 0.2)) { didDismiss = true } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .sheet(isPresented: $showSheet) { WidgetSetupSheet() }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var cardBody: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Theme.amber)
                .frame(width: 10, height: 10)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                Text("The fastest way to a clip")
                    .font(.hand(18))
                    .foregroundStyle(.white)
                Text("Put the REC button on your lock screen. One tap, and you're recording.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Text("SHOW ME HOW")
                    .font(.mono(9, weight: .medium))
                    .tracking(1.4)
                    .foregroundStyle(Theme.amber)
                    .padding(.top, 4)
            }
            // Room for the × so it never sits on top of the text.
            Spacer(minLength: 30)
        }
        .padding(14)
        .background(Theme.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(Theme.amber.opacity(0.28), lineWidth: 1))
        .contentShape(Rectangle())
    }
}
