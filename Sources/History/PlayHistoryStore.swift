import Foundation

final class PlayHistoryStore {
    private let db: SQLiteDB
    init(db: SQLiteDB) { self.db = db }

    func insert(_ entry: PlayHistoryEntry) {
        db.run(
            "INSERT INTO play_history (track_id, played_at, ms_played, completed) VALUES (?, ?, ?, ?)",
            [entry.trackId, Int(entry.playedAt.timeIntervalSince1970), entry.msPlayed, entry.completed ? 1 : 0]
        )
    }

    func entries(from: Date? = nil, to: Date? = nil) -> [PlayHistoryEntry] {
        var sql = "SELECT id, track_id, played_at, ms_played, completed FROM play_history WHERE 1=1"
        var bindings: [Any?] = []
        if let from {
            sql += " AND played_at >= ?"
            bindings.append(Int(from.timeIntervalSince1970))
        }
        if let to {
            sql += " AND played_at <= ?"
            bindings.append(Int(to.timeIntervalSince1970))
        }
        sql += " ORDER BY played_at DESC"

        return db.query(sql, bindings) { stmt in
            PlayHistoryEntry(
                id: Int64(SQLiteDB.columnInt(stmt, 0)),
                trackId: SQLiteDB.columnText(stmt, 1) ?? "",
                playedAt: Date(timeIntervalSince1970: TimeInterval(SQLiteDB.columnInt(stmt, 2))),
                msPlayed: SQLiteDB.columnInt(stmt, 3),
                completed: SQLiteDB.columnInt(stmt, 4) == 1
            )
        }
    }

    func mostPlayed(limit: Int = 20) -> [(trackId: String, playCount: Int)] {
        db.query(
            "SELECT track_id, COUNT(*) as c FROM play_history GROUP BY track_id ORDER BY c DESC LIMIT ?",
            [limit]
        ) { stmt in
            (SQLiteDB.columnText(stmt, 0) ?? "", SQLiteDB.columnInt(stmt, 1))
        }
    }
}
