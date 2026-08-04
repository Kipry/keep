import SwiftUI

// MARK: - Onboarding root

struct OnboardingView: View {
    @AppStorage("didOnboard") private var didOnboard = false
    @State private var step = 0
    @State private var forward = true

    private let totalSteps = 6

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            RadialGradient(
                colors: [Theme.amber.opacity(0.07), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 420
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    backButton
                    Spacer()
                    skipButton
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

                stepContent
                    .id(step)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                            removal:   .move(edge: forward ? .leading  : .trailing).combined(with: .opacity)
                        )
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            VStack(spacing: 0) {
                Spacer()
                bottomOverlay
            }
            .ignoresSafeArea(edges: .bottom)
        }
        // Swipe left/right anywhere to page through the steps — attached to the
        // root (not stepContent, whose .id(step) identity swap would kill an
        // in-flight gesture). simultaneousGesture + 24pt threshold keeps the
        // Back/Skip/CTA buttons fully tappable.
        .simultaneousGesture(stepSwipe)
    }

    private var stepSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { v in
                let dx = v.translation.width
                guard abs(dx) > 60, abs(dx) > abs(v.translation.height) * 1.2 else { return }
                if dx < 0, step < totalSteps - 1 {   // never completes onboarding
                    forward = true
                    withAnimation(.easeInOut(duration: 0.35)) { step += 1 }
                } else if dx > 0, step > 0 {
                    forward = false
                    withAnimation(.easeInOut(duration: 0.35)) { step -= 1 }
                }
            }
    }

    @ViewBuilder
    private var backButton: some View {
        if step > 0 {
            Button {
                forward = false
                withAnimation(.easeInOut(duration: 0.35)) { step -= 1 }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Back")
                        .font(.mono(11))
                }
                .foregroundStyle(Color(white: 0.45))
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(height: 30)
        }
    }

    @ViewBuilder
    private var skipButton: some View {
        if step < totalSteps - 1 {
            Button {
                forward = true
                withAnimation(.easeInOut(duration: 0.35)) { step = totalSteps - 1 }
            } label: {
                Text("Skip")
                    .font(.mono(11))
                    .foregroundStyle(Color(white: 0.45))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(height: 30)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: StepWelcome()
        case 1: StepLockScreen()
        case 2: StepLibrary()
        case 3: StepFilmstrip()
        case 4: StepExport()
        default: StepWidget()
        }
    }

    private var bottomOverlay: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Theme.background.opacity(0), Theme.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 40)

            VStack(spacing: 20) {
                dotsRow
                ctaButton
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 44)
            .background(Theme.background)
        }
    }

    private var dotsRow: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Capsule()
                    .fill(i == step ? Theme.amber : Color(white: 1, opacity: 0.22))
                    .frame(width: i == step ? 22 : 7, height: 7)
                    .animation(.easeInOut(duration: 0.25), value: step)
            }
        }
    }

    private var ctaButton: some View {
        Button {
            if step == totalSteps - 1 {
                didOnboard = true
            } else {
                forward = true
                withAnimation(.easeInOut(duration: 0.35)) { step += 1 }
            }
        } label: {
            let label: LocalizedStringKey = step == totalSteps - 1 ? "Let's go" : "Next"
            Text(label)
                .font(.hand(21))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Capsule().fill(Theme.amber))
                .shadow(color: Theme.amber.opacity(0.45), radius: 16, y: 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step layout shell

private struct StepShell<Visual: View>: View {
    let eyebrow: LocalizedStringKey
    let headline: LocalizedStringKey
    let subtext: LocalizedStringKey
    let visual: Visual

    init(eyebrow: LocalizedStringKey, headline: LocalizedStringKey, subtext: LocalizedStringKey, @ViewBuilder visual: () -> Visual) {
        self.eyebrow  = eyebrow
        self.headline = headline
        self.subtext  = subtext
        self.visual   = visual()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            visual
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

            Spacer(minLength: 20)

            VStack(alignment: .leading, spacing: 10) {
                Text(eyebrow)
                    .font(.mono(10.5, weight: .medium))
                    .foregroundStyle(Theme.amber)
                    .tracking(2.5)

                Text(headline)
                    .font(.hand(38))
                    .foregroundStyle(.white)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtext)
                    .font(.system(size: 14.5))
                    .foregroundStyle(Color(white: 0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 140)
        }
    }
}

// MARK: - Step 1: Welcome

private struct StepWelcome: View {
    var body: some View {
        StepShell(
            eyebrow:  "WELCOME",
            headline: "Hold the moment.",
            subtext:  "keep. — your life, memory by memory."
        ) {
            VStack(spacing: 46) {
                AmberLens()
                Wordmark(size: 52)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 36)
        }
    }
}

// "keep." wordmark in Patrick Hand (matches the app + design)
private struct Wordmark: View {
    var size: CGFloat = 40
    var body: some View {
        (Text("keep").foregroundStyle(Color.white)
         + Text(".").foregroundStyle(Theme.amber))
            .font(.hand(size))
    }
}

private struct AmberLens: View {
    @State private var floating = false

    private let lensSize: CGFloat = 168

    var body: some View {
        ZStack {
            // three concentric amber rings (border opacity 0.30 / 0.215 / 0.13)
            ForEach(Array([0, 1, 2].enumerated()), id: \.offset) { _, i in
                Circle()
                    .stroke(Theme.amber.opacity(0.30 - Double(i) * 0.085), lineWidth: 2)
                    .frame(width: lensSize, height: lensSize)
                    .scaleEffect(1 + CGFloat(i) * 0.3)
            }

            // amber body — radial highlight from upper area
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.984, green: 0.702, blue: 0.416), // #FBB36A
                            Theme.amber,                                   // #F0873A
                            Color(red: 0.788, green: 0.408, blue: 0.122)   // #C9681F
                        ],
                        center: UnitPoint(x: 0.5, y: 0.30),
                        startRadius: 0,
                        endRadius: lensSize * 0.55
                    )
                )
                .frame(width: lensSize, height: lensSize)
                .shadow(color: Theme.amber.opacity(0.28), radius: lensSize * 0.16, y: lensSize * 0.08)

            // dark glass lens
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.227, green: 0.227, blue: 0.227), Color(white: 0.035)],
                        center: UnitPoint(x: 0.36, y: 0.32),
                        startRadius: 0,
                        endRadius: lensSize * 0.42 * 0.72
                    )
                )
                .frame(width: lensSize * 0.42, height: lensSize * 0.42)

            // amber pupil
            Circle()
                .fill(Theme.amber)
                .frame(width: lensSize * 0.42 * 0.3, height: lensSize * 0.42 * 0.3)
                .shadow(color: Theme.amber.opacity(0.85), radius: lensSize * 0.05)

            // specular highlight
            Circle()
                .fill(.white.opacity(0.85))
                .frame(width: lensSize * 0.10, height: lensSize * 0.10)
                .blur(radius: 2)
                .offset(x: -lensSize * 0.10, y: -lensSize * 0.10)
        }
        .offset(y: floating ? -7 : 0)
        .animation(
            .easeInOut(duration: 3.6).repeatForever(autoreverses: true),
            value: floating
        )
        .onAppear { floating = true }
    }
}

