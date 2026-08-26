import Foundation
import SQLite3

// NOTE: requires libsqlite3.tbd linked in the Xcode target
// (Build Phases -> Link Binary With Libraries -> + -> libsqlite3.tbd).

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class SQLiteDB {
    private var db: OpaquePointer?
    
    private let queue = DispatchQueue(label: "come.musicexplorer.sqlite", qos: .userInitiated)

    init(fileName: String = "musicexplorer.sqlite3") {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MusicExplorer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent(fileName).path

        if sqlite3_open(path, &db) != SQLITE_OK {
            fatalError("Unable to open database at \(path)")
        }
        migrate()
    }

    private func migrate() {
        let statements = [
            """
            CREATE TABLE IF NOT EXISTS tracks (
                id TEXT PRIMARY KEY, title TEXT, artist TEXT, album TEXT, duration_ms INTEGER
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS lyrics_cache (
                track_id TEXT PRIMARY KEY REFERENCES tracks(id),
                source TEXT, synced_json TEXT, plain_text TEXT, fetched_at INTEGER
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS custom_lyrics (
                track_id TEXT PRIMARY KEY,
                synced_lrc TEXT,
                updated_at INTEGER
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS translations (
                track_id TEXT PRIMARY KEY REFERENCES tracks(id),
                raw_text TEXT, updated_at INTEGER
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS song_info (
                track_id TEXT PRIMARY KEY REFERENCES tracks(id),
                source TEXT, content TEXT, documentID TEXT,
                updated_at INTEGER
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS play_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                track_id TEXT REFERENCES tracks(id),
                played_at INTEGER, ms_played INTEGER, completed INTEGER
            );
            """
        ]
        for sql in statements { run(sql, []) }
        
        run(
            """
            CREATE TABLE IF NOT EXISTS custom_lyrics (
                track_id TEXT PRIMARY KEY REFERENCES tracks(id),
                original_lrc TEXT,
                translation_lrc TEXT,
                updated_at INTEGER
            );
            """, []
        )
        
        run(
            """
            CREATE TABLE IF NOT EXISTS lyric_annotations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                track_id TEXT REFERENCES tracks(id),
                line_index INTEGER,
                word_index INTEGER,
                marker TEXT,
                note_text TEXT,
                updated_at INTEGER
            );
            """, []
        )

        run(
            """
            CREATE TABLE IF NOT EXISTS lyric_notes (
                track_id TEXT PRIMARY KEY REFERENCES tracks(id),
                content TEXT,
                updated_at INTEGER
            );
            """, []
        )
        
        run(
            """
            CREATE TABLE IF NOT EXISTS lyric_line_notes (
                track_id TEXT PRIMARY KEY REFERENCES tracks(id),
                line_index INTEGER NOT NULL,
                note_text TEXT NOT NULL,
                updated_at INTEGER NOT NULL
            );
            """, []
        )
    }

    @discardableResult
    func run(_ sql: String, _ bindings: [Any?]) -> Bool {
        return queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                logLastError(sql)
                return false
            }
            defer { sqlite3_finalize(stmt) }
            bind(bindings, to: stmt)

            let result = sqlite3_step(stmt)
            guard result == SQLITE_DONE || result == SQLITE_ROW else {
                logLastError(sql)
                return false
            }
            return true
        }
    }

    func query<T>(_ sql: String, _ bindings: [Any?], _ mapper: (OpaquePointer) -> T) -> [T] {
        return queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                logLastError(sql)
                return []
            }
            defer { sqlite3_finalize(stmt) }
            bind(bindings, to: stmt)

            var results: [T] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(mapper(stmt!))
            }
            return results
        }
    }

    private func bind(_ bindings: [Any?], to stmt: OpaquePointer?) {
        guard let stmt = stmt else { return }
        
        for (i, value) in bindings.enumerated() {
            let idx = Int32(i + 1)
            switch value {
            case let v as String:
                sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
            case let v as Int:
                sqlite3_bind_int64(stmt, idx, Int64(v))
            case let v as Double:
                sqlite3_bind_double(stmt, idx, v)
            case nil:
                sqlite3_bind_null(stmt, idx)
            default:
                sqlite3_bind_null(stmt, idx)
            }
        }
    }

    private func logLastError(_ context: String) {
        if let cMsg = sqlite3_errmsg(db) {
            print("SQLite error [\(context)]: \(String(cString: cMsg))")
        }
    }

    static func columnText(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard let cStr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cStr)
    }

    static func columnInt(_ stmt: OpaquePointer, _ index: Int32) -> Int {
        Int(sqlite3_column_int64(stmt, index))
    }
}
