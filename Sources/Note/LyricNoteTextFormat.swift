import Foundation

/// PROTOTYPE — not wired into the app. Demonstrates that the "raw text with
/// markup rules" idea for the lyric note editor round-trips cleanly onto the
/// existing data model (letter-indexed annotations, per-line notes, one
/// whole-song note). No dependency on AppServices/the stores; pure text in,
/// structured data out, and back again.
///
/// Proposed syntax:
///
///   [note: free-form note about the whole song, can span
///   multiple lines until the closing bracket]
///
///   [00:12.34] 안녕하세요[1] 오늘도 좋은 날
///   [ann:1] "hello" -- formal register here
///   [lnote: this line sets up the whole first verse]
///
///   [00:15.80] (end)
///
/// Rules:
/// - `[mm:ss.xx] text` starts a new lyric line (same time format the app
///   already uses elsewhere via LRCTimeFormatter).
/// - An inline `[marker]` placed directly after a character in that line's
///   text marks *that* character as annotated with `marker`, and is
///   stripped back out of the actual lyric text on parse.
/// - `[ann:marker] text` on its own line attaches note text to that marker,
///   for the most recently started lyric line.
/// - `[lnote: text]` on its own line is a free-form note attached to the
///   most recently started lyric line.
/// - `[note: text]` anywhere outside a lyric line is the one whole-song
///   note. Multiple `[note: ...]` blocks are concatenated in order.
/// - Blank lines are ignored.

struct ParsedAnnotation {
    let charIndex: Int      // index into the *cleaned* line text (marker stripped)
    let marker: String
    var noteText: String = ""
}

struct ParsedLyricLine {
    let timeMs: Int?
    var text: String
    var annotations: [ParsedAnnotation] = []
    var lineNote: String = ""
}

struct ParsedLyricDocument {
    var lines: [ParsedLyricLine] = []
    var songNote: String = ""
}

enum LyricNoteTextFormat {

    // MARK: - Parsing

