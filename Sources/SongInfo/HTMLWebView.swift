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
    var webViewBox: WebViewBox? = nil   // NEW

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        
        // KVC keys removed: Apple strictly enforces loadFileURL(_:allowingReadAccessTo:)
        // to handle local directory permissions now.
        
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
                            
                if let archiveData = try? Data(contentsOf: fileURL) {
                    // 2. Load the raw binary data to bypass the -1009 network validation check
                    // 3. Pass the originalURL to trick the JS router into rendering the page
                    nsView.load(
                        archiveData,
                        mimeType: "application/x-webarchive",
                        characterEncodingName: "utf-8",
                        baseURL: originalURL ?? fileURL
                    )
                }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onNavigationFailure: (() -> Void)?
        var lastLoadedSource: Source?
        var allowJavaScript = false

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            preferences: WKWebpagePreferences,
            decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
        ) {
            preferences.allowsContentJavaScript = allowJavaScript
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

