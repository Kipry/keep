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

    // MARK: Skip

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

    // MARK: Step content

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

    // MARK: Bottom overlay

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
            Text(step == totalSteps - 1 ? "Let's go" : "Next")
                .font(.hand(21))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    Capsule().fill(Theme.amber)
                )
                .shadow(color: Theme.amber.opacity(0.45), radius: 16, y: 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step layout shell

private struct StepShell<Visual: View>: View {
    let eyebrow: String
    let headline: String
    let subtext: String
    let visual: Visual

    init(eyebrow: String, headline: String, subtext: String, @ViewBuilder visual: () -> Visual) {
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

// MARK: - Amber lens hero

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
            PhoneFrame {
                LockPhaseAnimation()
            }
        }
    }
}

// MARK: - Lock phase animation

private struct LockPhaseAnimation: View {
    @State private var phase = 0

    var body: some View {
        ZStack {
            LockPhase()
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    runCycle()
                }
            }
        }
    }
}

private struct LockPhase: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.08), Color(white: 0.04)],
                startPoint: .top, endPoint: .bottom
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

                Spacer()

                HStack(spacing: 14) {
                    Circle()
                        .fill(Color(white: 0.18))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "cloud.sun.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white.opacity(0.5))
                        )

                    RecWidget(size: 44)

                    Circle()
                        .fill(Color(white: 0.18))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "battery.75")
                                .font(.system(size: 18))
                                .foregroundStyle(.white.opacity(0.5))
                        )
                }

                Spacer().frame(height: 24)

                Text("One tap — record directly")
                    .font(.mono(10))
                    .foregroundStyle(Theme.amber.opacity(0.8))
                    .tracking(1)

                Spacer().frame(height: 32)
            }
        }
    }
}

private struct RecWidget: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.amber, lineWidth: 2)
                .frame(width: size, height: size)

            Circle()
                .fill(Theme.amber.opacity(0.15))
                .frame(width: size, height: size)

            VStack(spacing: 2) {
                Circle()
                    .fill(Theme.amber)
                    .frame(width: size * 0.18, height: size * 0.18)
                Text("REC")
                    .font(.mono(size * 0.2, weight: .medium))
                    .foregroundStyle(Theme.amber)
            }
        }
    }
}

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
                    Circle()
                        .fill(Theme.amber)
                        .frame(width: 80, height: 80)
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
            PhoneFrame {
                ProjectGridMock()
            }
        }
    }
}

private struct ProjectGridMock: View {
    private let gradients: [(Color, Color)] = [
        (Color(red: 0.1, green: 0.2, blue: 0.4),  Color(red: 0.05, green: 0.1, blue: 0.25)),
        (Color(red: 0.35, green: 0.1, blue: 0.1),  Color(red: 0.18, green: 0.05, blue: 0.05)),
        (Color(red: 0.1, green: 0.28, blue: 0.15), Color(red: 0.05, green: 0.14, blue: 0.07)),
        (Color(red: 0.22, green: 0.1, blue: 0.35), Color(red: 0.11, green: 0.05, blue: 0.18))
    ]

    var body: some View {
        ZStack(alignment: .top) {
            Color(white: 0.05)

            VStack(spacing: 0) {
                HStack {
                    Text("keep.")
                        .font(.hand(18))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "plus")
                        .foregroundStyle(Theme.amber)
                }
                .padding(.horizontal, 14)
                .padding(.top, 54)
                .padding(.bottom, 12)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(0..<4, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [gradients[i].0, gradients[i].1],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 90)
                            .overlay(
                                VStack(alignment: .leading, spacing: 3) {
                                    Spacer()
                                    Text(["Holiday", "Daily life", "Workout", "Family"][i])
                                        .font(.hand(12))
                                        .foregroundStyle(.white.opacity(0.9))
                                    Text("\([7, 12, 4, 9][i]) clips")
                                        .font(.mono(8))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            )
                    }
                }
                .padding(.horizontal, 12)
            }
        }
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
            PhoneFrame {
                FilmstripMock()
            }
        }
    }
}

private struct FilmstripMock: View {
    private let clipColors: [Color] = [
        Color(red: 0.1,  green: 0.2,  blue: 0.4),
        Color(red: 0.35, green: 0.1,  blue: 0.1),
        Color(red: 0.1,  green: 0.28, blue: 0.15),
        Color(red: 0.22, green: 0.1,  blue: 0.35),
        Color(red: 0.3,  green: 0.24, blue: 0.06),
        Color(red: 0.06, green: 0.24, blue: 0.28),
        Color(red: 0.18, green: 0.14, blue: 0.32),
        Color(red: 0.22, green: 0.14, blue: 0.06)
    ]

