import SwiftUI
import UIKit

// MARK: - Colour tokens

enum Theme {
    // Backgrounds
    static let background  = Color(red: 0.051, green: 0.051, blue: 0.051) // #0D0D0D
    static let filmCard    = Color(red: 0.122, green: 0.122, blue: 0.122) // #1F1F1F
    /// Settings rows, stat cards, streak card — the raised surface on top of
    /// `background`. Previously spelled `Color(white: 0.1)` at a dozen sites
    /// while two other card greys (0.122, 0.133) shipped alongside it.
    static let cardSurface = Color(white: 0.1)

    // Warm paper tones
    static let paper = Color(red: 0.961, green: 0.902, blue: 0.784) // #F5E6C8
    static let cream = Color(red: 0.929, green: 0.851, blue: 0.639) // #EDD9A3

    // Accent
    static let amber = Color(red: 0.941, green: 0.529, blue: 0.227) // #F0873A

    // Ink
    static let ink = Color(red: 0.102, green: 0.102, blue: 0.102) // #1A1A1A

    // Chrome
    /// Circular icon-button background. Was five different greys for the same
    /// affordance (0.12 / 0.14 / 0.16 / 0.18 / white at 10%).
    static let control = Color(white: 0.14)
    /// Hairline around cards and controls.
    static let hairline = Color.white.opacity(0.07)
}

// MARK: - Typography
//
// Font system matching the Keep / design-canvas spec:
//   .hand     → SF Pro Display, bold    feature titles, project names, nav labels, buttons
//   .mono     → JetBrainsMono-Regular / -Medium  precise data labels
//   .wordmark → Bricolage Grotesque ExtraBold    the "keep." logotype — nowhere else
//
// Patrick Hand and Caveat (the former `.hand` and `.scrawl`) read as childish
// and lost legibility at small sizes; both are gone from the bundle entirely,
// not just swapped out here.

// The custom fonts (`.mono`, `.wordmark`) are built with `relativeTo:` — the
// two-argument `Font.custom(_:size:)` produces a fixed point size that ignores
// Dynamic Type entirely, which used to leave most of the app's text
// unscalable for anyone who enlarges it. `.hand` reaches for the same
// guarantee on a *system* font via `UIFontMetrics`, since SwiftUI has no
// `Font.system(size:relativeTo:)` — `UIFontMetrics.scaledFont(for:)` is the
// mechanism `Font.custom(_:size:relativeTo:)` uses internally, just reached
// through UIKit here.
extension Font {
    /// Bold system display text — titles, project names, navigation labels, buttons.
    static func hand(_ size: CGFloat) -> Font {
        let base = UIFont.systemFont(ofSize: size, weight: .bold)
        return Font(UIFontMetrics(forTextStyle: uiTextStyle(for: size)).scaledFont(for: base))
    }

    /// JetBrains Mono — clip counts, durations, timestamps, eyebrow labels
    static func mono(_ size: CGFloat, weight: MonoWeight = .regular) -> Font {
        let style = textStyle(for: size)
        switch weight {
        case .medium:  return .custom("JetBrainsMono-Medium",  size: size, relativeTo: style)
        case .regular: return .custom("JetBrainsMono-Regular", size: size, relativeTo: style)
        }
    }

    /// Bricolage Grotesque ExtraBold — the "keep." wordmark, and only the wordmark.
    static func wordmark(_ size: CGFloat) -> Font {
        .custom("BricolageGrotesque-ExtraBold", size: size, relativeTo: textStyle(for: size))
    }

    /// `~-0.02em` tracking for `.hand` text, per the type spec. Font carries no
    /// tracking of its own in SwiftUI — this pairs with `.tracking(_:)` on the
    /// `Text` itself; a size, not a `Font`, is the return type for that reason.
    static func handTracking(for size: CGFloat) -> CGFloat { -0.02 * size }

