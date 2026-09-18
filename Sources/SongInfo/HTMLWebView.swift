//
//  HTMLWebView.swift
//  MusicExplorer
//
//  Created by Juhyeon Nam on 8/22/26.
//

import SwiftUI
import WebKit

final class WebViewBox {
    weak var webView: WKWebView?
}

enum Source: Equatable {
    case htmlString(String)
    case remoteURL(URL)
    case localFolder(indexFile: URL, folder: URL)
    case localWebArchive(fileURL: URL, originalURL: URL?)
}

struct HTMLWebView: NSViewRepresentable {
    let source: Source
    var onNavigationFailure: (() -> Void)? = nil
    var webViewBox: WebViewBox? = nil

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // WebKit runs a background "Safe Browsing" / fraudulent-website check
        // against Apple's servers for any navigation it believes targets a real
        // http(s) URL. Loading a .webarchive (mimeType "application/x-webarchive")
        // still counts, because WebKit derives the frame's effective URL from the
        // archive's own embedded WebResourceURL (the live URL recorded when the
        // page was captured) rather than from whatever `baseURL` we pass to
        // `load()`. Offline, that background lookup can't complete, hangs/retries,
        // and eventually surfaces as a generic NSURLErrorDomain -1009 on the main
        // frame's provisional navigation -- even though nothing in *our* content
        // needed the network. This is a private/undocumented WKPreferences key,
        // but it's the standard, widely-used workaround; Apple could rename or
        // remove it in a future OS release, so if it ever silently stops working,
        // this is the first place to check.
        config.preferences.setValue(false, forKey: "safeBrowsingEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground") // matches app theme
        webView.navigationDelegate = context.coordinator
        webViewBox?.webView = webView
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.onNavigationFailure = onNavigationFailure
        guard context.coordinator.lastLoadedSource != source else { return }
        context.coordinator.lastLoadedSource = source
        context.coordinator.isLocalWebArchive = false

        switch source {
            case .htmlString(let html):
                context.coordinator.allowJavaScript = true
                
                // Inject theme classes just in case JS fails
                let safeHtml = html.replacingOccurrences(of: "<html", with: "<html data-theme=\"dark\" class=\"theme-dark\"", options: .caseInsensitive)
                nsView.loadHTMLString(Self.prepare(safeHtml), baseURL: nil)
                
            case .remoteURL(let url):
                context.coordinator.allowJavaScript = true
                nsView.load(URLRequest(url: url))
                
            case .localFolder(let indexFile, let folder):
                context.coordinator.allowJavaScript = true
                
                // Using loadFileURL directly triggers WebKit sandbox restrictions that block relative CSS.
                // Reading it into a string and using loadHTMLString with the folder as the baseURL bypasses this perfectly.
                if let html = try? String(contentsOf: indexFile, encoding: .utf8) {
                    // Force theme classes in case Namuwiki's offline JS crashes
                    let safeHtml = html.replacingOccurrences(of: "<html", with: "<html data-theme=\"dark\" class=\"theme-dark\"", options: .caseInsensitive)
                    
                    nsView.loadHTMLString(Self.prepare(safeHtml), baseURL: folder)
                } else {
                    nsView.loadFileURL(indexFile, allowingReadAccessTo: folder)
                }
            case .localWebArchive(let fileURL, let originalURL):
                context.coordinator.allowJavaScript = true
                // Kept as a safety net: cancel any navigation beyond the first one
                // we issue ourselves (script- or link-triggered), so we never try
                // to actually chase a live URL while showing this offline fallback.
                context.coordinator.isLocalWebArchive = true
                context.coordinator.hasAllowedInitialArchiveLoad = false

                if let archiveData = try? Data(contentsOf: fileURL) {
                    // baseURL is the page's original live URL (not fileURL) so that
                    // any relative resource paths in the archived HTML resolve to
                    // the same absolute URLs the archive's bundled WebSubresources
                    // are keyed by. This is safe now that Safe Browsing is disabled
                    // above -- that was the actual source of the -1009, not this.
                    nsView.load(
                        archiveData,
                        mimeType: "application/x-webarchive",
                        characterEncodingName: "utf-8",
                        baseURL: originalURL ?? fileURL
                    )
                } else {
                    onNavigationFailure?()
                }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onNavigationFailure: (() -> Void)?
        var lastLoadedSource: Source?
        var allowJavaScript = false

        // Set while a `.localWebArchive` is loading. We still cancel any navigation
        // beyond the first as a safety net (in case a script tries to navigate the
        // main frame for any reason) — see decidePolicyFor below.
        var isLocalWebArchive = false
        var hasAllowedInitialArchiveLoad = false

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            preferences: WKWebpagePreferences,
            decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
        ) {
            preferences.allowsContentJavaScript = allowJavaScript

            if isLocalWebArchive {
                if hasAllowedInitialArchiveLoad {
                    // Anything after the one load we issued ourselves would be a
                    // script- or link-triggered navigation. Cancel it rather than
                    // letting WebKit try to actually fetch it while we're in this
                    // offline-fallback path — we stay on the already-rendered archive.
                    decisionHandler(.cancel, preferences)
                    return
                }
                hasAllowedInitialArchiveLoad = true
            }

            decisionHandler(.allow, preferences)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("[HTMLWebView] failed to load: \(error.localizedDescription)")
            onNavigationFailure?()
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("[HTMLWebView] failed to load: \(error.localizedDescription)")
            onNavigationFailure?()
        }
    }

    // MARK: - Raw-HTML-string preparation (unchanged from before)

    private static func prepare(_ html: String) -> String {
        if isFullDocument(html) {
            return injectColorScheme(into: html)
        }
        return """
        <html>
        <head>
        <style>
            :root { color-scheme: light dark; }
            body { font-family: -apple-system, sans-serif; padding: 10px; }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
    }

    private static func isFullDocument(_ s: String) -> Bool {
        let head = s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300).lowercased()
        return head.contains("<!doctype") || head.contains("<html")
    }

    private static func injectColorScheme(into html: String) -> String {
        guard let headRange = html.range(of: "<head", options: [.caseInsensitive]) else { return html }
        guard let tagEnd = html.range(of: ">", range: headRange.upperBound..<html.endIndex) else { return html }
        var result = html
        result.insert(contentsOf: "\n<meta name=\"color-scheme\" content=\"light dark\">\n", at: tagEnd.upperBound)
        return result
    }
}
