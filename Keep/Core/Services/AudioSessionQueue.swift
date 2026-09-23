import AVFoundation

// MARK: - Audio session queue

/// The one place the shared audio session is changed.
///
/// `setCategory` and `setActive` block until the system has reconfigured audio
/// routing, which can take long enough to stall a frame — Xcode flags every call
/// made from the main thread for exactly that. Apple's non-blocking
/// `activate`/`deactivate(options:completionHandler:)` would be the answer, but
/// both arrive in iOS 27, and this app runs from iOS 18.
///
/// So the blocking calls move here instead — and into a *serial* queue, which
/// is the part that actually matters. The camera and every playback surface
/// share a single `AVAudioSession`. Moved off the main thread independently, a
/// preview's deactivation could land after the camera had already switched to
/// recording, and switch the session off underneath it: a clip with no sound,
/// which is a bug this app has had before. One queue means changes happen in
/// the order they were asked for, whoever asked.
///
/// Once the minimum target reaches iOS 27, the completion-handler API can
/// replace the blocking calls inside here without anything outside changing.
enum AudioSessionQueue {
    private static let queue = DispatchQueue(label: "keep.audio-session", qos: .userInitiated)

    /// Queues a change and returns immediately. For changes nothing waits on —
    /// ending playback, releasing the session after recording.
    static func enqueue(_ work: @escaping @Sendable () -> Void) {
        queue.async(execute: work)
    }

    /// Queues a change and suspends until it has been applied. For the camera,
    /// which cannot start capturing until the session is set up for recording —
    /// still off the main thread, still in order behind anything queued before.
    static func perform(_ work: @escaping @Sendable () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            queue.async { c.resume(with: Result { try work() }) }
        }
    }
}
