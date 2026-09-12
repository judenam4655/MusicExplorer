import SwiftUI
import WebKit
import UniformTypeIdentifiers
 
/// Song info panel, two functions per your split:
///  - representation: renders saved HTML via HTMLWebView
///  - editor: raw HTML text editor, filled either by pasting directly or by
///    loading a dropped/imported .html file
struct SongInfoEditorView: View {
    @EnvironmentObject var appState: AppState
    @State private var isEditing = false
    @State private var draftText: String = ""
    @State private var isDropTargeted = false
    @State private var showFileImporter = false
    @State private var importError: String? = nil
    @State private var sourceDraft: String = ""
    @State private var isSavingOfflineCopy = false
    @State private var onlineFailed = false
    @State private var defaultOnlineFailed = false
    @State private var saveError: String? = nil
    @State private var webViewBox = WebViewBox()
    @State private var isSavingYorushikaPages = false
    @State private var yorushikaSaveStatus: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            sourceRow
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.html, .plainText],
            allowsMultipleSelection: false
        ) { handleFileImportResult($0) }
        .alert(
            "Couldn't load file",
            isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
        ) {
            Button("OK", role: .cancel) { importError = nil }
        } message: { Text(importError ?? "") }
        .alert(
            "Couldn't save offline copy",
            isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
        )
        {
            Button("OK", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
//        .alert(
//            "Yorushika pages",
//            isPresented: Binding(
//                get: { yorushikaSaveStatus != nil },
//                set: { if !$0 { yorushikaSaveStatus = nil } }
//            )
//        ) {
//            Button("OK", role: .cancel) { yorushikaSaveStatus = nil }
//        } message: {
//            Text(yorushikaSaveStatus ?? "")
//        }
        .onAppear { sourceDraft = appState.songInfoSource ?? ""; defaultOnlineFailed = false }
        .onChange(of: appState.songInfoSource) { newValue in
            onlineFailed = false
            defaultOnlineFailed = false
            sourceDraft = newValue ?? ""
        }
    }

    private var header: some View {
        HStack {
            Text("Song Info").font(.headline)
            Spacer()
            if isEditing {
                Button {
                    showFileImporter = true
                } label: {
                    Label("Import File", systemImage: "doc.badge.plus")
                }
                Button("Save") {
                    appState.services.saveSongInfo(draftText)
                    appState.songInfoText = draftText
                    isEditing = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                if appState.songInfoSource != nil && !onlineFailed {
                    Button {
                        Task { await saveOfflineCopy() }
                    } label: {
                        if isSavingOfflineCopy {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Save Offline Copy", systemImage: "arrow.down.circle")
                        }
                    }
                    .disabled(isSavingOfflineCopy)
                }
//                Button {
//                    Task { await saveAllYorushikaPages() }
//                } label: {
//                    if isSavingYorushikaPages {
//                        ProgressView().controlSize(.small)
//                    } else {
//                        Label("Save Yorushika Pages", systemImage: "arrow.down.doc")
//                    }
//                }
//                .disabled(isSavingYorushikaPages)

                Button("Edit HTML") {
                    draftText = appState.songInfoText ?? ""
                    isEditing = true
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    /// Persistent source-URL field, independent of the paste/drop editor
    /// below. Enter commits it; the content area then tries to load it live.
    private var sourceRow: some View {
        HStack {
            Image(systemName: "link").foregroundStyle(.secondary)
            TextField("Paste a source URL (e.g. a wiki page)...", text: $sourceDraft)
                .textFieldStyle(.plain)
                .onSubmit {
                    let trimmed = sourceDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    let newSource = trimmed.isEmpty ? nil : trimmed
                    appState.services.saveSongInfoSource(newSource)
                    appState.songInfoSource = newSource
                    onlineFailed = false
                }
            if appState.songInfoSource != nil {
                Button {
                    sourceDraft = ""
                    appState.services.saveSongInfoSource(nil)
                    appState.songInfoSource = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        let defaultURL = URL(string: "https://namu.wiki/w/%EC%9A%94%EB%A3%A8%EC%8B%9C%EC%B9%B4")!
        
        if isEditing {
            editorBody
        } else if let sourceString = appState.songInfoSource,
                  let url = URL(string: sourceString),
                  !onlineFailed {
            // ONLINE: navigate live. A navigation failure flips onlineFailed,
            // which drops us into the offline-copy branch below on next render.
            HTMLWebView(source: .remoteURL(url), onNavigationFailure: { onlineFailed = true }, webViewBox: webViewBox)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(10)
        } else if let documentID = appState.songInfoDocumentID,
                  let folder = try? Self.folderURL(documentID: documentID),
                  FileManager.default.fileExists(atPath: folder.appendingPathComponent("offline.webarchive").path) {
            
//            let _ = print("else if in SongINfoEditorView")
            // Provide the saved source URL (or a fallback) to mock the live environment
            let originalURL = URL(string: appState.songInfoSource ?? "https://namu.wiki")
            
            HTMLWebView(source: .localWebArchive(
                fileURL: folder.appendingPathComponent("offline.webarchive"),
                originalURL: originalURL
            ))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(10)
        } else if !defaultOnlineFailed {
            // ONLINE (or not-yet-known): try the real default page first, exactly
            // like the per-song source branch above. A navigation failure flips
            // defaultOnlineFailed, dropping us into the local-archive branch below
            // on the next render -- we don't check that archive's existence until
            // we actually know the live fetch failed.
            HTMLWebView(source: .remoteURL(defaultURL), onNavigationFailure: { defaultOnlineFailed = true }, webViewBox: webViewBox)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(10)
        } else if let rootFolder = try? Self.musicExplorerRootURL(),
                  FileManager.default.fileExists(atPath: rootFolder.appendingPathComponent("offline.webarchive").path) {
            // No per-song source/archive, live default fetch just failed, but a
            // bundled/app-level default archive exists (MusicExplorer/offline.webarchive,
            // not a per-song subfolder). Use it as the offline fallback.
            HTMLWebView(source: .localWebArchive(
                fileURL: rootFolder.appendingPathComponent("offline.webarchive"),
                originalURL: defaultURL
            ))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(10)
        } else {
            // Live default fetch failed and there's no cached default archive to
            // fall back to -- nothing more to try, so say so instead of silently
            // retrying the same doomed live fetch.
            VStack {
                Spacer()
                Image(systemName: "wifi.slash").font(.system(size: 32)).foregroundStyle(.secondary)
                Text("Couldn't reach the default page, and no offline copy is saved.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Manual paste/drop path (no source link involved at all) -- unchanged
    /// from before, backed by the plain `content` text column.
    @ViewBuilder
    private var fallbackTextOrEmpty: some View {
        if let text = appState.songInfoText, !text.isEmpty {
            HTMLWebView(source: .htmlString(text))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(10)
                .overlay(dropOverlay)
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { handleDrop($0) }
        } else {
            emptyStateBody
        }
    }

    private var editorBody: some View {
        TextEditor(text: $draftText)
            .font(.system(.body, design: .monospaced))
            .padding(12)
            .overlay(dropOverlay)
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { handleDrop($0) }
    }

    private var emptyStateBody: some View {
        VStack {
            Spacer()
            Image(systemName: "doc.text").font(.system(size: 32)).foregroundStyle(.secondary)
            Text(appState.songInfoSource == nil
                 ? "No info saved for this track yet."
                 : "Couldn't reach the source, and no offline copy is saved.")
                .foregroundStyle(.secondary)
            Text("Paste a source URL above, drop an HTML file, or hit Edit HTML to paste text.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(dropOverlay)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { handleDrop($0) }
    }

    @ViewBuilder
    private var dropOverlay: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                )
                .allowsHitTesting(false)
        }
    }

    // MARK: - One-time Yorushika page saving

    private struct YorushikaPage {
        let category: String
        let title: String
        let url: URL
        let fileName: String
    }

    /// These are the Namuwiki pages extracted from the supplied Yorushika article.
    /// Each URL is loaded through WebKit and saved as a .webarchive so the saved
    /// page can be reopened with the same HTMLWebView offline mechanism used below.
    private let yorushikaPages: [YorushikaPage] = []

    private func saveAllYorushikaPages() async {
        guard !isSavingYorushikaPages else { return }

        isSavingYorushikaPages = true
        defer { isSavingYorushikaPages = false }

        do {
            // Songs deliberately live directly under MusicExplorer, because the
            // app's song records are independent of the Yorushika artist folder.
            // Biography/album/single pages stay grouped under MusicExplorer/Yorushika.
            let musicExplorerRoot = try Self.musicExplorerRootURL()
            let yorushikaRoot = musicExplorerRoot.appendingPathComponent("Yorushika", isDirectory: true)
            try FileManager.default.createDirectory(at: musicExplorerRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: yorushikaRoot, withIntermediateDirectories: true)

            var localURLByRemoteURL: [String: URL] = [:]
            var outputURLByPageTitle: [String: URL] = [:]

            // Decide every destination first so links can be rewritten to the
            // destination of the target page even when that target is downloaded later.
            for page in yorushikaPages {
                let outputURL: URL
                if page.category == "Song" || page.category == "Single / Other" {
                    // All song/single pages live directly under MusicExplorer.
                    outputURL = musicExplorerRoot.appendingPathComponent(page.fileName)
                } else {
                    let categoryFolder: URL
                    switch page.category {
                    case "Biography":
                        categoryFolder = yorushikaRoot.appendingPathComponent("Biography", isDirectory: true)
                    case "Album":
                        categoryFolder = yorushikaRoot.appendingPathComponent("Albums", isDirectory: true)
                    default:
                        categoryFolder = yorushikaRoot.appendingPathComponent("Singles", isDirectory: true)
                    }
                    try FileManager.default.createDirectory(at: categoryFolder, withIntermediateDirectories: true)
                    outputURL = categoryFolder.appendingPathComponent(page.fileName)
                }

                outputURLByPageTitle[page.title] = outputURL
                localURLByRemoteURL[Self.canonicalPageKey(page.url)] = outputURL
            }

            // Rebuild all archives. Known Namuwiki links inside each downloaded
            // page are changed to file:// links pointing at the corresponding
            // saved archive. Therefore a click works without an internet connection.
            var saved = 0
            var failed: [String] = []

            for page in yorushikaPages {
                guard let outputURL = outputURLByPageTitle[page.title] else { continue }

                do {
                    let archive = try await Self.downloadWebArchive(url: page.url)
                    let patchedArchive = try Self.rewriteSavedPageLinks(
                        in: archive,
                        sourceURL: page.url,
                        localURLByRemoteURL: localURLByRemoteURL
                    )
                    try patchedArchive.write(to: outputURL, options: .atomic)
                    saved += 1
                } catch {
                    failed.append("• \(page.title): \(error.localizedDescription)")
                }
            }

            let summaryPath = "\(musicExplorerRoot.path)\nSongs/singles: MusicExplorer/*.webarchive\nBiography/albums: MusicExplorer/Yorushika/..."
            if failed.isEmpty {
                yorushikaSaveStatus = "Saved \(saved) pages.\n\n\(summaryPath)\n\nKnown page links were rewritten to local archives for offline navigation."
            } else {
                yorushikaSaveStatus = "Saved \(saved) of \(yorushikaPages.count) pages.\n\nFailed:\n\(failed.joined(separator: "\n"))\n\n\(summaryPath)"
            }
        } catch {
            yorushikaSaveStatus = "Couldn't save Yorushika pages:\n\n\(error.localizedDescription)"
        }
    }

    private static func canonicalPageKey(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        if let normalized = components?.url?.absoluteString {
            return normalized
        }
        components?.fragment = nil
        return components?.url?.absoluteString ?? url.absoluteString
    }

    private static func rewriteSavedPageLinks(
        in archiveData: Data,
        sourceURL: URL,
        localURLByRemoteURL: [String: URL]
    ) throws -> Data {
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard var archive = try PropertyListSerialization.propertyList(
            from: archiveData,
            options: [],
            format: &format
        ) as? [String: Any] else {
            throw SongInfoAssetSaverError.fetchFailed("Couldn't read the WebArchive property list.")
        }

        guard var mainResource = archive["WebMainResource"] as? [String: Any],
              let data = mainResource["WebResourceData"] as? Data,
              let html = String(data: data, encoding: .utf8) else {
            return archiveData
        }

        let rewrittenHTML = rewriteHTMLLinks(
            html,
            sourceURL: sourceURL,
            localURLByRemoteURL: localURLByRemoteURL
        )

        guard rewrittenHTML != html else {
            return archiveData
        }

        mainResource["WebResourceData"] = rewrittenHTML.data(using: .utf8) ?? data
        archive["WebMainResource"] = mainResource

        return try PropertyListSerialization.data(
            fromPropertyList: archive,
            format: format,
            options: 0
        )
    }

    private static func rewriteHTMLLinks(
        _ html: String,
        sourceURL: URL,
        localURLByRemoteURL: [String: URL]
    ) -> String {
        // Handle both href="..." and href='...'. We intentionally only
        // rewrite URLs that resolve to one of the pages we saved. External
        // links remain external and therefore retain their normal behavior.
        let patterns = [
            #"(?i)(href\s*=\s*)(\")([^\"]+)(\")"#,
            #"(?i)(href\s*=\s*)(\')([^\']+)(\')"#
        ]

        var result = html
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard match.numberOfRanges == 4,
                      let valueRange = Range(match.range(at: 3), in: result) else { continue }

                let rawValue = String(result[valueRange])
                guard !rawValue.isEmpty,
                      !rawValue.hasPrefix("#"),
                      !rawValue.lowercased().hasPrefix("javascript:"),
                      !rawValue.lowercased().hasPrefix("mailto:") else { continue }

                let resolvedURL: URL?
                if let absolute = URL(string: rawValue), absolute.scheme != nil {
                    resolvedURL = absolute
                } else {
                    resolvedURL = URL(string: rawValue, relativeTo: sourceURL)?.absoluteURL
                }

                guard let resolvedURL else { continue }
                let key = canonicalPageKey(resolvedURL)
                guard let localURL = localURLByRemoteURL[key] else { continue }

                var replacementURL = localURL.absoluteString
                if let fragment = resolvedURL.fragment, !fragment.isEmpty {
                    replacementURL += "#\(fragment)"
                }

                result.replaceSubrange(valueRange, with: replacementURL)
            }
        }
        return result
    }

    private static func downloadWebArchive(url: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let delegate = OnePageWebArchiveDelegate(url: url) { result in
                continuation.resume(with: result)
            }
            delegate.start()
        }
    }

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
            self.webView = WKWebView(frame: .zero, configuration: configuration)
            super.init()
            self.webView.navigationDelegate = self
        }

        func start() {
            webView.load(URLRequest(url: targetURL, cachePolicy: .reloadIgnoringLocalCacheData))
            // Keep this delegate alive until its async navigation/archive work finishes.
            selfKeepAlive = self
        }

        private var selfKeepAlive: OnePageWebArchiveDelegate?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Give scripts/navigation redirects a moment to settle before archiving.
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


    // MARK: - Offline copy saving

    private func saveOfflineCopy() async {
        guard let webView = webViewBox.webView else { return }
        isSavingOfflineCopy = true
        defer { isSavingOfflineCopy = false }

        do {
            let archiveData = try await createWebArchive(from: webView)
            
            let documentID = appState.songInfoDocumentID ?? UUID().uuidString
            let folder = try Self.folderURL(documentID: documentID)
            
            // NEW: Ensure the folders exist before trying to save the file
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            
            let fileURL = folder.appendingPathComponent("offline.webarchive")
            
            // Save the binary archive to disk
            try archiveData.write(to: fileURL, options: .atomic)
            
            appState.services.saveSongInfoOfflineCopy(content: "[WebArchive]", documentID: documentID)
            appState.songInfoText = "[WebArchive]"
            appState.songInfoDocumentID = documentID
        } catch {
            saveError = error.localizedDescription
        }
    }
    
    private func createWebArchive(from webView: WKWebView) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            // Use WebKit's native archive builder
            webView.createWebArchiveData { result in
                switch result {
                case .success(let data):
                    continuation.resume(returning: data)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func evaluateOuterHTML(_ webView: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript("document.documentElement.outerHTML") { result, error in
                if let error { continuation.resume(throwing: error); return }
                guard let html = result as? String else {
                    continuation.resume(throwing: SongInfoAssetSaverError.fetchFailed("Couldn't read the page content."))
                    return
                }
                continuation.resume(returning: html)
            }
        }
    }

    // MARK: - File handling (manual paste/drop path -- unchanged)

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            loadHTML(from: url)
        }
        return true
    }

    private func handleFileImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            loadHTML(from: url)
        case .failure(let error):
            DispatchQueue.main.async { importError = error.localizedDescription }
        }
    }

    private func loadHTML(from url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            DispatchQueue.main.async {
                draftText = content
                isEditing = true
            }
        } catch {
            DispatchQueue.main.async {
                importError = "Couldn't read \(url.lastPathComponent) as text: \(error.localizedDescription)"
            }
        }
    }

    private static func musicExplorerRootURL() throws -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MusicExplorer", isDirectory: true)
    }

    private static func folderURL(documentID: String) throws -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MusicExplorer", isDirectory: true)
            .appendingPathComponent(documentID, isDirectory: true)
    }
}
