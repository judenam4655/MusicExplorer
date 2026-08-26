import Foundation

/// Placeholder. Musixmatch's official public API only returns partial lyrics
/// and doesn't expose synced lyrics or translations to third-party apps --
/// that requires a commercial partner agreement. Getting full data any other
/// way means depending on a private, reverse-engineered endpoint, which this
/// project deliberately does not implement.
///
/// This provider returns nil so LyricsRepository just falls through to
/// LRCLibProvider. If you later get legitimate Musixmatch partner API
/// credentials, implement fetchLyrics here against their documented,
/// authorized endpoints.
final class MusixmatchProvider: LyricsProvider {
    func fetchLyrics(for query: TrackQuery) async -> LyricsFetchState {
        return .notFound
    }
    
    let name = "musixmatch"

    func fetchLyrics(for query: TrackQuery) async throws -> LyricsResult? {
        return nil
    }
}
