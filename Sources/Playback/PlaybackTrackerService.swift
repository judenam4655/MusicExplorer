import Foundation

final class PlaybackTrackerService {
    private var activeProvider: PlaybackProvider?
    private var interpolationTimer: Timer?
    private var lastSnapshot: PlaybackSnapshot?
    private var currentTrack: Track?

    var onTrackChanged: ((Track?, Track) -> Void)?   // (old, new)
    var onPositionTick: ((Int) -> Void)?
    var isPlaying: Bool { lastSnapshot?.isPlaying ?? false }

    func start() {
        let provider = selectProvider()
        activeProvider = provider
        print("[PlaybackTrackerService] using provider: \(provider.name)")

        // FIX: Grab the current state immediately so the timer has a baseline
        if let initialSnapshot = provider.currentSnapshot() {
            handleSnapshot(initialSnapshot)
        }

        provider.observe { [weak self] snapshot in
            self?.handleSnapshot(snapshot)
        }
        
        startInterpolationTimer()
    }

    func stop() {
        activeProvider?.stop()
        interpolationTimer?.invalidate()
    }
    
    func seek(to positionMs: Int) {
        activeProvider?.seek(to: positionMs)
    }
        
    func togglePlayPause() {
        activeProvider?.togglePlayPause()
    }

    private func selectProvider() -> PlaybackProvider {
        // LOCK strictly to Spotify, bypassing all MediaRemote caches
        return AppleScriptSpotifyProvider()
    }
    
    private func handleSnapshot(_ snapshot: PlaybackSnapshot) {
        let newTrack = snapshot.asTrack
        if newTrack.id != currentTrack?.id {
            let old = currentTrack
            currentTrack = newTrack
            onTrackChanged?(old, newTrack)
        }
        // Always update the snapshot so the interpolation timer has fresh timestamps
        lastSnapshot = snapshot
    }

    private func startInterpolationTimer() {
        // Fires 4x a second to drive the UI smoothly
        interpolationTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        onPositionTick?(currentInterpolatedPositionMs())
    }

    func currentInterpolatedPositionMs() -> Int {
        guard let last = lastSnapshot else { return 0 }
        
        // If the song is paused, don't increment the elapsed time
        guard last.isPlaying else { return last.positionMs }
        
        let elapsedMs = Date().timeIntervalSince(last.timestamp) * 1000
        return min(last.positionMs + Int(elapsedMs), last.durationMs)
    }
}


//import Foundation
//
//final class PlaybackTrackerService {
//    private var activeProvider: PlaybackProvider?
//    private var interpolationTimer: Timer?
//    private var lastSnapshot: PlaybackSnapshot?
//    private var currentTrack: Track?
//
//    var onTrackChanged: ((Track?, Track) -> Void)?   // (old, new)
//    var onPositionTick: ((Int) -> Void)?
//
//    func start() {
//        let provider = selectProvider()
//        activeProvider = provider
//        print("[PlaybackTrackerService] using provider: \(provider.name)")
//
//        provider.observe { [weak self] snapshot in
//            self?.handleSnapshot(snapshot)
//        }
//        startInterpolationTimer()
//    }
//
//    func stop() {
//        activeProvider?.stop()
//        interpolationTimer?.invalidate()
//    }
//
//    /// Probes providers in priority order and returns the first one that
//    /// actually produces data right now. No macOS-version branching: this
//    /// works unchanged on your 14.5 today (MediaRemoteDirectProvider wins)
//    /// and will keep working after any future upgrade past 15.4, where that
//    /// provider goes silent and MediaRemoteAdapterProvider takes over instead.
//    private func selectProvider() -> PlaybackProvider {
//        if let direct = MediaRemoteDirectProvider(), direct.currentSnapshot() != nil {
//            return direct
//        }
//        let adapter = MediaRemoteAdapterProvider()
//        if adapter.currentSnapshot() != nil {
//            return adapter
//        }
//        return AppleScriptSpotifyProvider()
//    }
//    
//    private func handleSnapshot(_ snapshot: PlaybackSnapshot) {
//        let newTrack = snapshot.asTrack
//        if newTrack.id != currentTrack?.id {
//            let old = currentTrack
//            currentTrack = newTrack
//            onTrackChanged?(old, newTrack)
//        }
//        lastSnapshot = snapshot
//    }
//
//    private func startInterpolationTimer() {
//        interpolationTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
//            self?.tick()
//        }
//    }
//
//    private func tick() {
//        onPositionTick?(currentInterpolatedPositionMs())
//    }
//
//    /// Position estimated from the last real snapshot plus elapsed wall-clock
//    /// time, so lyric sync doesn't need to poll the OS every 250ms. Real
//    /// snapshots (fired via handleSnapshot) reset this baseline, so drift
//    /// never accumulates for more than one polling/notification interval.
//    func currentInterpolatedPositionMs() -> Int {
//        guard let last = lastSnapshot else { return 0 }
//        guard last.isPlaying else { return last.positionMs }
//        let elapsedMs = Date().timeIntervalSince(last.timestamp) * 1000
//        return min(last.positionMs + Int(elapsedMs), last.durationMs)
//    }
//}
