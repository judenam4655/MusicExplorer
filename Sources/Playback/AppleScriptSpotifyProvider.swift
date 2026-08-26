import Foundation

final class AppleScriptSpotifyProvider: PlaybackProvider {
    let name = "AppleScriptSpotify"

    private var timer: Timer?
    private var updateHandler: ((PlaybackSnapshot) -> Void)?
    private let pollInterval: TimeInterval

    init(pollInterval: TimeInterval = 1.0) {
        self.pollInterval = pollInterval
    }

    func currentSnapshot() -> PlaybackSnapshot? {
        let script = """
        tell application "Spotify"
            if it is running then
                set t to name of current track
                set a to artist of current track
                set al to album of current track
                set d to duration of current track
                set p to player position
                set s to player state as string
                return t & "||" & a & "||" & al & "||" & d & "||" & p & "||" & s
            else
                return "NOT_RUNNING"
            end if
        end tell
        """
        
        guard let appleScript = NSAppleScript(source: script) else {
            print("Failed to create NSAppleScript instance")
            return nil
        }
        
        var errorInfo: NSDictionary?
        let result = appleScript.executeAndReturnError(&errorInfo)
        
        if let error = errorInfo {
            print("AppleScript Execution Error: \(error)")
            return nil
        }
        
        guard let output = result.stringValue else {
            print("AppleScript returned empty string value.")
            return nil
        }
        
        if output == "NOT_RUNNING" {
            print("Spotify process check: Spotify is not running.")
            return nil
        }
        
        return Self.parse(output)
    }

    func observe(_ onUpdate: @escaping (PlaybackSnapshot) -> Void) {
        updateHandler = onUpdate
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            guard let self, let snap = self.currentSnapshot() else { return }
            self.updateHandler?(snap)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        updateHandler = nil
    }
    
    func seek(to positionMs: Int) {
        let seconds = Double(positionMs) / 1000.0
        let script = "tell application \"Spotify\" to set player position to \(seconds)"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
    }
    
    func togglePlayPause() {
        let script = "tell application \"Spotify\" to playpause"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
    }

    private static func parse(_ raw: String) -> PlaybackSnapshot? {
        let parts = raw.components(separatedBy: "||")
        guard parts.count == 6 else {
            print("Failed to parse raw AppleScript output: \(raw)")
            return nil
        }
        
        let title = parts[0]
        let artist = parts[1]
        let album = parts[2]
        let durationMs = Int(Double(parts[3]) ?? 0)
        let positionSec = Double(parts[4]) ?? 0
        let isPlaying = parts[5] == "playing"

        return PlaybackSnapshot(
            trackTitle: title,
            artist: artist,
            album: album,
            durationMs: durationMs,
            positionMs: Int(positionSec * 1000),
            isPlaying: isPlaying,
            timestamp: Date()
        )
    }
}

//import Foundation
//
///// Last-resort fallback: polls Spotify.app directly via AppleScript. Also
///// usable for transport control (play/pause/seek) later, since neither
///// MediaRemote provider above gives write access.
/////
///// Requires Automation permission -- macOS will show a system prompt the
///// first time this actually talks to Spotify. Info.plist needs
///// NSAppleEventsUsageDescription (see README.md).
//final class AppleScriptSpotifyProvider: PlaybackProvider {
//    let name = "AppleScriptSpotify"
//
//    private var timer: Timer?
//    private var updateHandler: ((PlaybackSnapshot) -> Void)?
//    private let pollInterval: TimeInterval
//
//    init(pollInterval: TimeInterval = 1.0) {
//        self.pollInterval = pollInterval
//    }
//
//    func currentSnapshot() -> PlaybackSnapshot? {
//        let script = """
//        tell application "System Events"
//            set spotifyRunning to (name of processes) contains "Spotify"
//        end tell
//        if spotifyRunning then
//            tell application "Spotify"
//                set t to name of current track
//                set a to artist of current track
//                set al to album of current track
//                set d to duration of current track
//                set p to player position
//                set s to player state as string
//                return t & "||" & a & "||" & al & "||" & d & "||" & p & "||" & s
//            end tell
//        else
//            return "NOT_RUNNING"
//        end if
//        """
//        guard let appleScript = NSAppleScript(source: script) else { return nil }
//        var errorInfo: NSDictionary?
//        let result = appleScript.executeAndReturnError(&errorInfo)
//        guard errorInfo == nil, let output = result.stringValue, output != "NOT_RUNNING" else {
//            return nil
//        }
//        return Self.parse(output)
//    }
//
//    func observe(_ onUpdate: @escaping (PlaybackSnapshot) -> Void) {
//        updateHandler = onUpdate
//        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
//            guard let self, let snap = self.currentSnapshot() else { return }
//            self.updateHandler?(snap)
//        }
//    }
//
//    func stop() {
//        timer?.invalidate()
//        timer = nil
//        updateHandler = nil
//    }
//
//    private static func parse(_ raw: String) -> PlaybackSnapshot? {
//        let parts = raw.components(separatedBy: "||")
//        guard parts.count == 6 else { return nil }
//        let title = parts[0], artist = parts[1], album = parts[2]
//        let durationMs = Int(Double(parts[3]) ?? 0)   // Spotify's "duration" is already ms
//        let positionSec = Double(parts[4]) ?? 0        // "player position" is in seconds
//        let isPlaying = parts[5] == "playing"
//
//        return PlaybackSnapshot(
//            trackTitle: title,
//            artist: artist,
//            album: album,
//            durationMs: durationMs,
//            positionMs: Int(positionSec * 1000),
//            isPlaying: isPlaying,
//            timestamp: Date()
//        )
//    }
//}