    static func parse(_ raw: String) -> ParsedLyricDocument {
        var doc = ParsedLyricDocument()
        var pendingBlockKeyword: String? = nil   // "note" or "lnote" while collecting a multi-line block
        var pendingBlockBuffer: String = ""
        var pendingAnnMarker: String? = nil

        func flushPendingBlock() {
            guard let keyword = pendingBlockKeyword else { return }
            let text = pendingBlockBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            switch keyword {
            case "note":
                doc.songNote += (doc.songNote.isEmpty ? "" : "\n\n") + text
            case "lnote":
                if !doc.lines.isEmpty {
                    doc.lines[doc.lines.count - 1].lineNote = text
                }
            default:
                if let marker = pendingAnnMarker, !doc.lines.isEmpty {
                    let lastIndex = doc.lines.count - 1
                    if let i = doc.lines[lastIndex].annotations.firstIndex(where: { $0.marker == marker }) {
                        doc.lines[lastIndex].annotations[i].noteText = text
                    }
                }
            }
            pendingBlockKeyword = nil
            pendingBlockBuffer = ""
            pendingAnnMarker = nil
        }

        let rawLines = raw.components(separatedBy: .newlines)

        for rawLine in rawLines {
            let line = rawLine

            // A brand-new tagged line ends whatever block we were collecting.
            let isNewTag = line.hasPrefix("[note:") || line.hasPrefix("[lnote:")
                || line.hasPrefix("[ann:") || line.range(of: #"^\[\d{1,2}:\d{2}(\.\d{1,3})?\]"#, options: .regularExpression) != nil

            if isNewTag {
                flushPendingBlock()
            }

            if line.hasPrefix("[note:") {
                pendingBlockKeyword = "note"
                pendingBlockBuffer = String(line.dropFirst("[note:".count))
                if pendingBlockBuffer.hasSuffix("]") {
                    pendingBlockBuffer.removeLast()
                    flushPendingBlock()
                }
                continue
            }

            if line.hasPrefix("[lnote:") {
                pendingBlockKeyword = "lnote"
                pendingBlockBuffer = String(line.dropFirst("[lnote:".count))
                if pendingBlockBuffer.hasSuffix("]") {
                    pendingBlockBuffer.removeLast()
                    flushPendingBlock()
                }
                continue
            }

            if line.hasPrefix("[ann:"), let closeBracket = line.firstIndex(of: "]") {
                let marker = String(line[line.index(line.startIndex, offsetBy: 5)..<closeBracket])
                var rest = String(line[line.index(after: closeBracket)...])
                    .trimmingCharacters(in: .whitespaces)
                pendingBlockKeyword = "ann"
                pendingAnnMarker = marker
                pendingBlockBuffer = rest
                continue
            }

            // Currently inside a multi-line [note:/lnote:] block that hasn't closed yet.
            if pendingBlockKeyword != nil {
                if line.hasSuffix("]") {
                    pendingBlockBuffer += "\n" + String(line.dropLast())
                    flushPendingBlock()
                } else {
                    pendingBlockBuffer += "\n" + line
                }
                continue
            }

            // Timestamped lyric line: "[00:12.34] text with [1] inline markers"
            if let match = line.range(of: #"^\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]\s?"#, options: .regularExpression) {
                let tag = String(line[match])
                let timeMs = parseTimeTag(tag)
                var body = String(line[match.upperBound...])

                var annotations: [ParsedAnnotation] = []
                // Strip inline [marker] tags, recording the character index
                // (in the *cleaned* text) they were attached to.
                while let bracketRange = body.range(of: #"\[[^\[\]:]+\]"#, options: .regularExpression) {
                    let marker = String(body[bracketRange].dropFirst().dropLast())
                    let charIndex = body.distance(from: body.startIndex, to: bracketRange.lowerBound) - 1
                    annotations.append(ParsedAnnotation(charIndex: max(charIndex, 0), marker: marker))
                    body.removeSubrange(bracketRange)
                }

                doc.lines.append(ParsedLyricLine(timeMs: timeMs, text: body, annotations: annotations))
                continue
            }

            // Blank/unrecognized lines are ignored.
        }

        flushPendingBlock()
        return doc
    }

    private static func parseTimeTag(_ tag: String) -> Int? {
        // tag looks like "[01:23.45] " -- reuse the same mm:ss.xx shape the
        // app's LRCTimeFormatter already parses elsewhere.
        let trimmed = tag.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
        let parts = trimmed.split(separator: ":")
        guard parts.count == 2, let minutes = Int(parts[0]) else { return nil }
        let secParts = parts[1].split(separator: ".")
        guard let seconds = Int(secParts[0]) else { return nil }
        var ms = (minutes * 60 + seconds) * 1000
        if secParts.count > 1 {
            let fractionStr = secParts[1].padding(toLength: 3, withPad: "0", startingAt: 0)
            ms += Int(fractionStr) ?? 0
        }
        return ms
    }

    // MARK: - Serializing (structured data -> editable text, for "load into editor")

    static func serialize(_ doc: ParsedLyricDocument) -> String {
        var out = ""
        if !doc.songNote.isEmpty {
            out += "[note: \(doc.songNote)]\n\n"
        }
        for line in doc.lines {
            let timeTag = line.timeMs.map(formatTimeTag) ?? "[--:--]"
            var text = line.text
            // Re-insert inline markers at their recorded character index,
            // highest index first so earlier insertions don't shift later ones.
            for ann in line.annotations.sorted(by: { $0.charIndex > $1.charIndex }) {
                let insertAt = text.index(text.startIndex, offsetBy: min(ann.charIndex + 1, text.count))
                text.insert(contentsOf: "[\(ann.marker)]", at: insertAt)
            }
            out += "\(timeTag) \(text)\n"
            for ann in line.annotations where !ann.noteText.isEmpty {
                out += "[ann:\(ann.marker)] \(ann.noteText)\n"
            }
            if !line.lineNote.isEmpty {
                out += "[lnote: \(line.lineNote)]\n"
            }
            out += "\n"
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func formatTimeTag(_ ms: Int) -> String {
        let totalCentiseconds = ms / 10
        let minutes = totalCentiseconds / 6000
        let seconds = (totalCentiseconds / 100) % 60
        let centiseconds = totalCentiseconds % 100
        return String(format: "[%02d:%02d.%02d]", minutes, seconds, centiseconds)
    }
}

// MARK: - Demo / self-check (round-trip)

let sample = """
[note: A song about missing someone during a long winter.
Written from the perspective of someone who's already left.]

[00:12.34] 안녕하세요[1] 오늘도 좋은 날
[ann:1] "hello" -- formal register, sets a polite distant tone
[lnote: This line sets up the whole first verse's contrast between politeness and loneliness]

[00:15.80] (end)
"""

//let parsed = LyricNoteTextFormat.parse(sample)
//print("=== PARSED ===")
//print("Song note:", parsed.songNote)
//for line in parsed.lines {
//    print("Line @\(line.timeMs.map(String.init) ?? "nil")ms: \"\(line.text)\"")
//    for ann in line.annotations {
//        print("  annotation[\(ann.marker)] at char \(ann.charIndex): \(ann.noteText)")
//    }
//    if !line.lineNote.isEmpty { print("  line note: \(line.lineNote)") }
//}
//
//print("\n=== RE-SERIALIZED ===")
//print(LyricNoteTextFormat.serialize(parsed))
