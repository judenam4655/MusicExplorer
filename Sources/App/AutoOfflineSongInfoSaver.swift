//
//  AutoOfflineSongInfoSaver.swift
//  MusicExplorer
//
//  Created by Juhyeon Nam on 9/12/26.
//

import Foundation
import WebKit

// MARK: - TEMPORARY FEATURE — safe to delete wholesale later
//
// Auto-backfills offline song-info copies for a known batch of songs the
// first time each one is actually played, using a title -> markdown-link
// lookup table you provide. Once you've played through everything you care
// about, delete this file and the one call site in AppServices.swift
// (search for "AutoOfflineSongInfoSaver") and you're fully back to normal.
//
// Runs the same "load in an offscreen WKWebView, wait for it to settle, save
// as .webarchive" pipeline as the manual "Save Offline Copy" button in
// SongInfoEditorView, just triggered automatically instead of by a click.

final class AutoOfflineSongInfoSaver {
    static let shared = AutoOfflineSongInfoSaver()
    private init() {}

    /// title -> markdown-style link string, e.g.
    /// "[https://namu.wiki/](https://namu.wiki/w/...(...))". Set this once
    /// at startup, e.g. `AutoOfflineSongInfoSaver.shared.songLinks = songLinks`.
    var songLinks: [String: String] = [
        "カトレア": "https://namu.wiki/w/%EC%B9%B4%ED%8B%80%EB%A0%88%EC%95%BC(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "言って。": "https://namu.wiki/w/%EB%A7%90%ED%95%B4%EC%A4%98.(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "あの夏に咲け": "https://namu.wiki/w/%EA%B7%B8%20%EC%97%AC%EB%A6%84%EC%97%90%20%ED%94%BC%EC%96%B4%EB%9D%BC",
        "靴の花火": "https://namu.wiki/w/%EA%B5%AC%EB%91%90%EC%9D%98%20%EB%B6%88%EA%BD%83",
        "雲と幽霊": "https://namu.wiki/w/%EA%B5%AC%EB%A6%84%EA%B3%BC%20%EC%9C%A0%EB%A0%B9",
        "負け犬にアンコールはいらない": "https://namu.wiki/w/%ED%8C%A8%EB%B0%B0%EC%9E%90%EC%97%90%EA%B2%8C%20%EC%95%B5%EC%BD%9C%EC%9D%80%20%ED%95%84%EC%9A%94%20%EC%97%86%EC%96%B4",
        "爆弾魔": "https://namu.wiki/w/%ED%8F%AD%ED%83%84%EB%A7%88(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "ヒッチコック": "https://namu.wiki/w/%ED%9E%88%EC%B9%98%EC%BD%95",
        "準透明少年": "https://namu.wiki/w/%EC%A4%80%ED%88%AC%EB%AA%85%20%EC%86%8C%EB%85%84",
        "ただ君に晴れ": "https://namu.wiki/w/%EA%B7%B8%EC%A0%80%20%EB%84%A4%EA%B2%8C%20%EB%A7%91%EC%95%84%EB%9D%BC",
        "冬眠": "https://namu.wiki/w/%EA%B2%A8%EC%9A%B8%EC%9E%A0(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",

        "藍二乗": "https://namu.wiki/w/%EC%AA%BD%EB%B9%9B%20%EC%A0%9C%EA%B3%B1",
        "八月、某、月明かり": "https://namu.wiki/w/8%EC%9B%94%2C%20%EB%88%84%EA%B5%B0%EA%B0%80%2C%20%EB%8B%AC%EB%B9%9B",
        "詩書きとコーヒー": "https://namu.wiki/w/%EC%8B%9C%20%EC%93%B0%EA%B8%B0%EC%99%80%20%EC%BB%A4%ED%94%BC",
        "踊ろうぜ": "https://namu.wiki/w/%EC%B6%A4%EC%B6%94%EC%9E%90(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "六月は雨上がりの街を書く": "https://namu.wiki/w/6%EC%9B%94%EC%9D%80%20%EB%B9%84%20%EA%B0%A0%20%EB%92%A4%EC%9D%98%20%EA%B1%B0%EB%A6%AC%EB%A5%BC%20%EC%93%B4%EB%8B%A4",
        "五月は花緑青の窓辺から": "https://namu.wiki/w/5%EC%9B%94%EC%9D%80%20%ED%99%94%EB%A1%9D%EC%B2%AD%EC%9D%98%20%EC%B0%BD%EA%B0%80%EC%97%90%EC%84%9C",
        "夜紛い": "https://namu.wiki/w/%EB%B0%A4%EC%9D%98%20%EB%AA%A8%EC%A1%B0%ED%92%88",
        "パレード": "https://namu.wiki/w/%ED%8D%BC%EB%A0%88%EC%9D%B4%EB%93%9C(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "エルマ": "https://namu.wiki/w/%EC%97%98%EB%A7%88(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "だから僕は音楽を辞めた": "https://namu.wiki/w/%EA%B7%B8%EB%9E%98%EC%84%9C%20%EB%82%98%EB%8A%94%20%EC%9D%8C%EC%95%85%EC%9D%84%20%EA%B7%B8%EB%A7%8C%EB%91%90%EC%97%88%EB%8B%A4",

        "憂一乗": "https://namu.wiki/w/%EC%9A%B0%EC%9D%BC%EC%8A%B9",
        "夕凪、某、花惑い": "https://namu.wiki/w/%EC%9C%A0%EB%82%98%EA%B8%B0%2C%20%EB%88%84%EA%B5%B0%EA%B0%80%2C%20%EA%BD%83%EC%9D%98%20%ED%98%84%ED%98%B9",
        "雨とカプチーノ": "https://namu.wiki/w/%EB%B9%84%EC%99%80%20%EC%B9%B4%ED%91%B8%EC%B9%98%EB%85%B8",
        "神様のダンス": "https://namu.wiki/w/%EC%8B%A0%EC%9D%98%20%EC%B6%A4(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "雨晴るる": "https://namu.wiki/w/%EB%B9%84%20%EA%B0%A0%20%EB%92%A4(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "歩く": "https://namu.wiki/w/%EA%B1%B7%EB%8B%A4(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "心に穴が空いた": "https://namu.wiki/w/%EB%A7%88%EC%9D%8C%EC%97%90%20%EA%B5%AC%EB%A9%8D%EC%9D%B4%20%EB%9A%AB%EB%A0%B8%EC%96%B4",
        "声": "https://namu.wiki/w/%EB%AA%A9%EC%86%8C%EB%A6%AC(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "エイミー": "https://namu.wiki/w/%EC%97%90%EC%9D%B4%EB%AF%B8(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "ノーチラス": "https://namu.wiki/w/%EB%85%B8%ED%8B%B8%EB%9F%AC%EC%8A%A4(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",

        "昼鳶": "https://namu.wiki/w/%EB%82%AE%EB%8F%84%EB%91%91",
        "春ひさぎ": "https://namu.wiki/w/%EB%B4%84%ED%8C%94%EC%9D%B4",
        "レプリカント": "https://namu.wiki/w/%EB%A0%88%ED%94%8C%EB%A6%AC%EC%B9%B8%ED%8A%B8(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "花人局": "https://namu.wiki/w/%EB%AF%B8%EC%9D%B8%EA%B3%84(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "盗作": "https://namu.wiki/w/%EB%8F%84%EC%9E%91",
        "思想犯": "https://namu.wiki/w/%EC%82%AC%EC%83%81%EB%B2%94",
        "逃亡": "https://namu.wiki/w/%EB%8F%84%EB%A7%9D(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "夜行": "https://namu.wiki/w/%EC%95%BC%ED%96%89(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "花に亡霊": "https://namu.wiki/w/%EA%BD%83%EC%97%90%20%EB%A7%9D%EB%A0%B9",

        "強盗と花束": "https://namu.wiki/w/%EA%B0%95%EB%8F%84%EC%99%80%20%EA%BD%83%EB%8B%A4%EB%B0%9C",
        "春泥棒": "https://namu.wiki/w/%EB%B4%84%20%EB%8F%84%EB%91%91",
        "風を食む": "https://namu.wiki/w/%EB%B0%94%EB%9E%8C%EC%9D%84%20%EB%A8%B9%EB%8B%A4",
        "嘘月": "https://namu.wiki/w/%EA%B1%B0%EC%A7%93%EB%A7%90%EC%9F%81%EC%9D%B4",

        "又三郎": "https://namu.wiki/w/%EB%A7%88%ED%83%80%EC%82%AC%EB%B6%80%EB%A1%9C(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "老人と海": "https://namu.wiki/w/%EB%85%B8%EC%9D%B8%EA%B3%BC%20%EB%B0%94%EB%8B%A4(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "月に吠える": "https://namu.wiki/w/%EB%8B%AC%EC%97%90%20%EC%A7%96%EB%8B%A4(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "ブレーメン": "https://namu.wiki/w/%EB%B8%8C%EB%A0%88%EB%A9%98(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "左右盲": "https://namu.wiki/w/%EC%A2%8C%EC%9A%B0%EB%A7%B9(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "チノカテ": "https://namu.wiki/w/%EC%B9%98%EB%85%B8%EC%B9%B4%ED%85%8C",
        "テレパス": "https://namu.wiki/w/%ED%85%94%EB%A0%88%ED%8C%A8%EC%8A%A4(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "アルジャーノン": "https://namu.wiki/w/%EC%95%A8%EC%A0%80%EB%84%8C(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "451": "https://namu.wiki/w/451(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "都落ち": "https://namu.wiki/w/%EB%82%99%ED%96%A5(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "斜陽": "https://namu.wiki/w/%EC%82%AC%EC%96%91(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "月光浴": "https://namu.wiki/w/%EC%9B%94%EA%B4%91%EC%9A%95(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",

        "夏の肖像": "https://namu.wiki/w/%EC%97%AC%EB%A6%84%EC%9D%98%20%EC%B4%88%EC%83%81",
        "雪国": "https://namu.wiki/w/%EC%84%A4%EA%B5%AD(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "パドドゥ": "https://namu.wiki/w/%ED%8C%8C%20%EB%93%9C%20%EB%90%98(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "さよならモルテン": "https://namu.wiki/w/%EC%95%88%EB%85%95%20%EB%AA%A8%EB%A5%B4%ED%85%90",
        "いさな": "https://namu.wiki/w/%EA%B3%A0%EB%9E%98(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",

        "晴る": "https://namu.wiki/w/%EB%A7%91%EC%9D%80%20%EB%82%A0(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "ルバート": "https://namu.wiki/w/%EB%A3%A8%EB%B0%94%ED%86%A0(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "忘れてください": "https://namu.wiki/w/%EC%9E%8A%EC%96%B4%EC%A3%BC%EC%84%B8%EC%9A%94(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "アポリア": "https://namu.wiki/w/%EC%95%84%ED%8F%AC%EB%A6%AC%EC%95%84(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "太陽": "https://namu.wiki/w/%ED%83%9C%EC%96%91(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "へび": "https://namu.wiki/w/%EB%B1%80(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "火星人": "https://namu.wiki/w/%ED%99%94%EC%84%B1%EC%9D%B8(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "修羅": "https://namu.wiki/w/%EC%88%98%EB%9D%BC(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "プレイシック": "https://namu.wiki/w/%ED%94%8C%EB%A0%88%EC%9D%B4%20%EC%8B%9D",
        "茜": "https://namu.wiki/w/%EC%95%84%EC%B9%B4%EB%84%A4(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "あぶく": "https://namu.wiki/w/%EB%AC%BC%EB%96%BC%EC%83%88(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",

        "雲になる": "https://namu.wiki/w/%EA%B5%AC%EB%A6%84%EC%9D%B4%20%EB%90%98%EB%8B%A4(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "花も騒めく": "https://namu.wiki/w/%EA%BD%83%EB%8F%84%20%EC%88%A0%EB%A0%81%EC%9D%B4%EB%84%A4",
        "魔性": "https://namu.wiki/w/%EB%A7%88%EC%84%B1(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "ポスト春": "https://namu.wiki/w/%ED%8F%AC%EC%8A%A4%ED%8A%B8%20%EB%B4%84",
        "火葬": "https://namu.wiki/w/%ED%99%94%EC%9E%A5(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "うめき": "https://namu.wiki/w/%EC%8B%A0%EC%9D%8C(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "啄木鳥": "https://namu.wiki/w/%EB%94%B1%EB%94%B0%EA%B5%AC%EB%A6%AC(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "千鳥": "https://namu.wiki/w/%EB%AC%BC%EB%96%BC%EC%83%88(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",
        "櫂": "https://namu.wiki/w/%EB%85%B8(%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4)",

        "Make-up Shadow": "https://namu.wiki/w/Make-up%20Shadow",
        "憂、燦々": "https://namu.wiki/w/%EC%9A%B0%2C%20%EC%82%B0%EC%82%B0",
        "DARMA GRAND PRIX": "https://namu.wiki/w/DARMA%20GRAND%20PRIX"
    ]


