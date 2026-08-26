import Foundation

/// Simple CRUD over user-pasted Korean translations, keyed by trackId.
/// No fetching/scraping logic -- the user supplies the text.
final class TranslationStore {
    private let db: SQLiteDB
    init(db: SQLiteDB) { self.db = db }

    func get(trackId: String) -> TranslationDocument? {
        let rows: [TranslationDocument] = db.query(
            "SELECT raw_text, updated_at FROM translations WHERE track_id = ?",
            [trackId]
        ) { stmt in
            let text = SQLiteDB.columnText(stmt, 0) ?? ""
            let updatedAt = Date(timeIntervalSince1970: TimeInterval(SQLiteDB.columnInt(stmt, 1)))
            return TranslationDocument(trackId: trackId, language: "ko", rawText: text, updatedAt: updatedAt)
        }
        return rows.first
    }

    func save(trackId: String, rawText: String) {
        db.run(
            """
            INSERT INTO translations (track_id, raw_text, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(track_id) DO UPDATE SET
                raw_text = excluded.raw_text,
                updated_at = excluded.updated_at
            """,
            [trackId, rawText, Int(Date().timeIntervalSince1970)]
        )
    }

    func delete(trackId: String) {
        db.run("DELETE FROM translations WHERE track_id = ?", [trackId])
    }
}
