import Foundation

enum LRCParser {
    struct TimedIndex { let index: Int; let timeMs: Int }
    
    static func timedIndices(for lines: [LyricLine]) -> [TimedIndex] {
        lines.enumerated().compactMap { idx, line in
            line.timeMs.map { TimedIndex(index: idx, timeMs: $0) }
        }
    }
    
    static func currentLineIndex(in timed: [TimedIndex], atMs positionMs: Int) -> Int? {
        guard !timed.isEmpty else { return nil }
        var lo = 0, hi = timed.count - 1, result: Int? = nil
        while lo <= hi {
            let mid = (lo + hi) / 2
            if timed[mid].timeMs <= positionMs { result = timed[mid].index; lo = mid + 1 }
            else { hi = mid - 1 }
        }
        return result
    }
    
    private static let linePattern = #"^\[(\d{2}):(\d{2})(?:\.(\d{1,3}))?\](.*)$"#

    static func parse(_ raw: String) -> [LyricLine] {
        guard let regex = try? NSRegularExpression(pattern: linePattern) else { return [] }
        var lines: [LyricLine] = []

        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(rawLine)
            let range = NSRange(s.startIndex..., in: s)

            guard let match = regex.firstMatch(in: s, range: range) else {
                // No [mm:ss.xx] prefix — keep it as an untimed line instead
                // of discarding it.
                let text = s.trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    lines.append(LyricLine(timeMs: nil, text: text))
                }
                continue
            }

            func group(_ idx: Int) -> String? {
                guard let r = Range(match.range(at: idx), in: s) else { return nil }
                return String(s[r])
            }
            guard let minStr = group(1), let secStr = group(2) else { continue }
            let minutes = Int(minStr) ?? 0
            let seconds = Int(secStr) ?? 0
            let msFraction = group(3)
                .flatMap { Int($0.padding(toLength: 3, withPad: "0", startingAt: 0)) } ?? 0
            let text = group(4)?.trimmingCharacters(in: .whitespaces) ?? ""

            let timeMs = (minutes * 60 + seconds) * 1000 + msFraction
            lines.append(LyricLine(timeMs: timeMs, text: text))
        }

        // No longer sorted here — line order now comes straight from the
        // source text, which keeps untimed lines anchored to the timed
        // line they were saved next to instead of being reshuffled.
        return lines
    }

    /// Binary search for the line that should be highlighted at `positionMs`.
    /// Returns the index of the last line whose timestamp is <= positionMs.
//    static func currentLineIndex(in lines: [LyricLine], atMs positionMs: Int) -> Int? {
//        let timed = lines.enumerated().compactMap { idx, line in
//            line.timeMs.map { (index: idx, timeMs: $0) }
//        }
//        guard !timed.isEmpty else { return nil }
//
//        var lo = 0, hi = timed.count - 1, result: Int? = nil
//        while lo <= hi {
//            let mid = (lo + hi) / 2
//            if timed[mid].timeMs <= positionMs {
//                result = timed[mid].index
//                lo = mid + 1
//            } else {
//                hi = mid - 1
//            }
//        }
//        return result
//    }
}
