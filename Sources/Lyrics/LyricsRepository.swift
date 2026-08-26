import Foundation

final class LyricsRepository {
    private let primaryProviders: [LyricsProvider]
    private let customStore: CustomLyricsStore
    private let cache: LyricsCacheStore

    init(primaryProviders: [LyricsProvider], customStore: CustomLyricsStore, cache: LyricsCacheStore) {
        self.primaryProviders = primaryProviders
        self.customStore = customStore
        self.cache = cache
    }

    func lyrics(for track: Track) async -> LyricsFetchState {
        let translatedLines = customStore.getTranslationLRC(trackId: track.id).map { LRCParser.parse($0) }

        var originalResult: LyricsResult?

        if let customOriginalLRC = customStore.getOriginalLRC(trackId: track.id), !customOriginalLRC.isEmpty {
            let lines = LRCParser.parse(customOriginalLRC)
            originalResult = LyricsResult(source: "custom_local", synced: lines, plainText: nil, translatedSynced: nil)
        }
        // If you don't have custom lyrics, check the cache
        else if let cached = cache.get(trackId: track.id) {
            originalResult = cached
        }
        // If no cache, fetch from the web
        else {
            let query = TrackQuery(
                title: track.title, artist: track.artist,
                album: track.album, durationMs: track.durationMs
            )
            for provider in primaryProviders {
                let state = await provider.fetchLyrics(for: query)
                if case .success(let res) = state, let synced = res.synced, !synced.isEmpty {
                    cache.save(trackId: track.id, result: res)
                    originalResult = res
                    break
                }
            }
        }

        if let original = originalResult {
            let merged = LyricsResult(
                source: original.source,
                synced: original.synced,
                plainText: original.plainText,
                translatedSynced: translatedLines
            )
            return .success(merged)
        }

        if let translatedLines, !translatedLines.isEmpty {
            let translationOnly = LyricsResult(
                source: "custom_local",
                synced: translatedLines,
                plainText: nil,
                translatedSynced: nil
            )
            return .success(translationOnly)
        }

        return .notFound
    }
}
