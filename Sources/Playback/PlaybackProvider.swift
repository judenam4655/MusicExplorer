import Foundation

protocol PlaybackProvider: AnyObject {
    /// Used for logging/diagnostics when the tracker picks a fallback.
    var name: String { get }

    /// One-shot probe. Returns nil if this provider currently has no data
    /// (e.g. MediaRemote access denied on macOS 15.4+, or Spotify not running).
    /// PlaybackTrackerService uses this at startup to pick which provider to use.
    func currentSnapshot() -> PlaybackSnapshot?

    /// Begin push/poll updates. Callback may fire on a background queue.
    func observe(_ onUpdate: @escaping (PlaybackSnapshot) -> Void)

    func stop()
    
    func seek(to positionMs: Int)
    
    func togglePlayPause()
}
