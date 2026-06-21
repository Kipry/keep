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
                skipButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
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
            headline: "Hold the moment.\nBefore it's gone.",
            subtext:  "keep. — your life, one clip at a time."
        ) {
            AmberLens()
                .frame(height: 300)
        }
    }
}

private struct AmberLens: View {
    @State private var floating = false

    var body: some View {
        ZStack {
            ForEach([CGFloat(1.6), 1.3, 1.0], id: \.self) { scale in
                Circle()
                    .stroke(Theme.amber.opacity(scale == 1.0 ? 0.30 : scale == 1.3 ? 0.22 : 0.13), lineWidth: 1.5)
                    .frame(width: 160, height: 160)
                    .scaleEffect(scale)
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.984, green: 0.702, blue: 0.416),
                            Color(red: 0.941, green: 0.529, blue: 0.227),
                            Color(red: 0.788, green: 0.408, blue: 0.122)
                        ],
                        center: UnitPoint(x: 0.5, y: 0.3),
                        startRadius: 0,
                        endRadius: 80
                    )
                )
                .frame(width: 160, height: 160)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.18), Color(white: 0.07)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 52
                    )
                )
                .frame(width: 108, height: 108)

            Circle()
                .fill(Theme.amber)
                .frame(width: 8, height: 8)

            Circle()
                .fill(.white.opacity(0.55))
                .frame(width: 10, height: 10)
                .offset(x: -18, y: -16)
                .blur(radius: 2)

            Text("keep.")
                .font(.hand(20))
                .foregroundStyle(.white.opacity(0.9))
                .offset(y: 88)
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
            eyebrow:  "THE LOCK SCREEN TRIGGER",
            headline: "One tap.\nRecorded.",
            subtext:  "From the lock screen straight into recording — the app stays closed."
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
            CameraPhase()
                .opacity(phase == 1 ? 1 : 0)
                .animation(.easeInOut(duration: 0.4), value: phase)
            SuccessPhase()
                .opacity(phase == 2 ? 1 : 0)
                .animation(.easeInOut(duration: 0.4), value: phase)
        }
        .onAppear { runCycle() }
    }

    private func runCycle() {
        phase = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) {
            withAnimation { phase = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) {
                withAnimation { phase = 2 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { runCycle() }
            }
        }
    }
}

// MARK: - Shared lock screen mock (steps 2 & 6)

private struct LockScreenMock: View {
    var showTapRing: Bool = false
    var highlightWidget: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.07, blue: 0.04),
                    Color(red: 0.051, green: 0.051, blue: 0.051),
                    Color(red: 0.04, green: 0.05, blue: 0.07)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 4) {
                    Text("SONNTAG · 7. JUNI")
                        .font(.mono(11))
                        .foregroundStyle(.white.opacity(0.55))
                        .tracking(1.5)
                    Text("23:07")
                        .font(.custom("PatrickHand-Regular", size: 64))
                        .foregroundStyle(.white)
                }

                Spacer().frame(height: 36)

                HStack(spacing: 14) {
                    glassCircle(icon: "cloud.sun.fill")

                    ZStack {
                        if highlightWidget {
                            Circle()
                                .fill(Theme.amber.opacity(0.22))
                                .frame(width: 72, height: 72)
                                .blur(radius: 12)
                        }
                        if showTapRing || highlightWidget {
                            TapRingAnimation(size: 48)
                        }
                        RecWidget(size: 48)
                    }

                    glassCircle(icon: "battery.75")
                }

                Spacer().frame(height: 20)

                Text("One tap — record directly")
                    .font(.mono(10))
                    .foregroundStyle(Theme.amber.opacity(0.8))
                    .tracking(1)

                Spacer().frame(height: 32)
            }
        }
    }

    private func glassCircle(icon: String) -> some View {
        Circle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 48, height: 48)
            .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.5))
            )
    }
}

private struct TapRingAnimation: View {
    let size: CGFloat
    @State private var scale: CGFloat = 1.0
    @State private var opacity: CGFloat = 0.6

    var body: some View {
        Circle()
            .stroke(Theme.amber.opacity(0.5), lineWidth: 1.5)
            .frame(width: size * 1.75, height: size * 1.75)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
                    scale = 2.1
                    opacity = 0
                }
            }
    }
}

