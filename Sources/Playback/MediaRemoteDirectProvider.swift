import Foundation

/// Talks directly to the private MediaRemote.framework.
///
/// Works unmodified through macOS 15.3 (confirmed on your 14.5). On macOS
/// 15.4+, Apple restricted this so only entitled Apple processes can read
/// now-playing info -- calls here will return nil/empty on those systems.
/// That failure is exactly the signal PlaybackTrackerService uses to fall
/// back to MediaRemoteAdapterProvider, so no version check is needed here.
final class MediaRemoteDirectProvider: PlaybackProvider {
    let name = "MediaRemoteDirect"

    private typealias GetNowPlayingInfoFn =
        @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias RegisterFn = @convention(c) (DispatchQueue) -> Void

    private var getNowPlayingInfo: GetNowPlayingInfoFn?
    private var registerForNotifications: RegisterFn?
    private var observerToken: NSObjectProtocol?
    private var updateHandler: ((PlaybackSnapshot) -> Void)?

    init?() {
        guard let bundle = CFBundleCreate(
                kCFAllocatorDefault,
                NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
              ),
              CFBundleLoadExecutable(bundle) else {
            return nil
        }

        guard let getPtr = CFBundleGetFunctionPointerForName(
            bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString
        ) else {
            return nil
        }
        getNowPlayingInfo = unsafeBitCast(getPtr, to: GetNowPlayingInfoFn.self)

        if let regPtr = CFBundleGetFunctionPointerForName(
            bundle, "MRMediaRemoteRegisterForNowPlayingNotifications" as CFString
        ) {
            registerForNotifications = unsafeBitCast(regPtr, to: RegisterFn.self)
        }
    }

    func currentSnapshot() -> PlaybackSnapshot? {
        var result: PlaybackSnapshot?
        let sema = DispatchSemaphore(value: 0)
        getNowPlayingInfo?(DispatchQueue.global()) { info in
            result = Self.parse(info)
            sema.signal()
        }
        _ = sema.wait(timeout: .now() + 1.0)
        return result
    }

    func observe(_ onUpdate: @escaping (PlaybackSnapshot) -> Void) {
        updateHandler = onUpdate
        registerForNotifications?(DispatchQueue.main)
        observerToken = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.getNowPlayingInfo?(DispatchQueue.main) { info in
                if let snap = Self.parse(info) {
                    self.updateHandler?(snap)
                }
            }
        }
    }
    
    func seek(to positionMs: Int) {} // since read-only
    
    func togglePlayPause() {} // since read-only

    func stop() {
        if let token = observerToken {
            DistributedNotificationCenter.default().removeObserver(token)
        }
        observerToken = nil
        updateHandler = nil
    }

    private static func parse(_ info: [String: Any]) -> PlaybackSnapshot? {
        guard let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String else { return nil }
        let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
        let album = info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String
        let durationSec = info["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? 0
        let elapsedSec = info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? 0
        let rate = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0
        
        // Print the raw dictionary to the Xcode console
        print("🔍 Raw MediaRemote Info: \(info)")
        
        guard let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String,
              let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String else {
            print("❌ MediaRemote missing title or artist")
            return nil
        }

        return PlaybackSnapshot(
            trackTitle: title,
            artist: artist,
            album: album,
            durationMs: Int(durationSec * 1000),
            positionMs: Int(elapsedSec * 1000),
            isPlaying: rate > 0,
            timestamp: Date()
        )
    }
}