    var body: some View {
        ZStack {
            Color(white: 0.05)

            VStack {
                Spacer()
                VStack(spacing: 14) {
                    FilmstripRow(colors: Array(clipColors.prefix(4)))
                    FilmstripRow(colors: Array(clipColors.suffix(4)))
                }
                .padding(.horizontal, 12)
                Spacer()
            }
        }
    }
}

private struct FilmstripRow: View {
    let colors: [Color]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(white: 0.1))
                .frame(height: 72)

            HStack(spacing: 0) {
                sprocketColumn
                HStack(spacing: 3) {
                    ForEach(0..<colors.count, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(colors[i].opacity(0.85))
                            .frame(height: 56)
                    }
                }
                .padding(.horizontal, 4)
                sprocketColumn
            }
        }
    }

    private var sprocketColumn: some View {
        VStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(white: 0.22))
                    .frame(width: 8, height: 10)
            }
        }
        .padding(.horizontal, 4)
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
            PhoneFrame {
                ExportMock()
            }
        }
    }
}

private struct ExportMock: View {
    @State private var progress: CGFloat = 0
    @State private var displayPercent: Int = 0
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            Color(white: 0.04)

            RadialGradient(
                colors: [Theme.amber.opacity(0.12), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 180
            )

            VStack(spacing: 22) {
                Spacer()

                FilmstripRow(colors: [
                    Color(red: 0.1, green: 0.2, blue: 0.4),
                    Color(red: 0.35, green: 0.1, blue: 0.1),
                    Color(red: 0.1, green: 0.28, blue: 0.15),
                    Color(red: 0.22, green: 0.1, blue: 0.35)
                ])
                .padding(.horizontal, 20)
                .scaleEffect(0.85)

                VStack(spacing: 14) {
                    Text("COMPILING YOUR REEL")
                        .font(.mono(9, weight: .medium))
                        .foregroundStyle(Theme.amber)
                        .tracking(2)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(white: 0.18))
                                .frame(height: 4)
                            Capsule()
                                .fill(Theme.amber)
                                .frame(width: geo.size.width * progress, height: 4)
                        }
                    }
                    .frame(height: 4)
                    .padding(.horizontal, 24)

                    Text("\(displayPercent)%")
                        .font(.mono(22, weight: .medium))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }

                Spacer()
            }
        }
        .onAppear { startExport() }
        .onDisappear { timer?.invalidate() }
    }

    private func startExport() {
        progress = 0
        displayPercent = 0
        timer?.invalidate()
        let duration: CGFloat = 4.0
        let interval: CGFloat = 0.05
        let steps = Int(duration / interval)
        var current = 0
        timer = Timer.scheduledTimer(withTimeInterval: Double(interval), repeats: true) { t in
            current += 1
            let frac = CGFloat(current) / CGFloat(steps)
            progress       = min(frac, 1)
            displayPercent = min(Int(frac * 100), 100)
            if current >= steps {
                t.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { startExport() }
            }
        }
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
            PhoneFrame {
                WidgetSetupMock()
            }
        }
    }
}

private struct WidgetSetupMock: View {
    @State private var glowing = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.09, blue: 0.06), Color(red: 0.05, green: 0.04, blue: 0.03)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Theme.amber.opacity(0.18))
                        .frame(width: 88, height: 88)
                        .blur(radius: glowing ? 14 : 8)
                        .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: glowing)

                    RecWidget(size: 58)
                }

                Spacer().frame(height: 24)

                instructionCard

                Spacer().frame(height: 20)
            }
            .padding(.horizontal, 16)
        }
        .onAppear { glowing = true }
    }

    private var instructionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Theme.amber)
                .frame(height: 2)
                .cornerRadius(1)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(instructionSteps.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Theme.amber)
                                .frame(width: 20, height: 20)
                            Text("\(i + 1)")
                                .font(.mono(9, weight: .medium))
                                .foregroundStyle(Theme.ink)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(instructionSteps[i].0)
                                .font(.hand(14))
                                .foregroundStyle(.white)
                            Text(instructionSteps[i].1)
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
                .fill(Color(white: 0.12).opacity(0.85))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private let instructionSteps: [(String, String)] = [
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

    private var dispW:   CGFloat { screenW * scale }
    private var dispH:   CGFloat { screenH * scale }
    private var frameW:  CGFloat { dispW + bezel * 2 }
    private var frameH:  CGFloat { dispH + bezel * 2 }
    private var corner:  CGFloat { 44 * scale + bezel }

    var body: some View {
        ZStack(alignment: .top) {
            // Bezel
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

            // Screen: content is rendered at full 393×852, scaled to 0.45
            // with topLeading anchor, then the layout frame is collapsed to
            // the scaled size so nothing overflows into the surrounding layout.
            ZStack(alignment: .top) {
                Color.black
                content
                    .frame(width: screenW, height: screenH)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: dispW, height: dispH, alignment: .topLeading)
                // Dynamic Island
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
