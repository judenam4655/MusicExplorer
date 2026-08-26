import Foundation

/// A note attached to one word in one line of the current track's original
/// lyrics. Word-level, not character-level -- see the note in
/// LyricsNoteEditorView.swift about why true per-character placement needs
/// a different (AppKit/TextKit-based) approach if you want that later.
struct LyricAnnotation: Identifiable, Equatable {
    let id: Int64?
    let trackId: String
    let lineIndex: Int
    let wordIndex: Int
    var noteText: String
    var marker: String?
    let updatedAt: Date
}