// MARK: - REC widget (glass style, matches HTML design)

private struct RecWidget: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: size, height: size)
            Circle()
                .stroke(Theme.amber, lineWidth: 2)
                .frame(width: size, height: size)
            VStack(spacing: 2) {
                Circle()
                    .fill(Theme.amber)
                    .frame(width: size * 0.18, height: size * 0.18)
                Text("REC")
                    .font(.mono(size * 0.20, weight: .medium))
                    .foregroundStyle(Theme.amber)
            }
        }
    }
}

// MARK: - Camera recording phase

private struct CameraPhase: View {
    @State private var elapsed: CGFloat = 0
    @State private var timer: Timer?

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
                        .trim(from: 0, to: min(elapsed / 3, 1))
                        .stroke(Theme.amber, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 72, height: 72)
                        .rotationEffect(.degrees(-90))
                    Circle()
                        .fill(Color.red)
                        .frame(width: 36, height: 36)
                }

                HStack(spacing: 28) {
                    ForEach(["1s", "3s", "5s"], id: \.self) { label in
                        Text(label)
                            .font(.mono(11))
                            .foregroundStyle(label == "3s" ? Theme.amber : Color(white: 0.35))
                    }
                }

                Spacer()
            }
        }
        .onAppear {
            elapsed = 0
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                elapsed = min(elapsed + 0.05, 3)
                if elapsed >= 3 { timer?.invalidate() }
            }
        }
        .onDisappear { timer?.invalidate() }
    }
}