    /// Tracks which trackIds we've already tried this app run, so replaying
    /// the same song doesn't repeat the work (and doesn't repeatedly hit the
    /// disk/DB check either) even before a save has actually succeeded.
    private var attemptedTrackIDs = Set<String>()

    /// Call this from AppServices whenever the current track changes.
    /// Everything here is cheap-and-bail-early except the one branch that
    /// actually does a save, so it's safe to call unconditionally per track
    /// change (this is still the part you're deleting later, per your note
    /// about it costing performance to keep running after the backfill is done).
    func handle(track: Track, services: AppServices) {
        // TODO: verify `track.title` is the actual property name on your
        // Track type — I don't have Track.swift, so this is a guess. If the
        // real property is e.g. `track.name`, this is the only line to fix.
        let title = track.title

        guard !attemptedTrackIDs.contains(track.id) else { return }
        guard let rawLink = songLinks[title], let url = Self.extractURL(from: rawLink) else { return }
        attemptedTrackIDs.insert(track.id)

        // Already has a saved source/offline copy for this track? Nothing to do.
        if services.songInfoStore.get(trackId: track.id) != nil { return }

        Task {
            do {
                let archiveData = try await Self.downloadWebArchive(url: url)
                let documentID = UUID().uuidString
                let folder = try Self.folderURL(documentID: documentID)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let fileURL = folder.appendingPathComponent("offline.webarchive")
                try archiveData.write(to: fileURL, options: .atomic)

                await MainActor.run {
                    services.songInfoStore.save(
                        trackId: track.id,
                        source: url.absoluteString,
                        content: "[WebArchive]",
                        documentID: documentID
                    )
                }
                print("[AutoOfflineSongInfoSaver] saved offline copy for \(title)")
            } catch {
                // Deliberately not retried this run -- attemptedTrackIDs already
                // marked it, so a flaky network hiccup just means "no offline
                // copy for this one today" rather than hammering it on every replay.
                print("[AutoOfflineSongInfoSaver] failed for \(title): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Link parsing

    /// Pulls the URL out of a "[label](url)" markdown link, matching
    /// balanced parens rather than stopping at the first ")" -- needed
    /// because the sample data has literal, unescaped parens *inside* the
    /// URL itself (e.g. ".../%EC%B9%B4...(%EC%9A%94...)"). Falls back to
    /// treating the whole string as a bare URL if it isn't markdown-link shaped.
    private static func extractURL(from raw: String) -> URL? {
        guard let markerRange = raw.range(of: "](") else {
            return URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var depth = 1
        var idx = markerRange.upperBound
        let start = idx
        while idx < raw.endIndex {
            let ch = raw[idx]
            if ch == "(" { depth += 1 }
            else if ch == ")" {
                depth -= 1
                if depth == 0 { break }
            }
            idx = raw.index(after: idx)
        }
        guard idx < raw.endIndex else { return nil }
        return URL(string: String(raw[start..<idx]))
    }

    // MARK: - Paths (mirrors SongInfoEditorView.folderURL)

    private static func folderURL(documentID: String) throws -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MusicExplorer", isDirectory: true)
            .appendingPathComponent(documentID, isDirectory: true)
    }

    // MARK: - Offscreen archive download (mirrors SongInfoEditorView's private helper)

    private static func downloadWebArchive(url: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            // WKWebView/WKWebViewConfiguration must be created on the main
            // thread -- the enclosing `Task { ... }` in handle(track:services:)
            // does NOT guarantee that, so without this hop, constructing
            // OnePageWebArchiveDelegate off-main trips WebKit's internal
            // main-thread assertion (surfaces as EXC_BREAKPOINT).
            Task { @MainActor in
                let delegate = OnePageWebArchiveDelegate(url: url) { result in
                    continuation.resume(with: result)
                }
                delegate.start()
            }
        }
    }

    @MainActor
    private final class OnePageWebArchiveDelegate: NSObject, WKNavigationDelegate {
        let webView: WKWebView
        let targetURL: URL
        let completion: (Result<Data, Error>) -> Void
        private var finished = false

        init(url: URL, completion: @escaping (Result<Data, Error>) -> Void) {
            self.targetURL = url
            self.completion = completion
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .default()
            // Same Safe Browsing caveat as HTMLWebView: without this, a
            // provisional navigation to a real https URL can eat a live
            // network round-trip against Apple's servers before your own
            // request even goes out.
            configuration.preferences.setValue(false, forKey: "safeBrowsingEnabled")
            self.webView = WKWebView(frame: .zero, configuration: configuration)
            super.init()
            self.webView.navigationDelegate = self
        }

        func start() {
            webView.load(URLRequest(url: targetURL, cachePolicy: .reloadIgnoringLocalCacheData))
            selfKeepAlive = self
        }

        private var selfKeepAlive: OnePageWebArchiveDelegate?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak webView] in
                guard let self, let webView, !self.finished else { return }
                self.finished = true
                webView.createWebArchiveData { [weak self] result in
                    guard let self else { return }
                    self.completion(result)
                    self.selfKeepAlive = nil
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finish(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            finish(error)
        }

        private func finish(_ error: Error) {
            guard !finished else { return }
            finished = true
            completion(.failure(error))
            selfKeepAlive = nil
        }
    }
}
