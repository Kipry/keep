import SwiftUI
import SwiftData

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
    /// Owned here, not in the library, because the button that raises it now
    /// sits in the tab row — which belongs to this view.
    @State private var isCreatingProject = false

    private let order: [AppTab] = [.projects, .timeline, .today]

    private var tabIndex: Int { order.firstIndex(of: selectedTab) ?? 0 }

    // All three pages stay mounted in a sliding strip: switching tabs is a pure
    // offset animation — no view is rebuilt mid-slide (the old .id(selectedTab)
    // approach recreated the heavy Diary view during the transition, causing
    // visible hitches) — and every page keeps its scroll/scrub state.
    var body: some View {
        ZStack {
            // Sits OUTSIDE the GeometryReader below on purpose. A
            // GeometryReader that doesn't ignore the safe area confines its
            // *content* to that same safe area too — no .ignoresSafeArea()
            // a child makes further down can ever paint past the reader's
            // own bounds. That reader has to stay safe-area-aware (each
            // page's own header positioning depends on it), so the only way
            // for a background to actually reach the true top edge is to
            // sit outside it entirely. DiaryTimelineView hit this exact
            // pattern one level down already; this was the same bug one
            // level up, hiding behind it.
            Theme.background.ignoresSafeArea()
            // The warm glow Diary wants reaching the top edge, drawn here for
            // the same reason. It lives here and nowhere else: Diary used to
            // paint its own background over this one, which — being stuck
            // inside the reader below — covered the glow everywhere except
            // the status bar and so drew the very band this is meant to
            // remove.
            if selectedTab == .timeline {
                RadialGradient(colors: [Theme.amber.opacity(0.13), .clear],
                               center: .init(x: 0.5, y: 0.0), startRadius: 0, endRadius: 420)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            GeometryReader { geo in
                let w = geo.size.width
                ZStack {
                    HStack(spacing: 0) {
                        ProjectListView(isCreatingProject: $isCreatingProject).frame(width: w)
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
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AppTabBar(
                selectedTab: selectedTab,
                onSelect: switchTab,
                // The button belongs to the library, so it only exists there.
                showsCreate: selectedTab == .projects,
                onCreate: { isCreatingProject = true }
            )
        }
        .onboardingGate()
        .task {
            ClipFileRepair.run(in: modelContext)
            TrashSweep.run(in: modelContext)
            VideoComposer.purgeExports()
            // Re-renders covers captured at the old 320 px size. One pass per
            // install: afterwards every cover is already large enough.
            await CoverThumbnailRepair.run(in: modelContext)
        }
        // Deliberately its own task, and no longer part of the startup chain
        // above. A launch coming straight out of the Lock Screen camera is the
        // one launch where this has real work to do — copying a file, reading a
        // duration, rendering a thumbnail — and sitting in the middle of the
        // startup sequence it held everything after it, on the launch least
        // able to afford it. Nothing else here depends on its result.
        //
        // It runs for the lifetime of the app rather than once: the session
        // directory is often handed over a moment *after* the app is already on
        // screen, so a single read finds nothing and the clip only turns up on
        // the next launch. `.initial` covers whatever was already waiting,
        // `.added` covers whatever lands later.
        .task {
            if #available(iOS 18.0, *) {
                await LockedCaptureContextWriter.refresh(context: modelContext)
                await LockedCaptureImporter.observeUpdates(context: modelContext)
            }
        }
        // Widget deep link (keep://diary). Handled here rather than in a page,
        // because switching tabs is this view's responsibility.
        .onAppear { consumePendingTab() }
        // Adding a widget means leaving the app and coming back, so this is the
        // moment the hint should disappear.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            WidgetInstallation.shared.refresh()
            // Every return to the foreground is a possible "just unlocked
            // after recording from the Lock Screen" — the .task above only
            // covers a cold launch. Refreshing the app context here too keeps
            // the destination the Lock Screen shows in step with a project
            // renamed or created since.
            if #available(iOS 18.0, *) {
                Task {
                    await LockedCaptureImporter.importPending(context: modelContext)
                    await LockedCaptureContextWriter.refresh(context: modelContext)
                }
            }
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

/// The tab pill and, on the library, the new-project button beside it.
///
/// The button used to float above this row as a second amber circle. Two round
/// orange things stacked on top of each other, neither explaining the other —
/// so it moved into the row: same height, same radius, same baseline, one
/// object instead of two.
///
/// Three tabs leave enough room for the narrower pill. A fourth would not: at
/// that point either the labels go or the button moves up into the header.
/// Deliberately not built for in advance.
// MARK: - Create project button

/// The new-project action, sized to sit flush beside the tab pill.
///
/// Drawn rather than taken from SF Symbols: the design calls for a 2.6pt
/// stroke at 40% of the button's width, and `Image(systemName: "plus")` only
/// approaches that through a font weight — close on one size, wrong on the
/// next. A path is the same shape whatever the button measures.
private struct CreateProjectButton: View {
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            ZStack {
                Circle().fill(Theme.amber)
                Plus()
                    .stroke(Theme.ink, style: StrokeStyle(lineWidth: 3.6, lineCap: .round))
                    .frame(width: size * 0.4, height: size * 0.4)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(PressStyle())
        .contentShape(Circle())
        .accessibilityLabel("New Project")
        .accessibilityAddTraits(.isButton)
    }

    /// The press state comes from the button itself rather than a gesture laid
    /// over it — a second gesture on top of a Button competes with the tap it
    /// is supposed to be decorating.
    private struct PressStyle: ButtonStyle {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func makeBody(configuration: Configuration) -> some View {
            let pressed = configuration.isPressed
            // No shadow. An amber glow was the design, but the button's width
            // is animated, and animating a width means clipping to it — which
            // cut the glow into a square with visible corners. A flat disc in a
            // flat row is also simply cleaner.
            return configuration.label
                // Reduce Motion still gets an answer to the press, just a
                // brightening instead of a spring.
                .brightness(reduceMotion && pressed ? 0.08 : 0)
                .scaleEffect(reduceMotion ? 1 : (pressed ? 0.94 : 1))
                .animation(.spring(response: 0.26, dampingFraction: 0.7), value: pressed)
        }
    }

    /// Drawn rather than taken from SF Symbols: the design calls for a 2.6pt
    /// stroke at 40% of the button's width, and `Image(systemName: "plus")`
    /// only approaches that through a font weight — close at one size, wrong
    /// at the next. A path is the same shape whatever the button measures.
    private struct Plus: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return p
        }
    }
}

private struct AppTabBar: View {
    let selectedTab: AppTab
    let onSelect: (AppTab) -> Void
    let showsCreate: Bool
    let onCreate: () -> Void

    /// Measured from the pill rather than hardcoded, so the button stays
    /// exactly as tall however the labels grow under Dynamic Type. Seeded with
    /// the value it settles on, so the first frame is already right.
    @State private var barHeight: CGFloat = 66

    private var motion: Animation { .spring(response: 0.34, dampingFraction: 0.85) }

    var body: some View {
        HStack(spacing: 0) {
            tabPill
            // Width, not insertion: growing from nothing pushes the pill open
            // and pulls it shut again, which is the same movement in both
            // directions. An inserted view would pop.
            // Smaller than the pill it sits next to: matching its height made
            // the button read as the heaviest thing on the screen. The row
            // keeps the pill's height, so the disc simply centres in it and
            // nothing below shifts.
            let createSize = barHeight * 0.8
            CreateProjectButton(size: createSize, action: onCreate)
                .frame(width: showsCreate ? createSize : 0, height: barHeight)
                .opacity(showsCreate ? 1 : 0)
                .clipped()
                .padding(.leading, showsCreate ? 8 : 0)
                .allowsHitTesting(showsCreate)
        }
        .animation(motion, value: showsCreate)
        .padding(.horizontal, 40)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
    }

    private var tabPill: some View {
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
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
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
                    // Amber at 16%, with the icon carrying the colour instead
                    // of sitting on it. Full saturation appears once per screen,
                    // and down here that is now the create button — an active
                    // tab competing with it would make neither read as primary.
                    .foregroundStyle(isActive ? Theme.amber : .white.opacity(0.4))
                    .frame(width: 52, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(isActive ? Theme.amber.opacity(0.16) : .clear)
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
