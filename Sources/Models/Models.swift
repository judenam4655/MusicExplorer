import Foundation

struct Track: Equatable, Hashable {
    let id: String
    let title: String
    let artist: String
    let album: String?
    let durationMs: Int
}

struct PlaybackSnapshot {
    let trackTitle: String
    let artist: String
    let album: String?
    let durationMs: Int
    let positionMs: Int
    let isPlaying: Bool
    let timestamp: Date   // when this snapshot was captured, used for drift/interpolation math

    var asTrack: Track {
        Track(
            id: TrackIdentity.key(title: trackTitle, artist: artist, durationMs: durationMs),
            title: trackTitle,
            artist: artist,
            album: album,
            durationMs: durationMs
        )
    }
}

struct LyricLine: Codable, Equatable {
    let timeMs: Int?
    let text: String
}

struct LyricsResult: Codable {
    let source: String            // "lrclib" | "musixmatch" | "manual"
    let synced: [LyricLine]?      // nil if only plain (unsynced) text is available
    let plainText: String?
    let translatedSynced: [LyricLine]?
}

struct TranslationDocument {
    let trackId: String
    let language: String          // "ko"
    let rawText: String
    let updatedAt: Date
}

struct SongInfoNote {
    let trackId: String
    var content: String?
    var source: String?
    var documentID: String?
    let updatedAt: Date
}

struct PlayHistoryEntry {
    let id: Int64?
    let trackId: String
    let playedAt: Date
    let msPlayed: Int
    let completed: Bool
}

struct TrackQuery {
    let title: String
    let artist: String
    let album: String?
    let durationMs: Int
}