// MARK: - Step 2: Lock screen

private struct StepLockScreen: View {
    var body: some View {
        StepShell(
            eyebrow:  "ONE TAP",
            headline: "Tap. Record.\nDone.",
            subtext:  "Three seconds from the lock screen — then you're back in the moment instead of behind a phone."
        ) {
            PhoneFrame { LockPhaseAnimation() }
        }
    }
}

private struct LockPhaseAnimation: View {
    @State private var phase = 0

    var body: some View {
        ZStack {
            LockScreenMock(showTapRing: true)
                .opacity(phase == 0 ? 1 : 0)
                .animation(.easeInOut(duration: 0.4), value: phase)
            CameraPhase(isActive: phase == 1)
                .opacity(phase == 1 ? 1 : 0)
                .animation(.easeInOut(duration: 0.4), value: phase)
            SuccessPhase(isActive: phase == 2)
                .opacity(phase == 2 ? 1 : 0)
                .animation(.easeInOut(duration: 0.4), value: phase)
        }
        .onAppear { runCycle() }
    }

    // Lock screen (2.1s) → recording (exactly 1s, ring sweeps shut) → done (1.6s).
    private func runCycle() {
        phase = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) {
            withAnimation { phase = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation { phase = 2 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { runCycle() }
            }
        }
    }
}

