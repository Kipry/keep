import Foundation

/// Shared deep-link state injected as an environment object from LifeClipApp.
/// Any view in the hierarchy can observe and consume the pending action.
@Observable
final class AppDeepLink {
    var pendingRecordProjectID: UUID?
}
