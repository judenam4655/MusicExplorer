//
//  LineNoteStore.swift
//  MusicExplorer
//
//  Created by Juhyeon Nam on 8/22/26.
//

//import Foundation
//
//final class LineNoteStore {
//    private let db: SQLiteDB
//    init(db: SQLiteDB) { self.db = db }
//
//    func all(trackId: String) -> [Int: String] {
//        var results: [Int: String] = [:]
//        db.query(
//            "SELECT line_index, note_text FROM lyric_line_notes WHERE track_id = ?",
//            [trackId]
//        ) { stmt in
//            let index = SQLiteDB.columnInt(stmt, 0)
//            let text = SQLiteDB.columnText(stmt, 1) ?? ""
//            results[index] = text
//        }
//        return results
//    }
//
//    func save(trackId: String, lineIndex: Int, text: String) {
//        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
//        if trimmed.isEmpty {
//            db.run("DELETE FROM lyric_line_notes WHERE track_id = ? AND line_index = ?", [trackId, lineIndex])
//        } else {
//            db.run(
//                """
//                INSERT INTO lyric_line_notes (track_id, line_index, note_text, updated_at)
//                VALUES (?, ?, ?, ?)
//                ON CONFLICT(track_id, line_index) DO UPDATE SET note_text = excluded.note_text, updated_at = excluded.updated_at
//                """,
//                [trackId, lineIndex, trimmed, Int(Date().timeIntervalSince1970)]
//            )
//        }
//    }
//}
