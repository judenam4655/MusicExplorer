import Foundation

/// Fetch states
enum LyricsFetchState {
    case success(LyricsResult)
    case notFound
    case timeout
    case error(Error)
}

protocol LyricsProvider {
    var name: String { get }
    func fetchLyrics(for query: TrackQuery) async -> LyricsFetchState
}
