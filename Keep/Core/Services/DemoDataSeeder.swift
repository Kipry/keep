import Foundation
import SwiftData
import UIKit

// MARK: - Demo data seeder

/// Fills an empty library with realistic-looking history for taking App Store
/// screenshots — never for real users. Compiled only into Debug builds, and
/// even there it only runs when explicitly asked for via a launch argument,
/// so a normal `Cmd-R` during development never triggers it.
///
/// Every clip goes through `VideoComposer.renderStillVideo`, the exact same
/// path a real photo import uses — so what lands on screen (poster, filmstrip,
/// export, widget) is exercising production code, not a shortcut that only
/// looks right.
#if DEBUG
enum DemoDataSeeder {
    /// Pass `-SeedDemoData` in the scheme's "Arguments Passed On Launch" to
    /// populate an empty library on next run. Does nothing if the library
    /// already has any project — this never touches or duplicates real data.
    @MainActor
    static func seedIfRequested(context: ModelContext) async {
        guard CommandLine.arguments.contains("-SeedDemoData") else { return }
        let existing = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        guard existing.isEmpty else { return }
        await seed(context: context)
    }

    @MainActor
    private static func seed(context: ModelContext) async {
        let calendar = Calendar.current
        let composer = VideoComposer()

        func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 20, minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour, minute: minute))!
        }

        // "Alltag" is the everyday backbone — the other three are occasions
        // layered on top, exactly how someone would actually use the app.
        let alltag = Project(name: "Alltag")
        let sommer = Project(name: "Sommer 2026")
        let berge  = Project(name: "Berge")
        let stadt  = Project(name: "Stadtnächte")
        for p in [alltag, sommer, berge, stadt] { context.insert(p) }

        var order: [ObjectIdentifier: Int] = [:]
        func nextOrder(_ p: Project) -> Int {
            let key = ObjectIdentifier(p)
            let n = order[key] ?? 0
            order[key] = n + 1
            return n
        }

        // MARK: Alltag — Feb 16 → Aug 6, ~170 days, real gaps, unbroken final month
        let alltagStart = date(2026, 2, 16)
        let alltagEnd   = date(2026, 8, 6)
        let streakStart = calendar.date(byAdding: .day, value: -30, to: alltagEnd)!
        // Deliberate multi-day gaps — a few sick days, a busy weekend — so the
        // year spiral and diary actually show missed stretches, not a
        // suspiciously perfect record.
        let gapRanges: [ClosedRange<Date>] = [
            date(2026, 3, 2)...date(2026, 3, 5),
            date(2026, 4, 10)...date(2026, 4, 10),
            date(2026, 6, 15)...date(2026, 6, 16)
        ]
        let alltagImages = ["ClipCoffee", "ClipCity", "ClipSunset"]

        var day = alltagStart
        while day <= alltagEnd {
            let inGap = gapRanges.contains { $0.contains(day) }
            let inFinalStreak = day >= streakStart
            let recordToday = inFinalStreak || (!inGap && Double.random(in: 0...1) < 0.82)
            if recordToday {
                let createdAt = calendar.date(
                    bySettingHour: Int.random(in: 17...22), minute: Int.random(in: 0...59),
                    second: 0, of: day
                ) ?? day
                await addSeedClip(
                    image: alltagImages.randomElement()!, to: alltag,
                    order: nextOrder(alltag), createdAt: createdAt,
                    composer: composer, context: context
                )
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }

        // MARK: Sommer 2026 — a beach week, dense, one rest day
        let sommerImages = ["ClipSunset", "ClipCoffee"]
        for d in 10...21 where d != 15 {
            let createdAt = date(2026, 7, d, hour: Int.random(in: 12...19), minute: Int.random(in: 0...59))
            await addSeedClip(
                image: sommerImages.randomElement()!, to: sommer,
                order: nextOrder(sommer), createdAt: createdAt,
                composer: composer, context: context
            )
        }

        // MARK: Berge — a four-day hiking trip, filmed every day
        for d in 22...25 {
            let createdAt = date(2026, 5, d, hour: Int.random(in: 8...18), minute: Int.random(in: 0...59))
            await addSeedClip(
                image: "ClipHike", to: berge,
                order: nextOrder(berge), createdAt: createdAt,
                composer: composer, context: context
            )
        }

        // MARK: Stadtnächte — scattered nights out, a few weeks apart
        let stadtNights: [(Int, Int)] = [(3, 7), (3, 28), (4, 18), (5, 9), (6, 6), (6, 27), (7, 25)]
        let stadtImages = ["ClipCity", "ClipConcert", "ClipSparkler"]
        for (m, d) in stadtNights {
            let createdAt = date(2026, m, d, hour: Int.random(in: 21...23), minute: Int.random(in: 0...59))
            await addSeedClip(
                image: stadtImages.randomElement()!, to: stadt,
                order: nextOrder(stadt), createdAt: createdAt,
                composer: composer, context: context
            )
        }

        try? context.save()
        WidgetDataStore.refresh(context: context)
    }

    /// Mirrors `ProjectDetailView.addPhotoClip`: persists the source image,
    /// renders it to a short still-video so it composes like any real clip,
    /// sets the thumbnail and (for each project's first clip) the cover —
    /// same fields, same order, as an actual import.
    @discardableResult
    @MainActor
    private static func addSeedClip(image: String, to project: Project, order: Int,
                                    createdAt: Date, composer: VideoComposer,
                                    context: ModelContext) async -> Bool {
        guard let uiImage = UIImage(named: image) else { return false }
        let imports = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Imports", isDirectory: true)
        try? FileManager.default.createDirectory(at: imports, withIntermediateDirectories: true)
        let imageURL = imports.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        guard let jpeg = uiImage.jpegData(compressionQuality: 0.92) else { return false }
        guard (try? jpeg.write(to: imageURL)) != nil else { return false }

        let duration = RecordingDuration.options.randomElement() ?? RecordingDuration.golden
        guard let movURL = try? await composer.renderStillVideo(from: imageURL, duration: duration) else {
            try? FileManager.default.removeItem(at: imageURL)
            return false
        }

        let clip = Clip(fileURL: movURL, duration: duration, order: order, createdAt: createdAt)
        clip.isPhoto = true
        clip.photoDuration = duration
        clip.photoSourceURLString = imageURL.absoluteString
        clip.project = project
        project.updatedAt = createdAt
        context.insert(clip)

        if let thumb = downscaled(uiImage, maxEdge: 320).jpegData(compressionQuality: 0.7) {
            clip.thumbnailData = thumb
            if project.activeClips.count == 1 {
                project.coverThumbnailData = downscaled(uiImage, maxEdge: Cover.maxEdge)
                    .jpegData(compressionQuality: Cover.quality)
                project.coverClipID = clip.id
            }
            ClipTone.analyzeIfNeeded(clip)
        }
        return true
    }

    private static func downscaled(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxEdge else { return image }
        let scale = maxEdge / longest
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: newSize).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
#endif
