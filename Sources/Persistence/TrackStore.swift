import Foundation

/// Every other table (lyrics_cache, translations, song_info, play_history)
/// references tracks(id), so this upsert should run before any of them are
/// written to for a given track. AppServices calls this on every track change.
final class TrackStore {
    private let db: SQLiteDB
    init(db: SQLiteDB) { self.db = db }

    func upsert(_ track: Track) {
        db.run(
            """
            INSERT INTO tracks (id, title, artist, album, duration_ms)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                artist = excluded.artist,
                album = excluded.album,
                duration_ms = excluded.duration_ms
            """,
            [track.id, track.title, track.artist, track.album, track.durationMs]
        )
    }
}
