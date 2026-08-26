import Foundation

final class LRCLibProvider: LyricsProvider {
    let name = "lrclib"
    private let session = URLSession.shared
    private let baseURL = "https://lrclib.net/api"

    func fetchLyrics(for query: TrackQuery) async -> LyricsFetchState {
        do {
            if let exact = try await getExact(query) {
                return .success(exact)
            }
            if let fallback = try await searchFallback(query) {
                return .success(fallback)
            }
            return .notFound
        } catch let error as URLError where error.code == .timedOut {
            return .timeout
        } catch {
            return .error(error)
        }
    }

    private func getExact(_ query: TrackQuery) async throws -> LyricsResult? {
        var comps = URLComponents(string: "\(baseURL)/get")!
        comps.queryItems = [
            URLQueryItem(name: "track_name", value: query.title),
            URLQueryItem(name: "artist_name", value: query.artist),
            URLQueryItem(name: "album_name", value: query.album ?? ""),
            URLQueryItem(name: "duration", value: String(query.durationMs / 1000)),
        ]
        guard let url = comps.url else { return nil }

        // Enforce a strict 5-second timeout
        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return try Self.decode(data, source: name)
    }

    private func searchFallback(_ query: TrackQuery) async throws -> LyricsResult? {
        var comps = URLComponents(string: "\(baseURL)/search")!
        comps.queryItems = [
            URLQueryItem(name: "track_name", value: query.title),
            URLQueryItem(name: "artist_name", value: query.artist),
        ]
        guard let url = comps.url else { return nil }

        // Enforce a strict 5-second timeout
        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        
        guard let results = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = results.first,
              let jsonData = try? JSONSerialization.data(withJSONObject: first) else {
            return nil
        }
        return try Self.decode(jsonData, source: name)
    }

    private static func decode(_ data: Data, source: String) throws -> LyricsResult? {
        struct RawResponse: Decodable {
            let syncedLyrics: String?
            let plainLyrics: String?
        }
        let raw = try JSONDecoder().decode(RawResponse.self, from: data)
        let synced = raw.syncedLyrics.map { LRCParser.parse($0) }
        guard synced != nil || raw.plainLyrics != nil else { return nil }
        return LyricsResult(source: source, synced: synced, plainText: raw.plainLyrics, translatedSynced: nil)
    }
}