private struct SuccessPhase: View {
    var body: some View {
        ZStack {
            Color(white: 0.04)
            VStack(spacing: 16) {
                ZStack {
                    Circle().fill(Theme.amber).frame(width: 80, height: 80)
                    Image(systemName: "checkmark")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
                Text("Done.")
                    .font(.hand(38))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Step 3: Library

private struct StepLibrary: View {
    var body: some View {
        StepShell(
            eyebrow:  "LIBRARY",
            headline: "Every experience.\nIts own project.",
            subtext:  "Holiday, daily life, workout — all clips from one day in one place."
        ) {
            PhoneFrame { ProjectGridMock() }
        }
    }
}

// MARK: - Project grid mock (matches actual ProjectListView exactly)

private struct ProjectGridMock: View {
    private let cards: [(name: LocalizedStringKey, clips: Int, date: String, top: Color, bot: Color)] = [
        ("Summer 2026",  7, "Jun 20, 2026",
         Color(red: 0.1,  green: 0.2,  blue: 0.4),  Color(red: 0.05, green: 0.1,  blue: 0.25)),
        ("Daily life",  12, "Jun 19, 2026",
         Color(red: 0.35, green: 0.1,  blue: 0.1),  Color(red: 0.18, green: 0.05, blue: 0.05)),
        ("Workout",      4, "Jun 17, 2026",
         Color(red: 0.1,  green: 0.28, blue: 0.15), Color(red: 0.05, green: 0.14, blue: 0.07)),
        ("Family",       9, "Jun 15, 2026",
         Color(red: 0.22, green: 0.1,  blue: 0.35), Color(red: 0.11, green: 0.05, blue: 0.18))
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
                                LinearGradient(
                                    colors: [c.top, c.bot],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
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

    private let items: [(String, String, String)] = [
        ("square.grid.2x2", "square.grid.2x2.fill", "Projects"),
        ("archivebox",       "archivebox.fill",       "Archive"),
        ("sparkles",         "sparkles",              "Today")
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
                .fill(Color(white: 0.1).opacity(0.95))
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
            headline: "Your day.\nFrame by frame.",
            subtext:  "Trim, sort, rearrange — just like a real film strip."
        ) {
            PhoneFrame { FilmstripMock() }
        }
    }
}

// MARK: - Filmstrip mock (matches actual ProjectDetailView)

private struct FilmstripMock: View {
    private let rowColors: [[Color]] = [
        [
            Color(red: 0.1,  green: 0.2,  blue: 0.4),
            Color(red: 0.35, green: 0.1,  blue: 0.1),
            Color(red: 0.1,  green: 0.28, blue: 0.15),
            Color(red: 0.22, green: 0.1,  blue: 0.35)
        ],
        [
            Color(red: 0.3,  green: 0.24, blue: 0.06),
            Color(red: 0.06, green: 0.24, blue: 0.28),
            Color(red: 0.18, green: 0.14, blue: 0.32),
            Color(red: 0.22, green: 0.14, blue: 0.06)
        ]
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
                    ForEach(rowColors.indices, id: \.self) { i in
                        MockFilmstripRow(colors: rowColors[i])
                    }

                    Text("+ add to the reel")
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
                    Text("Wind the reel · Export")
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
    let colors: [Color]

    var body: some View {
        VStack(spacing: 0) {
            sprocketHoles
            HStack(spacing: 5) {
                ForEach(colors.indices, id: \.self) { i in
                    colors[i]
                        .overlay(
                            Image(systemName: "film")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.15))
                        )
                        .aspectRatio(4/5, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
                let pad = 4 - min(colors.count, 4)
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
            subtext:  "Wind the reel — a finished video in seconds."
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
                    Text("COMPILING YOUR REEL")
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
    private let colors: [Color] = [
        Color(red: 0.1,  green: 0.2,  blue: 0.4),
        Color(red: 0.35, green: 0.1,  blue: 0.1),
        Color(red: 0.1,  green: 0.28, blue: 0.15),
        Color(red: 0.22, green: 0.1,  blue: 0.35),
        Color(red: 0.3,  green: 0.24, blue: 0.06)
    ]

    var body: some View {
        VStack(spacing: 0) {
            sprocketRow
            HStack(spacing: 3) {
                ForEach(colors.indices, id: \.self) { i in
                    colors[i]
                        .frame(width: 60, height: 80)
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
            subtext:  "The most powerful feature: a lock screen widget that takes you from moment to recording in 3 seconds. No unlocking, no opening."
        ) {
            PhoneFrame { WidgetSetupMock() }
        }
    }
}

// MARK: - Widget setup mock (lock screen + glowing REC + instruction card)

private struct WidgetSetupMock: View {
    @State private var glowing = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.07, blue: 0.04),
                    Color(red: 0.051, green: 0.051, blue: 0.051),
                    Color(red: 0.04, green: 0.05, blue: 0.07)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 4) {
                    Text("SONNTAG · 7. JUNI")
                        .font(.mono(11))
                        .foregroundStyle(.white.opacity(0.55))
                        .tracking(1.5)
                    Text("23:07")
                        .font(.custom("PatrickHand-Regular", size: 64))
                        .foregroundStyle(.white)
                }

                Spacer().frame(height: 36)

                HStack(spacing: 14) {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 48, height: 48)
                        .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                        .overlay(Image(systemName: "cloud.sun.fill").font(.system(size: 20)).foregroundStyle(.white.opacity(0.5)))

                    ZStack {
                        Circle()
                            .fill(Theme.amber.opacity(glowing ? 0.28 : 0.12))
                            .frame(width: 76, height: 76)
                            .blur(radius: glowing ? 16 : 8)
                        TapRingAnimation(size: 48)
                        RecWidget(size: 48)
                    }

                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 48, height: 48)
                        .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                        .overlay(Image(systemName: "battery.75").font(.system(size: 20)).foregroundStyle(.white.opacity(0.5)))
                }

                Spacer().frame(height: 28)

                instructionCard
                    .padding(.horizontal, 24)

                Spacer().frame(height: 28)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                glowing = true
            }
        }
    }

    private var instructionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Theme.amber)
                .frame(height: 2)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(steps.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 10) {
                        ZStack {
                            Circle().fill(Theme.amber).frame(width: 20, height: 20)
                            Text("\(i + 1)")
                                .font(.mono(9, weight: .medium))
                                .foregroundStyle(Theme.ink)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(steps[i].0)
                                .font(.hand(14))
                                .foregroundStyle(.white)
                            Text(steps[i].1)
                                .font(.system(size: 11))
                                .foregroundStyle(Color(white: 0.45))
                        }
                    }
                }
            }
            .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.1))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.14), lineWidth: 1))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private let steps: [(LocalizedStringKey, LocalizedStringKey)] = [
        ("Long-press the lock screen", "Tap 'Customise'"),
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
