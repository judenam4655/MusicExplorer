//
//  CustomLyricsStore.swift
//  MusicExplorer
//
//  Created by Juhyeon Nam on 8/21/26.
//

import Foundation

final class CustomLyricsStore {
    private let db: SQLiteDB

    init(db: SQLiteDB) {
        self.db = db
    }

    func getOriginalLRC(trackId: String) -> String? {
        firstNonEmpty(column: "original_lrc", trackId: trackId)
    }

    func getTranslationLRC(trackId: String) -> String? {
        firstNonEmpty(column: "translation_lrc", trackId: trackId)
    }

    func saveOriginal(trackId: String, lrcText: String) {
        upsert(trackId: trackId, column: "original_lrc", value: lrcText)
    }

    func saveTranslation(trackId: String, lrcText: String) {
        upsert(trackId: trackId, column: "translation_lrc", value: lrcText)
    }

    func delete(trackId: String) {
        db.run("DELETE FROM custom_lyrics WHERE track_id = ?", [trackId])
    }

    private func firstNonEmpty(column: String, trackId: String) -> String? {
        let rows: [String] = db.query(
            "SELECT \(column) FROM custom_lyrics WHERE track_id = ?",
            [trackId]
        ) { stmt in SQLiteDB.columnText(stmt, 0) ?? "" }
        let value = rows.first
        return (value?.isEmpty ?? true) ? nil : value
    }

    /// Two-step upsert (insert-empty-row-if-missing, then update the one
    /// column) so saving a translation never clobbers an existing custom
    /// original in the same row, and vice versa.
    private func upsert(trackId: String, column: String, value: String) {
        db.run(
            "INSERT INTO custom_lyrics (track_id, updated_at) VALUES (?, ?) ON CONFLICT(track_id) DO NOTHING",
            [trackId, Int(Date().timeIntervalSince1970)]
        )
        db.run(
            "UPDATE custom_lyrics SET \(column) = ?, updated_at = ? WHERE track_id = ?",
            [value, Int(Date().timeIntervalSince1970), trackId]
        )
    }
}
