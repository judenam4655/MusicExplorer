import Foundation

final class PlayHistoryLogger {
    private let store: PlayHistoryStore
    private var startedAt: Date?
    private var lastKnownPositionMs: Int = 0

    /// A track counts as "completed" once playback reached at least this
    /// fraction of its duration before switching away.
    private let completionThreshold = 0.9

    init(store: PlayHistoryStore) {
        self.store = store
    }

    /// Call this from PlaybackTrackerService.onTrackChanged. Closes out the
    /// *previous* track's history entry using whatever position we last saw
    /// for it, then starts timing the new one.
    func trackChanged(from old: Track?, to new: Track) {
        if let old, let startedAt {
            let msPlayed = lastKnownPositionMs
            let completed = old.durationMs > 0
                && Double(msPlayed) / Double(old.durationMs) >= completionThreshold
            store.insert(PlayHistoryEntry(
                id: nil, trackId: old.id, playedAt: startedAt,
                msPlayed: msPlayed, completed: completed
            ))
        }
        startedAt = Date()
        lastKnownPositionMs = 0
    }

    /// Call this from PlaybackTrackerService.onPositionTick so we always know
    /// how far into the current track we got, in case the user quits or
    /// switches tracks between snapshots.
    func positionUpdated(_ positionMs: Int) {
        lastKnownPositionMs = positionMs
    }
}
