import SwiftUI

// MARK: - App tabs

enum AppTab {
    case projects, timeline, today
}

// MARK: - Root view

struct ContentView: View {
    @State private var selectedTab: AppTab = .projects
    @State private var slideForward = true

    private let order: [AppTab] = [.projects, .timeline, .today]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.background.ignoresSafeArea()
                page
                    .id(selectedTab)
                    .transition(.asymmetric(
                        insertion: .move(edge: slideForward ? .trailing : .leading),
                        removal:   .move(edge: slideForward ? .leading : .trailing)
                    ))
            }
            .contentShape(Rectangle())
            // Edge-swipe between the main pages. Starting near a screen edge keeps
            // this from clashing with the timeline scrubber and horizontal carousels.
            .simultaneousGesture(edgeSwipe(width: geo.size.width))
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AppTabBar(selectedTab: selectedTab, onSelect: switchTab)
        }
        .onboardingGate()
    }

    @ViewBuilder
    private var page: some View {
        switch selectedTab {
        case .projects: ProjectListView()
        case .timeline: DiaryTimelineView()
        case .today:    OnThisDayView()
        }
    }

    private func edgeSwipe(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .global)
            .onEnded { v in
                let dx = v.translation.width, dy = v.translation.height
                guard abs(dx) > 60, abs(dx) > abs(dy) * 1.4 else { return }
                let fromLeft  = v.startLocation.x < 30
                let fromRight = v.startLocation.x > width - 30
                if dx < 0 && fromRight { step(1) }        // swipe ← from right edge → next
                else if dx > 0 && fromLeft { step(-1) }   // swipe → from left edge → previous
            }
    }

    private func step(_ delta: Int) {
        guard let i = order.firstIndex(of: selectedTab) else { return }
        let j = i + delta
        guard j >= 0, j < order.count else { return }
        switchTab(to: order[j])
    }

    private func switchTab(to tab: AppTab) {
        guard tab != selectedTab,
              let from = order.firstIndex(of: selectedTab),
              let to   = order.firstIndex(of: tab) else { return }
        slideForward = to > from
        withAnimation(.easeInOut(duration: 0.28)) { selectedTab = tab }
    }
}

// MARK: - Tab bar

private struct AppTabBar: View {
    let selectedTab: AppTab
    let onSelect: (AppTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            tabItem(.projects, icon: "square.grid.2x2",      label: "Projekte")
            tabItem(.timeline, icon: "calendar.day.timeline.left", fillIcon: "calendar.day.timeline.left", label: "Tagebuch")
            tabItem(.today,    icon: "sparkles", fillIcon: "sparkles", label: "Heute")
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

    private func tabItem(_ tab: AppTab, icon: String, fillIcon: String? = nil, label: String) -> some View {
        let isActive = selectedTab == tab
        let activeIcon = fillIcon ?? (icon + ".fill")
        return Button {
            onSelect(tab)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: isActive ? activeIcon : icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isActive ? Theme.ink : .white.opacity(0.4))
                    .frame(width: 52, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(isActive ? Theme.amber : .clear)
                    )
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isActive ? Theme.amber : .white.opacity(0.35))
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.18), value: selectedTab)
    }
}

// MARK: - Onboarding gate

extension View {
    func onboardingGate() -> some View {
        modifier(OnboardingGateModifier())
    }
}

private struct OnboardingGateModifier: ViewModifier {
    @AppStorage("didOnboard") private var didOnboard = false
    func body(content: Content) -> some View {
        if didOnboard { content } else { OnboardingView() }
    }
}
