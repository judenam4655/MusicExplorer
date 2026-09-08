import Foundation

/// Parses the Lyric Sync editor's raw text buffer into "blocks" -- the same
/// unit `SyncBlock` used to represent (one timestamp, one chunk of text
/// that may itself span a couple of physical lines for original+
/// translation). This replaces the old per-block `ForEach` of live text
/// fields: instead of one persistent SwiftUI view per block, the whole
/// buffer is just a `String` and this is a pure function over it, called on
/// demand (on save, on each spacebar sync, and to draw the small sync
/// status line) rather than kept as live view state.
///
/// Handles the input shapes the editor needs to support:
///
/// 1. **Timed**: every block's first line starts with `[mm:ss.xx]`.
///
///      [00:12.34] 첫 줄
///      번역
///
///      [00:15.80] (end)
///
/// 2. **Untimed**: no line anywhere has a timestamp tag; blocks are plain
///    lyric text.
///
/// 3. **Paragraphs / Single Line**: if blank lines exist (and `ignoreBlankLines` is false),
///    blank lines separate blocks. If `ignoreBlankLines` is true (Single Line mode),
///    every single non-empty physical line is evaluated as its own independent block.
struct RawLyricsBlock {
    var timeMs: Int?
    var text: String        // may contain an embedded "\n" for a 2nd/3rd line (e.g. translation)
    var firstLineIndex: Int // index into the ORIGINAL full \n-split line array; used to place a timestamp back into the raw buffer
}

enum RawLyricsParser {

    static func parseBlocks(_ raw: String, ignoreBlankLines: Bool = false) -> [RawLyricsBlock] {
        let allLines = raw.components(separatedBy: "\n")
        
        if ignoreBlankLines {
            var blocks: [RawLyricsBlock] = []
            for (i, rawLine) in allLines.enumerated() {
                let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                blocks.append(makeBlock(lines: [trimmed], firstLineIndex: i))
            }
            return blocks
        }

        let hasBlankLine = allLines.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }

        var blocks: [RawLyricsBlock] = []

        if hasBlankLine {
            // Rule 3: blank lines delimit blocks; lines between them stay joined.
            var currentLines: [String] = []
            var currentStart: Int? = nil
            for (i, rawLine) in allLines.enumerated() {
                let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    if let start = currentStart, !currentLines.isEmpty {
                        blocks.append(makeBlock(lines: currentLines, firstLineIndex: start))
                    }
                    currentLines = []
                    currentStart = nil
                } else {
                    if currentStart == nil { currentStart = i }
                    currentLines.append(trimmed)
                }
            }
            if let start = currentStart, !currentLines.isEmpty {
                blocks.append(makeBlock(lines: currentLines, firstLineIndex: start))
            }
        } else {
            // No blank lines anywhere: every physical line is its own block.
            for (i, rawLine) in allLines.enumerated() {
                let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                blocks.append(makeBlock(lines: [trimmed], firstLineIndex: i))
            }
        }

        return blocks
    }

    private static func makeBlock(lines: [String], firstLineIndex: Int) -> RawLyricsBlock {
        guard let first = lines.first, let (ms, rest) = extractTimestamp(first) else {
            return RawLyricsBlock(timeMs: nil, text: lines.joined(separator: "\n"), firstLineIndex: firstLineIndex)
        }
        var rewritten = lines
        rewritten[0] = rest
        return RawLyricsBlock(timeMs: ms, text: rewritten.joined(separator: "\n"), firstLineIndex: firstLineIndex)
    }

    /// If `line` starts with a `[mm:ss.xx]`-shaped tag, returns the parsed
    /// milliseconds and the remaining text with the tag (and one following
    /// space) stripped off. Reuses `LRCTimeFormatter` for the actual
    /// mm:ss.xx parsing so this always agrees with the rest of the app on
    /// what's a valid time string.
    private static func extractTimestamp(_ line: String) -> (Int, String)? {
        guard let match = line.range(of: #"^\[([^\]]+)\]\s*"#, options: .regularExpression) else { return nil }
        let tagContent = String(line[match])
            .trimmingCharacters(in: CharacterSet(charactersIn: "[] \t"))
        guard let ms = LRCTimeFormatter.stringToMs(tagContent) else { return nil }
        return (ms, String(line[match.upperBound...]))
    }

    /// Rewrites the physical line at `firstLineIndex` in `raw` to carry `ms`
    /// as its timestamp, replacing whatever tag (if any) it already had.
    /// Used by the spacebar sync action -- a targeted string edit instead
    /// of touching any SwiftUI view state per block.
    static func applyingTimestamp(_ ms: Int, atLineIndex firstLineIndex: Int, to raw: String) -> String {
        var lines = raw.components(separatedBy: "\n")
        guard lines.indices.contains(firstLineIndex) else { return raw }
        let stripped = stripTimestamp(lines[firstLineIndex])
        let tag = "[\(LRCTimeFormatter.msToString(ms))]"
        lines[firstLineIndex] = stripped.isEmpty ? tag : "\(tag) \(stripped)"
        return lines.joined(separator: "\n")
    }

    private static func stripTimestamp(_ line: String) -> String {
        guard let (_, rest) = extractTimestamp(line) else {
            return line.trimmingCharacters(in: .whitespaces)
        }
        return rest
    }
}
