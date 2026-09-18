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
/// - `[mm:ss.xx] text` starts a new *timed* lyric line (same time format the
///   app already uses elsewhere via LRCTimeFormatter).
/// - A line with no leading `[mm:ss.xx]` tag and no other recognized prefix
///   is a plain *untimed* lyric line -- this is for custom/imported lyrics
///   that were never synced. A document is expected to be either fully
///   timed or fully untimed, not a mix of both.
/// - An inline `[marker]` placed directly after a character in that line's
///   text marks *that* character as annotated with `marker`, and is
///   stripped back out of the actual lyric text on parse. Works the same
///   whether the line is timed or untimed.
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
        var pendingBlockKeyword: String? = nil
        var pendingBlockBuffer: String = ""
        var pendingAnnMarker: String? = nil
        var headerDepth: Int = 0   // bracket nesting depth while inside a [header: ...] block

        func bracketDelta(_ s: String) -> Int {
            var delta = 0
            for ch in s {
                if ch == "[" { delta += 1 }
                else if ch == "]" { delta -= 1 }
            }
            return delta
        }

        func flushPendingBlock() {
            guard let keyword = pendingBlockKeyword else { return }
            let text = pendingBlockBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            switch keyword {
            case "header":
                break
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
                    } else {
                        // No inline [marker] was found in the line text, so
                        // this is a "general" annotation (same concept as
                        // the app's "+ Add annotation" button) -- give it
                        // its own synthetic negative index so it doesn't
                        // collide with any other general annotation on the
                        // same line.
                        let lowestUsed = doc.lines[lastIndex].annotations.map { $0.charIndex }.min() ?? 0
                        let synthetic = min(-1, lowestUsed - 1)
                        doc.lines[lastIndex].annotations.append(
                            ParsedAnnotation(charIndex: synthetic, marker: marker, noteText: text)
                        )
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

            if pendingBlockKeyword == "header" {
                headerDepth += bracketDelta(line)
                if headerDepth <= 0 {
                    flushPendingBlock()
                }
                continue
            }

            let isNewTag = line.hasPrefix("[header:") || line.hasPrefix("[note:") || line.hasPrefix("[lnote:")
                || line.hasPrefix("[ann:") || line.range(of: #"^\[\d{1,2}:\d{2}(\.\d{1,3})?\]"#, options: .regularExpression) != nil

            if isNewTag {
                flushPendingBlock()
            }

            if line.hasPrefix("[header:") {
                pendingBlockKeyword = "header"
                let rest = String(line.dropFirst("[header:".count))
                headerDepth = 1 + bracketDelta(rest)   // 1 accounts for the opening "[" of "[header:" itself
                if headerDepth <= 0 {
                    flushPendingBlock()
                }
                continue
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
                let rest = String(line[line.index(after: closeBracket)...])
                    .trimmingCharacters(in: .whitespaces)
                pendingBlockKeyword = "ann"
                pendingAnnMarker = marker
                pendingBlockBuffer = rest
                
                flushPendingBlock()
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
                let body = String(line[match.upperBound...])
                let (cleanText, annotations) = extractInlineAnnotations(body)
                doc.lines.append(ParsedLyricLine(timeMs: timeMs, text: cleanText, annotations: annotations))
                continue
            }

            // Untimed lyric line (case 2): no timestamp anywhere in the
            // document. Any non-blank line that isn't a recognized `[...]`
            // tag is treated as a plain lyric line. Mixed documents (some
            // lines timed, some not) aren't a supported input -- each line
            // is still just judged on its own, so it degrades reasonably,
            // but there's no dedicated handling for that combination.
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if !trimmedLine.isEmpty && !trimmedLine.hasPrefix("[") {
                let (cleanText, annotations) = extractInlineAnnotations(trimmedLine)
                doc.lines.append(ParsedLyricLine(timeMs: nil, text: cleanText, annotations: annotations))
                continue
            }

            // Blank/unrecognized lines are ignored.
        }

        flushPendingBlock()
        return doc
    }

    /// Strips inline `[marker]` tags out of a line's text, recording the
    /// character index (in the *cleaned* text) each one was attached to.
    /// Shared by both the timestamped and untimed lyric-line branches so
    /// annotation placement behaves identically either way.
    private static func extractInlineAnnotations(_ text: String) -> (String, [ParsedAnnotation]) {
        var body = text
        var annotations: [ParsedAnnotation] = []
        while let bracketRange = body.range(of: #"\[[^\[\]:]+\]"#, options: .regularExpression) {
            let marker = String(body[bracketRange].dropFirst().dropLast())
            let charIndex = body.distance(from: body.startIndex, to: bracketRange.lowerBound) - 1
            annotations.append(ParsedAnnotation(charIndex: max(charIndex, 0), marker: marker))
            body.removeSubrange(bracketRange)
        }
        return (body, annotations)
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
        var out = "[header: =============================================\n"
                + "[note: 미야자와 겐지의 소설 『바람의 마타사부로』에서 모티브를 얻었다.]\n"
                + "[03:00.10] 悲しみも夢も全て飛ばしてゆけ、又三郎[借]\n"
                + "[ann:借] 『바람의 마타사부로』에서 차용\n"
                + "[lnote: 마타사부로의 내용을 재해석 한 것]\n"
                + "=====================================================]\n\n"
                
        if !doc.songNote.isEmpty {
            out += "[note: \(doc.songNote)]\n\n"
        }
        for line in doc.lines {
            var text = line.text
            // Re-insert inline markers at their recorded character index,
            // highest index first so earlier insertions don't shift later
            // ones. Negative indices are "general" annotations (not tied to
            // a letter) and never get an inline tag -- only the standalone
            // [ann:marker] line below.
            for ann in line.annotations.filter({ $0.charIndex >= 0 }).sorted(by: { $0.charIndex > $1.charIndex }) {
                let insertAt = text.index(text.startIndex, offsetBy: min(ann.charIndex + 1, text.count))
                text.insert(contentsOf: "[\(ann.marker)]", at: insertAt)
            }
            // No timestamp -> no tag at all (case 2), rather than a
            // placeholder like "[--:--]" that the parser can't read back.
            if let ms = line.timeMs {
                out += "\(formatTimeTag(ms)) \(text)\n"
            } else {
                out += "\(text)\n"
            }
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

#if DEBUG
/// Not called automatically -- run this from a debug button or the
/// Xcode console (`po LyricNoteTextFormat.selfCheck()`) if you want to
/// eyeball the parse -> serialize round-trip.
extension LyricNoteTextFormat {
    static func selfCheck() -> String {
        let sample = """
        [note: A song about missing someone during a long winter.
        Written from the perspective of someone who's already left.]

        [00:12.34] 안녕하세요[1] 오늘도 좋은 날
        [ann:1] "hello" -- formal register, sets a polite distant tone
        [ann:general] This whole line is a callback to the album's opening track
        [lnote: This line sets up the whole first verse's contrast between politeness and loneliness]

        [00:15.80] (end)
        """

        let parsed = parse(sample)
        var out = "=== PARSED (timed) ===\n"
        out += "Song note: \(parsed.songNote)\n"
        for line in parsed.lines {
            out += "Line @\(line.timeMs.map(String.init) ?? "nil")ms: \"\(line.text)\"\n"
            for ann in line.annotations {
                out += "  annotation[\(ann.marker)] at char \(ann.charIndex): \(ann.noteText)\n"
            }
            if !line.lineNote.isEmpty { out += "  line note: \(line.lineNote)\n" }
        }
        out += "\n=== RE-SERIALIZED (timed) ===\n"
        out += serialize(parsed)

        // Case 2: untimed lyrics -- this is exactly what was broken before
        // (serialize used to emit an unparseable "[--:--]" placeholder).
        let untimedSample = """
        안녕하세요[1] 오늘도 좋은 날
        [ann:1] "hello" -- formal register
        다음 소절
        """
        let untimedParsed = parse(untimedSample)
        out += "\n=== PARSED (untimed) ===\n"
        out += "Line count: \(untimedParsed.lines.count)\n"
        for line in untimedParsed.lines {
            out += "Line (timeMs=\(line.timeMs.map(String.init) ?? "nil")): \"\(line.text)\"\n"
        }
        out += "\n=== RE-SERIALIZED (untimed) ===\n"
        out += serialize(untimedParsed)

        return out
    }
}
#endif
