import SwiftUI

// MARK: - App tabs

enum AppTab {
    case projects, timeline, today
}

// MARK: - Root view

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppDeepLink.self) private var deepLink
    @State private var selectedTab: AppTab = .projects
    @State private var dragOffset: CGFloat = 0

    private let order: [AppTab] = [.projects, .timeline, .today]

    private var tabIndex: Int { order.firstIndex(of: selectedTab) ?? 0 }

    // All three pages stay mounted in a sliding strip: switching tabs is a pure
    // offset animation — no view is rebuilt mid-slide (the old .id(selectedTab)
    // approach recreated the heavy Diary view during the transition, causing
    // visible hitches) — and every page keeps its scroll/scrub state.
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                Theme.background.ignoresSafeArea()
                HStack(spacing: 0) {
                    ProjectListView().frame(width: w)
                    DiaryTimelineView(isActive: selectedTab == .timeline).frame(width: w)
                    OnThisDayView(isActive: selectedTab == .today).frame(width: w)
                }
                .offset(x: -CGFloat(tabIndex) * w + dragOffset)
                // Pin the 3-page strip's leading edge at x = 0 — a bare 3w-wide
                // HStack would be centered by the ZStack (leading edge at -w).
                .frame(width: w, alignment: .leading)
                // Confine rendering AND hit-testing to the visible window so the
                // off-screen pages can't receive stray touches.
                .clipped()
            }
            .contentShape(Rectangle())
            // Edge-swipe between the main pages. Starting near a screen edge keeps
            // this from clashing with the timeline scrubber and horizontal carousels.
            .simultaneousGesture(edgeSwipe(width: w))
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AppTabBar(selectedTab: selectedTab, onSelect: switchTab)
        }
        .onboardingGate()
        .task {
            #if DEBUG
            await DemoDataSeeder.seedIfRequested(context: modelContext)
            #endif
            ClipFileRepair.run(in: modelContext)
            TrashSweep.run(in: modelContext)
            VideoComposer.purgeExports()
            // Re-renders covers captured at the old 320 px size. One pass per
            // install: afterwards every cover is already large enough.
            await CoverThumbnailRepair.run(in: modelContext)
        }
        // Widget deep link (keep://diary). Handled here rather than in a page,
        // because switching tabs is this view's responsibility.
        .onAppear { consumePendingTab() }
        // Adding a widget means leaving the app and coming back, so this is the
        // moment the hint should disappear.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { WidgetInstallation.shared.refresh() }
        }
        .onChange(of: deepLink.pendingTab) { _, _ in consumePendingTab() }
    }

    private func consumePendingTab() {
        guard let tab = deepLink.pendingTab else { return }
        deepLink.pendingTab = nil
        switchTab(to: tab)
    }

    /// Apple's own minimum recommended touch target (Human Interface
    /// Guidelines) — chosen over the old 30 pt because that read as "must
    /// start exactly at the bezel" in practice. Still narrow enough that the
    /// Diary tab's full-width day scrubber and the Chronicle carousels, which
    /// both read horizontal drags across the whole page, are never touched by
    /// a start point this close to the edge.
    private let edgeZone: CGFloat = 44

    private func edgeSwipe(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { v in
                let fromLeft  = v.startLocation.x < edgeZone
                let fromRight = v.startLocation.x > width - edgeZone
                let dx = v.translation.width
                // Only track intentional horizontal edge drags.
                guard (fromLeft && dx > 0) || (fromRight && dx < 0) else { return }
                guard abs(dx) > abs(v.translation.height) * 0.5 else { return }
                // 1:1 tracking — the neighbouring page follows the finger.
                // Rubber only when dragging past the first/last page.
                let overscroll = (dx > 0 && tabIndex == 0) || (dx < 0 && tabIndex == order.count - 1)
                dragOffset = overscroll ? dx * 0.25 : dx
            }
            .onEnded { v in
                let dx = v.translation.width
                let fromLeft  = v.startLocation.x < edgeZone
                let fromRight = v.startLocation.x > width - edgeZone
                let vx = v.velocity.width
                let fast = (dx < 0 && vx < -500) || (dx > 0 && vx > 500)   // direction-matched flick
                let commit = abs(dx) > abs(v.translation.height) * 1.2
                    && ((dx < 0 && fromRight) || (dx > 0 && fromLeft))
                    && (abs(dx) > width * 0.28 || fast)
                var target: AppTab?
                if commit {
                    let j = tabIndex + (dx < 0 ? 1 : -1)
                    if order.indices.contains(j) { target = order[j] }
                }
                // Tab change and offset reset in ONE transaction: the spring
                // animates continuously from the finger's release position to
                // the destination page — no jump.
                withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                    if let target { selectedTab = target }
                    dragOffset = 0
                }
            }
    }

    private func switchTab(to tab: AppTab) {
        guard tab != selectedTab else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
            selectedTab = tab
            dragOffset = 0
        }
    }
}

// MARK: - Tab bar

private struct AppTabBar: View {
    let selectedTab: AppTab
    let onSelect: (AppTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            tabItem(.projects, icon: "square.grid.2x2",      label: "Projects")
            tabItem(.timeline, icon: "calendar.day.timeline.left", fillIcon: "calendar.day.timeline.left", label: "Diary")
            tabItem(.today,    icon: "sparkles", fillIcon: "sparkles", label: "Chronicle")
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

    // LocalizedStringKey, not String: Text(_: String) is the *verbatim*
    // initialiser, so these labels were baked in as German for every locale —
    // even though the catalog already had the translations.
    private func tabItem(_ tab: AppTab, icon: String, fillIcon: String? = nil,
                         label: LocalizedStringKey) -> some View {
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
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
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