// MARK: - Shared lock-screen building blocks (match kb-screens.jsx LockFace)

/// Warm amber-tinted lock-screen backdrop (radial glow + dark gradient).
private struct LockBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.141, green: 0.114, blue: 0.086), // #241d16
                    Color(red: 0.047, green: 0.043, blue: 0.039), // #0c0b0a
                    .black
                ],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [Theme.amber.opacity(0.10), .clear],
                center: UnitPoint(x: 0.5, y: 0.16),
                startRadius: 0, endRadius: 300
            )
        }
        .ignoresSafeArea()
    }
}

/// Lock-screen clock — SF Pro Display time over a mono date line.
private struct LockClock: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("SUNDAY · JUNE 7")
                .font(.mono(13))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.55))
            Text("23:07")
                .font(.system(size: 88, weight: .semibold))
                .foregroundStyle(.white)
                .tracking(-3)
        }
    }
}

/// Decoy accessory-circular widgets either side of the REC widget.
private struct CircularDecoy: View {
    enum Kind { case weather, battery }
    let kind: Kind
    var size: CGFloat = 62

    var body: some View {
        ZStack {
            Circle().fill(.white.opacity(0.14))
            switch kind {
            case .weather:
                Image(systemName: "cloud.sun.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color(red: 1, green: 0.84, blue: 0.04))
                    .font(.system(size: 24))
            case .battery:
                VStack(spacing: -1) {
                    Text("85")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                    Text("%")
                        .font(.mono(8))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// accessoryCircular REC widget — amber ring + dot + "REC" over glass.
private struct RecWidget: View {
    var size: CGFloat = 62
    var showTap: Bool = false

    var body: some View {
        ZStack {
            if showTap { TapRingAnimation(size: size) }
            Circle().fill(.white.opacity(0.12))
            Circle().stroke(Theme.amber, lineWidth: 2)
            VStack(spacing: 2) {
                Circle()
                    .fill(Theme.amber)
                    .frame(width: size * 0.16, height: size * 0.16)
                Text("REC")
                    .font(.mono(size * 0.13, weight: .medium))
                    .tracking(0.5)
                    .foregroundStyle(Theme.amber)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Expanding white tap pulse (kbTap: grow + fade out).
private struct TapRingAnimation: View {
    let size: CGFloat
    @State private var animate = false

    var body: some View {
        Circle()
            .stroke(.white.opacity(0.9), lineWidth: 2)
            .frame(width: size + 12, height: size + 12)
            .scaleEffect(animate ? 1.3 : 0.55)
            .opacity(animate ? 0 : 0.85)
            .onAppear {
                withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
                    animate = true
                }
            }
    }
}

// MARK: - Lock screen mock (step 2 · matches LockFace)

private struct LockScreenMock: View {
    var showTapRing: Bool = false

    var body: some View {
        ZStack {
            LockBackground()

            VStack(spacing: 0) {
                LockClock()
                    .padding(.top, 92)

                // accessory widget row (weather · REC · battery)
                HStack(spacing: 16) {
                    CircularDecoy(kind: .weather)
                    RecWidget(size: 62, showTap: showTapRing)
                    CircularDecoy(kind: .battery)
                }
                .padding(.top, 30)

                // pointer caption
                VStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.amber)
                    Text("One tap, and you're recording")
                        .font(.hand(19))
                        .foregroundStyle(.white)
                    Text("STRAIGHT FROM THE LOCK SCREEN")
                        .font(.mono(10))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.45))
                }
                .padding(.top, 18)

                Spacer()

                // lock affordances
                HStack(spacing: 200) {
                    lockAffordance("lock.fill")
                    lockAffordance("camera.fill")
                }
                .padding(.bottom, 40)

                // home indicator
                Capsule()
                    .fill(.white.opacity(0.6))
                    .frame(width: 134, height: 5)
                    .padding(.bottom, 9)
            }
        }
    }

    private func lockAffordance(_ icon: String) -> some View {
        Circle()
            .fill(.white.opacity(0.16))
            .frame(width: 46, height: 46)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
            )
    }
}

// MARK: - Camera recording phase

private struct CameraPhase: View {
    let isActive: Bool
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.06), Color(white: 0.02)],
                startPoint: .top, endPoint: .bottom
            )

            VStack(spacing: 24) {
                Spacer()

                ZStack {
                    Circle()
                        .stroke(Color(white: 0.25), lineWidth: 4)
                        .frame(width: 72, height: 72)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Theme.amber, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 72, height: 72)
                        .rotationEffect(.degrees(-90))
                    Circle()
                        .fill(Color.red)
                        .frame(width: 36, height: 36)
                }

                // Mirrors the real picker rather than a hardcoded list — this
                // showed three options where the app has four, and marked the
                // wrong one as selected.
                HStack(spacing: 20) {
                    ForEach(RecordingDuration.options, id: \.self) { d in
                        Text(verbatim: RecordingDuration.label(d))
                            .font(.mono(11))
                            .foregroundStyle(d == RecordingDuration.standard
                                             ? Theme.amber : Color(white: 0.35))
                    }
                }

                Spacer()
            }
        }
        // All phases stay mounted (they cross-fade via opacity), so onAppear
        // fires only once — the ring must restart from zero each time this
        // phase becomes visible, sweeping shut in the default duration.
        .onChange(of: isActive) { _, active in
            if active {
                progress = 0
                withAnimation(.linear(duration: RecordingDuration.standard)) { progress = 1 }
            } else {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { progress = 0 }
            }
        }
    }
}

