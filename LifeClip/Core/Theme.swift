import SwiftUI

enum Theme {
    // Backgrounds
    static let background  = Color(red: 0.051, green: 0.051, blue: 0.051) // #0D0D0D
    static let filmCard    = Color(red: 0.122, green: 0.122, blue: 0.122) // #1F1F1F — film strip bg
    static let cardSurface = Color(red: 0.133, green: 0.133, blue: 0.133) // #222

    // Warm paper tones (used on export cards)
    static let paper  = Color(red: 0.961, green: 0.902, blue: 0.784) // #F5E6C8
    static let cream  = Color(red: 0.929, green: 0.851, blue: 0.639) // #EDD9A3
    static let paperDim = Color(red: 0.878, green: 0.816, blue: 0.682) // slightly darker paper

    // Accent
    static let amber = Color(red: 0.941, green: 0.529, blue: 0.227) // #F0873A

    // Ink
    static let ink      = Color(red: 0.102, green: 0.102, blue: 0.102) // #1A1A1A
    static let inkSoft  = Color(red: 0.102, green: 0.102, blue: 0.102).opacity(0.45)
    static let inkFaint = Color(red: 0.102, green: 0.102, blue: 0.102).opacity(0.18)
}
