import Foundation

final class LyricAnnotationStore {
    private let db: SQLiteDB
    init(db: SQLiteDB) { self.db = db }

    func all(trackId: String) -> [LyricAnnotation] {
        db.query(
            """
            SELECT id, line_index, word_index, note_text, marker, updated_at
            FROM lyric_annotations WHERE track_id = ?
            ORDER BY line_index, word_index
            """,
            [trackId]
        ) { stmt in
            LyricAnnotation(
                id: Int64(SQLiteDB.columnInt(stmt, 0)),
                trackId: trackId,
                lineIndex: SQLiteDB.columnInt(stmt, 1),
                wordIndex: SQLiteDB.columnInt(stmt, 2),
                noteText: SQLiteDB.columnText(stmt, 3) ?? "",
                marker: SQLiteDB.columnText(stmt, 4),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(SQLiteDB.columnInt(stmt, 5)))
            )
        }
    }

    /// Grouped by line index for fast lookup while rendering the lyrics view.
    func grouped(trackId: String) -> [Int: [LyricAnnotation]] {
        Dictionary(grouping: all(trackId: trackId), by: { $0.lineIndex })
    }

    /// Delete-then-insert rather than a raw INSERT, since there's no unique
    /// constraint on (track_id, line_index, word_index) -- this keeps
    /// re-saving the same word from piling up duplicate rows.
    func save(trackId: String, lineIndex: Int, wordIndex: Int, noteText: String, marker: String) {
        delete(trackId: trackId, lineIndex: lineIndex, wordIndex: wordIndex)
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        db.run(
            """
            INSERT INTO lyric_annotations (track_id, line_index, word_index, note_text, marker, updated_at) VALUES (?, ?, ?, ?, ?, ?)
            """,
            [trackId, lineIndex, wordIndex, trimmed, marker, Int(Date().timeIntervalSince1970)]
        )
    }

    func delete(trackId: String, lineIndex: Int, wordIndex: Int) {
        db.run(
            "DELETE FROM lyric_annotations WHERE track_id = ? AND line_index = ? AND word_index = ?",
            [trackId, lineIndex, wordIndex]
        )
    }

    func deleteAll(trackId: String) {
        db.run("DELETE FROM lyric_annotations WHERE track_id = ?", [trackId])
    }
}

/// Separate from annotations: one free-form note per track, not tied to a
/// specific word or line.
final class LineNoteStore {
    private let db: SQLiteDB
    init(db: SQLiteDB) {
        self.db = db
        db.run("""
            CREATE TABLE IF NOT EXISTS lyric_line_notes (
                track_id TEXT,
                line_index INTEGER,
                note_text TEXT,
                updated_at INTEGER,
                PRIMARY KEY (track_id, line_index)
            )
        """, [])
    }

    func all(trackId: String) -> [Int: String] {
        var results: [Int: String] = [:]
        db.query(
            "SELECT line_index, note_text FROM lyric_line_notes WHERE track_id = ?",
            [trackId]
        ) { stmt in
            let index = SQLiteDB.columnInt(stmt, 0)
            let text = SQLiteDB.columnText(stmt, 1) ?? ""
            results[index] = text
        }
        return results
    }

    func save(trackId: String, lineIndex: Int, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            db.run("DELETE FROM lyric_line_notes WHERE track_id = ? AND line_index = ?", [trackId, lineIndex])
        } else {
            db.run(
                """
                INSERT INTO lyric_line_notes (track_id, line_index, note_text, updated_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(track_id, line_index) DO UPDATE SET note_text = excluded.note_text, updated_at = excluded.updated_at
                """,
                [trackId, lineIndex, trimmed, Int(Date().timeIntervalSince1970)]
            )
        }
    }
}

final class LyricNoteStore {
    private let db: SQLiteDB
    init(db: SQLiteDB) { self.db = db }

    func get(trackId: String) -> String? {
        let rows: [String] = db.query(
            "SELECT content FROM lyric_notes WHERE track_id = ?",
            [trackId]
        ) { SQLiteDB.columnText($0, 0) ?? "" }
        return rows.first
    }

    func save(trackId: String, content: String) {
        db.run(
            """
            INSERT INTO lyric_notes (track_id, content, updated_at) VALUES (?, ?, ?)
            ON CONFLICT(track_id) DO UPDATE SET content = excluded.content, updated_at = excluded.updated_at
            """,
            [trackId, content, Int(Date().timeIntervalSince1970)]
        )
    }
}
