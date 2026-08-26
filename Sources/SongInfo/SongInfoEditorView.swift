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
    @State private var saveError: String? = nil
    @State private var webViewBox = WebViewBox()

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
        ) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
        .onAppear { sourceDraft = appState.songInfoSource ?? "" }
        .onChange(of: appState.songInfoSource) { newValue in
            onlineFailed = false
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
            
            // Provide the saved source URL (or a fallback) to mock the live environment
            let originalURL = URL(string: appState.songInfoSource ?? "https://namu.wiki")
            
            HTMLWebView(source: .localWebArchive(
                fileURL: folder.appendingPathComponent("offline.webarchive"),
                originalURL: originalURL
            ))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(10)
        } else {
            HTMLWebView(source: .remoteURL(defaultURL), onNavigationFailure: { }, webViewBox: webViewBox)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(10)
//            fallbackTextOrEmpty
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

    private static func folderURL(documentID: String) throws -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MusicExplorer", isDirectory: true)
            .appendingPathComponent(documentID, isDirectory: true)
    }
}