    /// Anchors each size to the nearest system text style so it scales at a
    /// sensible rate — small captions grow less than headlines, as they do in
    /// system typography.
    private static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11:  return .caption2
        case ..<13:  return .caption
        case ..<15:  return .footnote
        case ..<17:  return .subheadline
        case ..<20:  return .body
        case ..<24:  return .title3
        case ..<30:  return .title2
        default:     return .title
        }
    }

    /// Same ladder as `textStyle(for:)`, in `UIFont.TextStyle` terms — `.hand`
    /// scales through `UIFontMetrics`, which speaks UIKit's style type rather
    /// than SwiftUI's `Font.TextStyle`.
    private static func uiTextStyle(for size: CGFloat) -> UIFont.TextStyle {
        switch size {
        case ..<11:  return .caption2
        case ..<13:  return .caption1
        case ..<15:  return .footnote
        case ..<17:  return .subheadline
        case ..<20:  return .body
        case ..<24:  return .title3
        case ..<30:  return .title2
        default:     return .title1
        }
    }

    enum MonoWeight { case regular, medium }
}

// MARK: - Named type-scale tokens (mirrors wireframe spec)

extension Font {
    static var pageTitle:    Font { .hand(32) }   // tab-level screen title
    static var appWordmark:  Font { .wordmark(36) }   // "keep."
    static var navTitle:     Font { .hand(22) }   // compact nav header
    static var cardTitle:    Font { .hand(15) }   // name on grid card
    static var handBody:     Font { .hand(18) }   // CTA / button labels

    static var eyebrow:      Font { .mono(10) }   // "YOUR LIBRARY", section labels
    static var monoCaption:  Font { .mono(9)  }   // dates, subtitles
    static var durBadge:     Font { .mono(9,  weight: .medium) }
    static var clipBadge:    Font { .mono(10, weight: .medium) }
}

// MARK: - Screen layout

/// Shared geometry for the top-level tabs. Centralised because Library, Diary
/// and Memories had drifted to three different gutters and header offsets,
/// which showed up as the title jumping when swiping between tabs.
enum Layout {
    /// Horizontal inset for all top-level screens.
    static let gutter: CGFloat = 24
    /// Gap between the safe-area top and the header block.
    static let headerTop: CGFloat = 20
}

// MARK: - Shared screen header

/// The eyebrow + title block every tab shows at the top, with an optional
/// trailing control. Takes `Text` rather than strings so callers keep their
/// own localisation and can pass a formatted date as the eyebrow.
struct ScreenHeader<Trailing: View>: View {
    let eyebrow: Text
    let title: Text
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                eyebrow
                    .font(.eyebrow)
                    .tracking(2.5)
                    .foregroundStyle(.white.opacity(0.35))
                title
                    .font(.pageTitle)
                    .tracking(Font.handTracking(for: 32))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(eyebrow: Text, title: Text) {
        self.init(eyebrow: eyebrow, title: title) { EmptyView() }
    }
}

// MARK: - Shared controls
//
// These existed two to four times each with small divergences. The diary's
// zoom picker and its Time/Places switch were character-for-character
// identical apart from the binding, and the TODAY chip was duplicated verbatim
// between the timeline and the map.

/// One segment of a pill selector. Wrap a row of them in `.segmentedTrack()`.
struct SegmentButton: View {
    let label: LocalizedStringKey
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.mono(11, weight: isOn ? .medium : .regular))
                .tracking(0.3)
                .foregroundStyle(isOn ? Theme.ink : .white.opacity(0.55))
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(isOn ? Theme.amber : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

extension View {
    /// The recessed track a row of `SegmentButton`s sits in.
    func segmentedTrack() -> some View {
        padding(3)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
    }
}

/// Amber outline chip — "TODAY", "EMPTY" and friends.
struct AmberChip: View {
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.mono(11))
                .tracking(1)
                .foregroundStyle(Theme.amber)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.amber.opacity(0.12), in: Capsule())
                .overlay(Capsule().stroke(Theme.amber.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Circular icon button — the app's close/action affordance.
struct CircleIconButton: View {
    let systemName: String
    let label: LocalizedStringKey
    var size: CGFloat = 32
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: size, height: size)
                .background(Theme.control, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Scroll edge fade

extension View {
    /// Softly dissolves scrolling content at the top edge so it fades out
    /// underneath a pinned header instead of hitting a hard cut-off line.
    /// Apply to the ScrollView itself; the fade stays fixed to its frame.
    func topEdgeFade(height: CGFloat = 32) -> some View {
        mask(
            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: height)
                Color.black
            }
        )
    }
}
