import SwiftUI

// MARK: - App tabs

enum AppTab {
    case projects, archive, timeline, today
}

// MARK: - Root view

struct ContentView: View {
    @State private var selectedTab: AppTab = .projects

    var body: some View {
        Group {
            switch selectedTab {
            case .projects: ProjectListView()
            case .archive:  ArchiveView()
            case .timeline: DiaryTimelineView()
            case .today:    OnThisDayView()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AppTabBar(selectedTab: $selectedTab)
        }
        .onboardingGate()
    }
}

// MARK: - Tab bar

private struct AppTabBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 0) {
            tabItem(.projects, icon: "square.grid.2x2",      label: "Projekte")
            tabItem(.archive,  icon: "archivebox",            label: "Archiv")
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
            withAnimation(.easeInOut(duration: 0.18)) { selectedTab = tab }
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
