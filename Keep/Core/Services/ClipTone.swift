import SwiftUI
import UIKit

// MARK: - Film palette

/// The sixteen tones every day on the year spiral is snapped to.
///
/// Raw dominant colours from phone clips are mostly desaturated interior
/// browns and greys — plotted straight, a year reads as mud. Quantising to a
/// fixed film-stock palette turns near-identical days into the *same* tone, so
/// the spiral shows areas and seasonal drift instead of 365 shades of sludge.
/// Warm greys, beige, olive, smoke blue, rust.
enum FilmPalette {
    static let tones: [UInt32] = [
        0x33302C, 0x413B35, 0x514840, 0x61544A,
        0x71614F, 0x83705A, 0x948069, 0xA4907A,
        0x5A6157, 0x4A5A56, 0x465868, 0x5D6E80,
        0x8A5D45, 0xB0764A, 0xCB8C4E, 0xDCAB6C
    ]

    /// Stand-in for a day that has clips but whose tone couldn't be derived —
    /// a mid grey from the palette, so the day still reads as recorded.
    static let neutral: UInt32 = 0x514840

    static func color(_ packed: UInt32) -> Color {
        Color(red:   Double((packed >> 16) & 0xFF) / 255,
              green: Double((packed >> 8)  & 0xFF) / 255,
              blue:  Double( packed        & 0xFF) / 255)
    }

    /// Average colour of a thumbnail, snapped to the nearest palette tone.
    static func tone(forThumbnail data: Data) -> UInt32? {
        guard let rgb = averageColor(of: data) else { return nil }
        return snap(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    /// Nearest tone by luminance-weighted distance, after a saturation lift.
    /// Without the lift every interior day lands on the same two greys.
    static func snap(red: CGFloat, green: CGFloat, blue: CGFloat) -> UInt32 {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(red: red, green: green, blue: blue, alpha: 1)
            .getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        var r: CGFloat = 0, g: CGFloat = 0, bl: CGFloat = 0
        UIColor(hue: h, saturation: min(0.72, s * 1.6 + 0.03), brightness: b, alpha: 1)
            .getRed(&r, green: &g, blue: &bl, alpha: &a)

        var best = tones[0]
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for tone in tones {
            let tr = CGFloat((tone >> 16) & 0xFF) / 255
            let tg = CGFloat((tone >> 8)  & 0xFF) / 255
            let tb = CGFloat( tone        & 0xFF) / 255
            // Luminance weights, not plain RGB — closer to how the eye judges it.
            let d = 0.3 * pow(tr - r, 2) + 0.59 * pow(tg - g, 2) + 0.11 * pow(tb - bl, 2)
            if d < bestDistance { bestDistance = d; best = tone }
        }
        return best
    }

    /// Draws the thumbnail into a single pixel and reads it back. The average
    /// rather than a true dominant-colour histogram: for a 3-second clip it is
    /// far cheaper, and the palette snap that follows does the real work.
    private static func averageColor(of data: Data) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                    data: base, width: 1, height: 1,
                    bitsPerComponent: 8, bytesPerRow: 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        return (CGFloat(pixel[0]) / 255, CGFloat(pixel[1]) / 255, CGFloat(pixel[2]) / 255)
    }
}

// MARK: - ClipTone

/// Derives and caches each clip's palette tone.
///
/// Quantising happens once, when the thumbnail exists, and the result is
/// persisted on the clip. The spiral must never touch 365 images while drawing.
///
/// Not actor-isolated, matching `TrashSweep` and `ClipFileRepair`: every entry
/// point is a synchronous main-thread call from a view, and a global actor here
/// would only force `await` into places that can't have it.
enum ClipTone {

    /// No-op once the clip has been analysed. A clip whose thumbnail hasn't
    /// arrived yet is deliberately left un-analysed so it gets picked up on the
    /// next pass rather than being written off as tone-less forever.
    static func analyzeIfNeeded(_ clip: Clip) {
        guard !clip.toneAnalyzed, let data = clip.thumbnailData else { return }
        clip.toneHex = FilmPalette.tone(forThumbnail: data).map { Int($0) }
        clip.toneAnalyzed = true
    }

    /// Tone for a whole day: the first clip of that day that has one.
    ///
    /// Analyses as it goes, which doubles as the backfill for clips recorded
    /// before tones existed — and stops at the first hit, so a day costs one
    /// decode rather than one per clip. A day that has clips always gets a
    /// colour, falling back to the neutral tone, so an unreadable thumbnail
    /// can't make a recorded day read as empty.
    static func dayTone(_ clips: [Clip]) -> Color? {
        guard !clips.isEmpty else { return nil }
        for clip in clips {
            analyzeIfNeeded(clip)
            if let hex = clip.toneHex { return FilmPalette.color(UInt32(hex)) }
        }
        return FilmPalette.color(FilmPalette.neutral)
    }
}
