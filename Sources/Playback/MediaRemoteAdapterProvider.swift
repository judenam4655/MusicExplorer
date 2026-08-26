import Foundation

/// Bridges to a vendored copy of github.com/ungive/mediaremote-adapter, which
/// shells out through an entitled system binary (e.g. /usr/bin/perl) to reach
/// MediaRemote on macOS 15.4+, where MediaRemoteDirectProvider stops working.
///
/// SETUP REQUIRED (see README.md):
///  1. Download github.com/ungive/mediaremote-adapter.
///  2. Add its adapter script + helper framework to this Xcode project under
///     Resources/mediaremote-adapter/, included via a "Copy Files" build
///     phase so they land in the .app bundle's Resources folder.
///  3. Check that repo's README for its CURRENT CLI surface before relying on
///     this -- it's an actively maintained third-party tool and its exact
///     flags/output format may have moved on since this was written. The
///     `stream`/`get` subcommands and JSON field names below are this
///     project's best-effort match to that tool as of writing; treat them as
///     a starting point to verify against the real README, not gospel.
final class MediaRemoteAdapterProvider: PlaybackProvider {
    let name = "MediaRemoteAdapter"

    private var process: Process?
    private var updateHandler: ((PlaybackSnapshot) -> Void)?

    private var adapterScriptURL: URL? {
        Bundle.main.url(
            forResource: "mediaremote-adapter", withExtension: "pl",
            subdirectory: "mediaremote-adapter"
        )
    }
    private var helperFrameworkPath: String? {
        Bundle.main.path(
            forResource: "MediaRemoteAdapter", ofType: "framework",
            inDirectory: "mediaremote-adapter"
        )
    }

    /// Quick availability check without starting the long-running stream.
    func currentSnapshot() -> PlaybackSnapshot? {
        guard let scriptURL = adapterScriptURL, let helperPath = helperFrameworkPath else { return nil }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        proc.arguments = [scriptURL.path, helperPath, "get"]
        let pipe = Pipe()
        proc.standardOutput = pipe

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let line = String(data: data, encoding: .utf8)?
                .split(separator: "\n").last else { return nil }
        return Self.parseJSONLine(String(line))
    }

    func observe(_ onUpdate: @escaping (PlaybackSnapshot) -> Void) {
        guard let scriptURL = adapterScriptURL, let helperPath = helperFrameworkPath else { return }
        updateHandler = onUpdate

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        proc.arguments = [scriptURL.path, helperPath, "stream"]

        let pipe = Pipe()
        proc.standardOutput = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(separator: "\n") {
                if let snap = Self.parseJSONLine(String(line)) {
                    self.updateHandler?(snap)
                }
            }
        }

        do {
            try proc.run()
            process = proc
        } catch {
            // Launch failed (missing binary, bad arguments, etc). Left silent
            // here so PlaybackTrackerService's selection logic falls back
            // further (to AppleScriptSpotifyProvider) instead of crashing.
        }
    }
    
    func seek(to positionMs: Int) {} // since read-only
    
    func togglePlayPause() {} // since read-only

    func stop() {
        process?.terminate()
        process = nil
        updateHandler = nil
    }

    private static func parseJSONLine(_ line: String) -> PlaybackSnapshot? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let title = obj["title"] as? String else { return nil }
        let artist = obj["artist"] as? String ?? ""
        let album = obj["album"] as? String
        let durationSec = obj["duration"] as? Double ?? 0
        let elapsedSec = obj["elapsedTime"] as? Double ?? 0
        let playing = obj["playing"] as? Bool ?? false

        return PlaybackSnapshot(
            trackTitle: title,
            artist: artist,
            album: album,
            durationMs: Int(durationSec * 1000),
            positionMs: Int(elapsedSec * 1000),
            isPlaying: playing,
            timestamp: Date()
        )
    }
}
