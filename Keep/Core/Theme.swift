import SwiftUI

// MARK: - Colour tokens

enum Theme {
    // Backgrounds
    static let background  = Color(red: 0.051, green: 0.051, blue: 0.051) // #0D0D0D
    static let filmCard    = Color(red: 0.122, green: 0.122, blue: 0.122) // #1F1F1F
    static let cardSurface = Color(red: 0.133, green: 0.133, blue: 0.133) // #222

    // Warm paper tones
    static let paper    = Color(red: 0.961, green: 0.902, blue: 0.784) // #F5E6C8
    static let cream    = Color(red: 0.929, green: 0.851, blue: 0.639) // #EDD9A3
    static let paperDim = Color(red: 0.878, green: 0.816, blue: 0.682)

    // Accent
    static let amber = Color(red: 0.941, green: 0.529, blue: 0.227) // #F0873A

    // Ink
    static let ink      = Color(red: 0.102, green: 0.102, blue: 0.102) // #1A1A1A
    static let inkSoft  = Color(red: 0.102, green: 0.102, blue: 0.102).opacity(0.45)
    static let inkFaint = Color(red: 0.102, green: 0.102, blue: 0.102).opacity(0.18)
}

// MARK: - Typography
//
// Three-font system matching the Keep / design-canvas spec:
//   .hand   → PatrickHand-Regular   warm, organic display text
//   .mono   → JetBrainsMono-Regular / -Medium  precise data labels
//   .scrawl → Caveat-Medium          decorative / handwritten accents

extension Font {
    /// Patrick Hand — titles, project names, navigation labels, buttons
    static func hand(_ size: CGFloat) -> Font {
        .custom("PatrickHand-Regular", size: size)
    }

    /// JetBrains Mono — clip counts, durations, timestamps, eyebrow labels
    static func mono(_ size: CGFloat, weight: MonoWeight = .regular) -> Font {
        switch weight {
        case .medium:  return .custom("JetBrainsMono-Medium",  size: size)
        case .regular: return .custom("JetBrainsMono-Regular", size: size)
        }
    }

    /// Caveat — decorative / scrawl text ("add to the reel", "+" FAB glyph)
    static func scrawl(_ size: CGFloat) -> Font {
        .custom("Caveat-Medium", size: size)
    }

    enum MonoWeight { case regular, medium }
}

// MARK: - Named type-scale tokens (mirrors wireframe spec)

extension Font {
    static var appWordmark:  Font { .hand(36) }   // "keep."
    static var screenTitle:  Font { .hand(26) }   // project name hero
    static var navTitle:     Font { .hand(22) }   // compact nav header
    static var cardTitle:    Font { .hand(15) }   // name on grid card
    static var handBody:     Font { .hand(18) }   // CTA / button labels
    static var handCaption:  Font { .hand(14) }   // secondary labels

    static var eyebrow:      Font { .mono(10) }   // "YOUR LIBRARY", section labels
    static var monoCaption:  Font { .mono(9)  }   // dates, subtitles
    static var durBadge:     Font { .mono(9,  weight: .medium) }
    static var clipBadge:    Font { .mono(10, weight: .medium) }
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
