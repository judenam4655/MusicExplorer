import Foundation

/// Simple CRUD over user-pasted song info (e.g. from Namuwiki), keyed by
/// trackId. Deliberately no scraping/fetching -- see review notes on why.
final class SongInfoStore {
    private let db: SQLiteDB
    init(db: SQLiteDB) { self.db = db }
    
    func get(trackId: String) -> SongInfoNote? {
        let rows: [SongInfoNote] = db.query(
            "SELECT source, content, documentID, updated_at FROM song_info WHERE track_id = ?",
            [trackId]
        ) { stmt in
            // FIX: Realigned the column indices to match 0, 1, 2, 3
            let source = SQLiteDB.columnText(stmt, 0) ?? ""
            let content = SQLiteDB.columnText(stmt, 1) ?? ""
            let docID = SQLiteDB.columnText(stmt, 2) ?? ""
            let updatedAt = Date(timeIntervalSince1970: TimeInterval(SQLiteDB.columnInt(stmt, 3)))
            return SongInfoNote(trackId: trackId, content: content, source: source, documentID: docID, updatedAt: updatedAt)
        }
        return rows.first
    }
    
    func save(trackId: String, source: String?, content: String, documentID: String?) {
        db.run(
            """
            INSERT INTO song_info (track_id, source, content, documentID, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(track_id) DO UPDATE SET
                source = excluded.source,
                content = excluded.content,
                documentID = excluded.documentID,
                updated_at = excluded.updated_at
            """,
            [trackId, source, content, documentID, Int(Date().timeIntervalSince1970)]
        )
    }
    
    func saveSource(trackId: String, source: String){
        db.run(
            """
            INSERT INTO song_info (track_id, source, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(track_id) DO UPDATE SET
                source = excluded.source,
                updated_at = excluded.updated_at
            """,
            [trackId, source, Int(Date().timeIntervalSince1970)]
        )
    }
    
    func saveOfflineCopy(trackId: String, content: String, documentID: String){
        db.run(
            """
            INSERT INTO song_info (track_id, content, documentID, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(track_id) DO UPDATE SET
                content = excluded.content,
                documentID = excluded.documentID,
                updated_at = excluded.updated_at
            """,
            [trackId, content, documentID, Int(Date().timeIntervalSince1970)]
        )
    }
}
