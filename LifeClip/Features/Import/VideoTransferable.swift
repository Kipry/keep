import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Makes a video selectable via PhotosPicker and copies it into the app sandbox.
/// Copying is required because PHAsset file URLs are ephemeral and disappear
/// after the picker session ends.
struct VideoTransferable: Transferable {
    let url: URL
    let duration: Double

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let destDir = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Imports", isDirectory: true)
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            let destURL = destDir
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")
            try FileManager.default.copyItem(at: received.file, to: destURL)
            let asset = AVURLAsset(url: destURL)
            let duration = try await asset.load(.duration)
            return VideoTransferable(url: destURL, duration: duration.seconds)
        }
    }
}
