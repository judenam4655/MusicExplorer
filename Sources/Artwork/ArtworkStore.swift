//
//  ArtworkStore.swift
//  MusicExplorer
//
//  Created by Juhyeon Nam on 9/8/26.
//

import Foundation

final class ArtworkStore {
    private let db: SQLiteDB

    init(db: SQLiteDB) {
        self.db = db
    }

    /// Retrieves the cached image data and its origin ("itunes" or "manual")
    func getArtwork(trackId: String) -> (data: Data, source: String)? {
        let _ = print("trackId:" + trackId)
        var result: (Data, String)? = nil
        let _ = db.query(
            "SELECT image_data, source FROM track_artwork WHERE track_id = ?",
            [trackId]
        ) { stmt in
            if let data = SQLiteDB.columnData(stmt, 0),
               let source = SQLiteDB.columnText(stmt, 1) {
                result = (data, source)
            }
            return result
        }
        return result
    }

    /// Saves artwork data. Upserts to prevent duplicate rows per track.
    func saveArtwork(trackId: String, imageData: Data, source: String) {
        db.run(
            """
            INSERT INTO track_artwork (track_id, image_data, source, updated_at) 
            VALUES (?, ?, ?, ?) 
            ON CONFLICT(track_id) DO UPDATE SET 
                image_data = excluded.image_data, 
                source = excluded.source, 
                updated_at = excluded.updated_at
            """,
            [trackId, imageData, source, Int(Date().timeIntervalSince1970)]
        )
    }

    /// Deletes the artwork record (used for removing custom overrides)
    func delete(trackId: String) {
        db.run("DELETE FROM track_artwork WHERE track_id = ?", [trackId])
    }
}
