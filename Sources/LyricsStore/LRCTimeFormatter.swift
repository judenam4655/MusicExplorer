//
//  LRCTimeFormatter.swift.swift
//  MusicExplorer
//
//  Created by Juhyeon Nam on 8/22/26.
//

import Foundation

struct LRCTimeFormatter {
    /// Converts ms (e.g., 92430) to "01:32.43"
    static func msToString(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let fraction = (ms % 1000) / 10 // 2 digits
        return String(format: "%02d:%02d.%02d", minutes, seconds, fraction)
    }

    /// Converts "01:32.43" or "[01:32.43]" back to milliseconds
    static func stringToMs(_ str: String) -> Int? {
        let clean = str.replacingOccurrences(of: "[", with: "")
                       .replacingOccurrences(of: "]", with: "")
                       .trimmingCharacters(in: .whitespaces)
        
        let parts = clean.split(separator: ":")
        guard parts.count == 2 else { return nil }
        
        let minPart = Int(parts[0]) ?? 0
        let secParts = parts[1].split(separator: ".")
        
        let seconds = Int(secParts[0]) ?? 0
        let msFraction = secParts.count > 1 ? (Int(secParts[1]) ?? 0) * 10 : 0
        
        return (minPart * 60 + seconds) * 1000 + msFraction
    }
}
