import Foundation

/// This store IS the app's offline mode -- there's no separate "offline"
/// code path elsewhere, just cache-first reads through LyricsRepository.
final class LyricsCacheStore {
    private let db: SQLiteDB
    init(db: SQLiteDB) { self.db = db }

    func get(trackId: String) -> LyricsResult? {
        let rows: [LyricsResult] = db.query(
            "SELECT source, synced_json, plain_text FROM lyrics_cache WHERE track_id = ?",
            [trackId]
        ) { stmt in
            let source = SQLiteDB.columnText(stmt, 0) ?? "unknown"
            let syncedJSON = SQLiteDB.columnText(stmt, 1)
            let plain = SQLiteDB.columnText(stmt, 2)
            let synced: [LyricLine]? = syncedJSON.flatMap {
                try? JSONDecoder().decode([LyricLine].self, from: Data($0.utf8))
            }
            return LyricsResult(source: source, synced: synced, plainText: plain, translatedSynced: nil)
        }
        return rows.first
    }

    func save(trackId: String, result: LyricsResult) {
        let syncedJSON: String? = result.synced
            .flatMap { try? JSONEncoder().encode($0) }
            .flatMap { String(data: $0, encoding: .utf8) }

        db.run(
            """
            INSERT INTO lyrics_cache (track_id, source, synced_json, plain_text, fetched_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(track_id) DO UPDATE SET
                source = excluded.source,
                synced_json = excluded.synced_json,
                plain_text = excluded.plain_text,
                fetched_at = excluded.fetched_at
            """,
            [trackId, result.source, syncedJSON, result.plainText, Int(Date().timeIntervalSince1970)]
        )
    }
}