private struct SuccessPhase: View {
    let isActive: Bool
    @State private var popped = false

    private var badge: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.984, green: 0.702, blue: 0.416),
                            Theme.amber,
                            Color(red: 0.788, green: 0.408, blue: 0.122)
                        ],
                        center: UnitPoint(x: 0.5, y: 0.3),
                        startRadius: 0, endRadius: 70
                    )
                )
                .frame(width: 124, height: 124)
                .shadow(color: Theme.amber.opacity(0.4), radius: 28, y: 14)
            Image(systemName: "checkmark")
                .font(.system(size: 52, weight: .bold))
                .foregroundStyle(Color(red: 0.10, green: 0.07, blue: 0.02))
        }
        .scaleEffect(popped ? 1 : 0.8)
    }

    var body: some View {
        ZStack {
            LockBackground()
            VStack(spacing: 0) {
                badge
                Text("Done.")
                    .font(.hand(38))
                    .foregroundStyle(.white)
                    .padding(.top, 28)
                Text("Three seconds. Phone back in your pocket.")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                    .padding(.horizontal, 40)
            }
        }
        // Replays the badge pop every cycle (onAppear only fires once because
        // the phases stay mounted and cross-fade via opacity).
        .onChange(of: isActive) { _, active in
            if active {
                popped = false
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { popped = true }
            } else {
                popped = false
            }
        }
    }
}

// MARK: - Step 3: Library

private struct StepLibrary: View {
    var body: some View {
        StepShell(
            eyebrow:  "LIBRARY",
            headline: "Your story.",
            subtext:  "Holidays, workouts, ordinary days — each one adds a clip."
        ) {
            PhoneFrame { ProjectGridMock() }
        }
    }
}

// MARK: - Project grid mock (matches actual ProjectListView exactly)

private struct ProjectGridMock: View {
    private let cards: [(name: LocalizedStringKey, clips: Int, date: String, image: String)] = [
        ("Summer 2026",  7, "Jun 20, 2026", "ClipSunset"),
        ("Daily life",  12, "Jun 19, 2026", "ClipCoffee"),
        ("City Nights",  4, "Jun 17, 2026", "ClipCity"),
        ("Mountains",    9, "Jun 15, 2026", "ClipHike")
    ]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Theme.background

