import Foundation
import SwiftData

/// Repairs Clip file references that point at a stale sandbox container path.
///
/// Every recorded/imported file is stored as an *absolute* URL, which bakes
/// in the app's container UUID at record time. That UUID changes whenever
/// the app is reinstalled under a different bundle identifier (e.g. after a
/// rename) or its container is manually transferred to a new install — the
/// old absolute path then points nowhere, even though the file itself was
/// carried over unchanged. This scans for clips whose file is missing and
/// relinks them to the same path relative to "Documents/" inside the
/// *current* container, if a file exists there.
enum ClipFileRepair {
    static func run(in context: ModelContext) {
        guard let clips = try? context.fetch(FetchDescriptor<Clip>()) else { return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var didChange = false

        for clip in clips {
            if !clip.isAvailable, let relocated = relocate(clip.fileURLString, under: docs) {
                clip.setFile(relocated)
                didChange = true
            }
            if let photoString = clip.photoSourceURLString, !exists(photoString),
               let relocated = relocate(photoString, under: docs) {
                clip.photoSourceURLString = relocated.absoluteString
                didChange = true
            }
        }

        if didChange { try? context.save() }
    }

    private static func exists(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private static func relocate(_ absoluteString: String, under docs: URL) -> URL? {
        guard let range = absoluteString.range(of: "/Documents/") else { return nil }
        let relative = String(absoluteString[range.upperBound...])
        let candidate = docs.appendingPathComponent(relative)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }
}
