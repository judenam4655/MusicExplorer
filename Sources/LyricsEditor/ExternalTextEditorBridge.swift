import AppKit
import Foundation

/// Hands text editing off to a real, separate application (TextEdit, BBEdit,
/// VS Code -- whatever the person has set as their default .txt handler)
/// instead of rendering it inside our own view tree. This is deliberately
/// dumb: write a file, open it, and later re-read whatever's on disk when
/// asked to. No file-watching, no live sync -- just the two buttons you
/// asked for ("open" and "load").
///
/// This is also the actual performance win for large songs: while the
/// person is editing, none of our SwiftUI view hierarchy is doing anything
/// at all. The cost of rendering hundreds of annotatable letters only
/// applies to the read-only summary you choose to keep on screen (or not).
enum ExternalTextEditorBridge {

    private static var workingDirectory: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MusicExplorerTextEdits", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Turns free text (a track title, etc.) into something safe to use as
    /// a filename.
    static func sanitizedFilename(_ raw: String, suffix: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let cleaned = raw.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { $0.append($1) }
        let trimmed = cleaned.isEmpty ? "untitled" : cleaned
        return "\(trimmed)-\(suffix).txt"
    }

    /// Writes `text` to a well-known temp file and opens it in the user's
    /// default text editor. Returns the file URL so the caller can later
    /// `load(from:)` it -- keep this around (e.g. in `@State`) between the
    /// "Open" and "Load" button taps.
    @discardableResult
    static func open(text: String, filename: String) -> URL? {
        let url = workingDirectory.appendingPathComponent(filename)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(url)
            return url
        } catch {
            print("ExternalTextEditorBridge: failed to write/open \(filename): \(error)")
            return nil
        }
    }

    /// Reads back whatever is currently saved at `url`. Call this after the
    /// person has edited and saved in their external editor and tapped
    /// "Load Changes" back in the app.
    static func load(from url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }
}