            VStack(spacing: 0) {
                // Header — mirrors ProjectListView
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("YOUR LIBRARY")
                                .font(.mono(10))
                                .tracking(2)
                                .foregroundStyle(.white.opacity(0.35))
                            Text("keep.")
                                .font(.hand(36))
                                .foregroundStyle(.white)
                        }
                        Spacer()
                        Circle()
                            .fill(.white.opacity(0.1))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                            )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 64)
                .padding(.bottom, 24)

                // 2-column grid — matches ProjectListView grid + ProjectCard
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                    spacing: 14
                ) {
                    ForEach(cards.indices, id: \.self) { i in
                        let c = cards[i]
                        ZStack(alignment: .topTrailing) {
                            ZStack(alignment: .bottomLeading) {
                                Image(c.image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 196)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))

                                LinearGradient(
                                    colors: [.clear, .black.opacity(0.72)],
                                    startPoint: .center,
                                    endPoint: .bottom
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 14))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.name)
                                        .font(.hand(15))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                    Text(c.date)
                                        .font(.mono(9))
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                                .padding(10)
                            }

                            Text("\(c.clips)")
                                .font(.mono(10, weight: .medium))
                                .foregroundStyle(Theme.paper)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.black.opacity(0.55), in: Capsule())
                                .overlay(Capsule().stroke(Theme.paper.opacity(0.4), lineWidth: 1))
                                .padding(8)
                        }
                    }
                }
                .padding(.horizontal, 24)

                Spacer()
            }

            // Amber FAB — mirrors ProjectListView FAB
            Circle()
                .fill(Theme.amber)
                .frame(width: 58, height: 58)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.ink)
                )
                .shadow(color: Theme.amber.opacity(0.5), radius: 12, y: 4)
                .padding(.trailing, 20)
                .padding(.bottom, 92)

            // Tab bar — mirrors AppTabBar
            VStack {
                Spacer()
                MockTabBar(activeTab: 0)
            }
        }
    }
}

// MARK: - Mock tab bar (matches actual AppTabBar capsule)

private struct MockTabBar: View {
    let activeTab: Int

    // Icons and labels must track ContentView's real tab bar — this mock
    // used to promise an "Archive" and a "Today" tab that don't exist. The
    // label is a LocalizedStringKey, not a String: Text(String) is the
    // verbatim initialiser, so these never localised.
    private let items: [(String, String, LocalizedStringKey)] = [
        ("square.grid.2x2",             "square.grid.2x2.fill",         "Projects"),
        ("calendar.day.timeline.left",  "calendar.day.timeline.left",   "Diary"),
        ("sparkles",                    "sparkles",                     "Memories")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                let item = items[i]
                let active = i == activeTab
                VStack(spacing: 4) {
                    Image(systemName: active ? item.1 : item.0)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(active ? Theme.ink : .white.opacity(0.4))
                        .frame(width: 52, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(active ? Theme.amber : .clear)
                        )
                    Text(item.2)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(active ? Theme.amber : .white.opacity(0.35))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Theme.cardSurface.opacity(0.95))
                .overlay(Capsule().stroke(.white.opacity(0.08), lineWidth: 1))
        )
        .padding(.horizontal, 40)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Step 4: Filmstrip

private struct StepFilmstrip: View {
    var body: some View {
        StepShell(
            eyebrow:  "FILMSTRIP",
            headline: "Your cut.\nFrame by frame.",
            subtext:  "Trim, sort, rearrange your clips.\nJust like a real film strip."
        ) {
            PhoneFrame { FilmstripMock() }
        }
    }
}

// MARK: - Filmstrip mock (matches actual ProjectDetailView)

private struct FilmstripMock: View {
    private let rowImages: [[String]] = [
        ["ClipSunset", "ClipHike", "ClipCity", "ClipCoffee"],
        ["ClipConcert", "ClipSparkler", "ClipSunset", "ClipCity"]
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background

            VStack(spacing: 0) {
                // Nav bar — mirrors ProjectDetailView navBar
                HStack(alignment: .center) {
                    Text("‹")
                        .font(.hand(28))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)

                    VStack(spacing: 2) {
                        Text("Summer 2026")
                            .font(.hand(22))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("7 CLIPS · 21s")
                            .font(.mono(9))
                            .tracking(0.5)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity)

                    HStack(spacing: 2) {
                        Circle()
                            .fill(.white.opacity(0.1))
                            .frame(width: 32, height: 32)
                            .overlay(Image(systemName: "play.fill").font(.system(size: 12)).foregroundStyle(.white))
                        Circle()
                            .fill(.white.opacity(0.1))
                            .frame(width: 32, height: 32)
                            .overlay(Image(systemName: "plus").font(.system(size: 15, weight: .bold)).foregroundStyle(.white))
                    }
                    .frame(width: 100, alignment: .trailing)
                }
                .padding(.horizontal, 16)
                .padding(.top, 60)
                .padding(.bottom, 12)

                // Filmstrip rows + "add" button
                VStack(spacing: 12) {
                    ForEach(rowImages.indices, id: \.self) { i in
                        MockFilmstripRow(images: rowImages[i])
                    }

                    Text("+ add to the film")
                        .font(.scrawl(22))
                        .foregroundStyle(.white.opacity(0.25))
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: 1.4, dash: [6]))
                        )
                        .padding(.horizontal, 14)
                }
                .padding(.top, 4)

                Spacer()
            }

            // Camera FAB
            HStack {
                Spacer()
                Circle()
                    .fill(Theme.amber)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: "camera.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                    )
                    .shadow(color: Theme.amber.opacity(0.45), radius: 14, y: 4)
                    .padding(.trailing, 22)
                    .padding(.bottom, 132)
            }

            // Export bar — mirrors ProjectDetailView exportBar
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "film.stack")
                    Text("Make the film · Export")
                        .font(.hand(18))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Theme.amber, in: RoundedRectangle(cornerRadius: 14))

                Text("7 CLIPS → 1 VIDEO · ~21s")
                    .font(.mono(9))
                    .foregroundStyle(.white.opacity(0.3))
                    .tracking(0.5)
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background(
                LinearGradient(
                    colors: [Theme.background.opacity(0), Theme.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}

// MARK: - Mock filmstrip row (matches real FilmstripRow structure)

private struct MockFilmstripRow: View {
    let images: [String]

    var body: some View {
        VStack(spacing: 0) {
            sprocketHoles
            HStack(spacing: 5) {
                ForEach(images.indices, id: \.self) { i in
                    Color.clear
                        .aspectRatio(4/5, contentMode: .fit)
                        .overlay(
                            Image(images[i])
                                .resizable()
                                .scaledToFill()
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
                let pad = 4 - min(images.count, 4)
                ForEach(0..<pad, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.04))
                        .aspectRatio(4/5, contentMode: .fit)
                }
            }
            .padding(.horizontal, 6)
            sprocketHoles
        }
        .background(Theme.filmCard)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 14)
    }

    private var sprocketHoles: some View {
        HStack(spacing: 0) {
            ForEach(0..<18, id: \.self) { _ in
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.background)
                    .frame(width: 8, height: 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }
}

// MARK: - Step 5: Export

private struct StepExport: View {
    var body: some View {
        StepShell(
            eyebrow:  "EXPORT",
            headline: "Clips in.\nVideo out.",
            subtext:  "One tap, and all your clips become a single film."
        ) {
            PhoneFrame { ExportMock() }
        }
    }
}

// MARK: - Export mock (matches actual ExportProgressOverlay)

private struct ExportMock: View {
    @State private var progress: CGFloat = 0
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            Color.black.opacity(0.95)

            RadialGradient(
                colors: [Theme.amber.opacity(0.12), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 200
            )
            .frame(width: 400, height: 400)

            VStack(spacing: 52) {
                MockExportFilmStrip()

                VStack(spacing: 22) {
                    Text("COMPILING YOUR VIDEO")
                        .font(.mono(10))
                        .tracking(3)
                        .foregroundStyle(.white.opacity(0.38))

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.1))
                                .frame(height: 3)
                            Capsule()
                                .fill(Theme.amber)
                                .frame(width: geo.size.width * progress, height: 3)
                                .shadow(color: Theme.amber.opacity(0.8), radius: 6)
                        }
                    }
                    .frame(height: 3)

                    Text("\(Int(progress * 100))%")
                        .font(.hand(52))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
                .padding(.horizontal, 40)
            }
        }
        .onAppear { startExport() }
        .onDisappear { timer?.invalidate() }
    }

    private func startExport() {
        progress = 0
        timer?.invalidate()
        var elapsed = 0.0
        let total = 4.0
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { t in
            elapsed += 0.05
            progress = min(CGFloat(elapsed / total), 1)
            if elapsed >= total {
                t.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.startExport() }
            }
        }
    }
}

// MARK: - Mock export film strip (matches actual ExportProgressOverlay filmStrip)

private struct MockExportFilmStrip: View {
    private let images: [String] = [
        "ClipSunset", "ClipConcert", "ClipHike", "ClipCity", "ClipSparkler"
    ]

    var body: some View {
        VStack(spacing: 0) {
            sprocketRow
            HStack(spacing: 3) {
                ForEach(images.indices, id: \.self) { i in
                    Image(images[i])
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 80)
                        .clipped()
                }
            }
            .padding(.horizontal, 6)
            sprocketRow
        }
        .background(Theme.filmCard)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 20)
    }

    private var sprocketRow: some View {
        HStack(spacing: 4) {
            ForEach(0..<14, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.background)
                    .frame(width: 8, height: 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
    }
}

// MARK: - Step 6: Widget setup

private struct StepWidget: View {
    var body: some View {
        StepShell(
            eyebrow:  "YOUR TRIGGER",
            headline: "Put the REC button\non your lock screen.",
            subtext:  "Add it once — after that, every recording is one tap away."
        ) {
            PhoneFrame { WidgetSetupMock() }
        }
    }
}

// MARK: - Widget setup mock (lock screen + glowing REC + instruction card)

private struct WidgetSetupMock: View {
    @State private var glowing = false
    @State private var floating = false

    var body: some View {
        ZStack {
            LockBackground()

            VStack(spacing: 0) {
                LockClock()
                    .padding(.top, 92)

                // accessory row — REC widget glows + gently floats
                HStack(spacing: 16) {
                    CircularDecoy(kind: .weather)
                    ZStack {
                        Circle()
                            .fill(Theme.amber.opacity(glowing ? 0.20 : 0))
                            .frame(width: 82, height: 82)
                            .blur(radius: 7)
                        RecWidget(size: 62)
                    }
                    .offset(y: floating ? -5 : 0)
                    CircularDecoy(kind: .battery)
                }
                .padding(.top, 30)

                Spacer()

                instructionCard
                    .frame(width: 330)
                    .padding(.bottom, 30)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { glowing = true }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { floating = true }
        }
    }

    @ViewBuilder
    private func stepRow(_ index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Theme.amber).frame(width: 22, height: 22)
                Text("\(index + 1)")
                    .font(.mono(11, weight: .medium))
                    .foregroundStyle(Theme.ink)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(steps[index].0)
                    .font(.hand(17))
                    .foregroundStyle(.white)
                Text(steps[index].1)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private var instructionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("HOW TO SET IT UP")
                .font(.mono(10))
                .tracking(2)
                .foregroundStyle(Theme.amber)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(steps.indices, id: \.self) { i in stepRow(i) }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(white: 0.07).opacity(0.86))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.amber.opacity(0.3), lineWidth: 1))
        )
    }

    private let steps: [(LocalizedStringKey, LocalizedStringKey)] = [
        ("Long-press the lock screen", "Tap “Customize”"),
        ("Add a widget",               "Choose keep. from the list"),
        ("Place the REC circle",        "Done — 1 tap to record")
    ]
}

// MARK: - Phone frame

private struct PhoneFrame<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private let screenW: CGFloat = 393
    private let screenH: CGFloat = 852
    private let scale:   CGFloat = 0.45
    private let bezel:   CGFloat = 7

    private var dispW:  CGFloat { screenW * scale }
    private var dispH:  CGFloat { screenH * scale }
    private var frameW: CGFloat { dispW + bezel * 2 }
    private var frameH: CGFloat { dispH + bezel * 2 }
    private var corner: CGFloat { 44 * scale + bezel }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: corner)
                .fill(LinearGradient(
                    colors: [Color(white: 0.22), Color(white: 0.10)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .overlay {
                    RoundedRectangle(cornerRadius: corner)
                        .stroke(.white.opacity(0.15), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.55), radius: 20, y: 10)
                .frame(width: frameW, height: frameH)

            ZStack(alignment: .top) {
                Color.black
                content
                    .frame(width: screenW, height: screenH)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: dispW, height: dispH, alignment: .topLeading)
                Capsule()
                    .fill(.black)
                    .frame(width: 124 * scale, height: 36 * scale)
                    .padding(.top, 13 * scale)
            }
            .frame(width: dispW, height: dispH)
            .clipShape(RoundedRectangle(cornerRadius: 44 * scale))
            .offset(y: bezel)
        }
        .frame(width: frameW, height: frameH)
    }
}
