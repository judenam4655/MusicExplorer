import Foundation

struct SavedSongInfo {
    let documentID: String
    let htmlContent: String   // rewritten HTML, asset refs now point at local files
    let folderURL: URL
}

enum SongInfoAssetSaverError: Error, LocalizedError {
    case invalidURL
    case fetchFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "That doesn't look like a valid URL."
        case .fetchFailed(let msg): return msg
        }
    }
}

/// Downloads a web page plus the CSS/image assets it references, rewrites
/// the HTML to point at local copies, and saves everything under
/// Application Support/MusicExplorer/<documentID>/.
///
/// Scope note: this covers the common case -- <link rel=stylesheet href>,
/// <img src>, and background-image: url(...) references one level deep
/// inside those stylesheets. It does not recursively follow @import chains,
/// <script src>, srcset, or JS-driven image loading. A page that leans on
/// any of those will still work fine *online* (untouched refs just point at
/// their original URL), but the *offline* copy may be missing those assets.
final class SongInfoAssetSaver {
    private let session = URLSession.shared
    private let maxAssets = 300 // safety cap against pathological pages
    
    func saveSnapshot(
            renderedHTML: String,
        baseURL: URL,
        trackId: String,
        existingDocumentID: String? = nil
    ) async throws -> SavedSongInfo {
        let documentID = existingDocumentID ?? UUID().uuidString
        let folder = try Self.resetDocumentFolder(documentID: documentID)
        
        // Apply HTML stripping and defeat lazy-loading placeholders
        var html = Self.cleanNamuwikiHTML(renderedHTML)
        html = html
            .replacingOccurrences(of: "src=\"data:image", with: "dummy=\"data:image")
            .replacingOccurrences(of: "src='data:image", with: "dummy='data:image")
            
        var downloadCount = 0

        // 1. Stylesheets
        for href in Self.extractStylesheetHrefs(in: html) {
            guard downloadCount < maxAssets, let assetURL = Self.resolve(href, relativeTo: baseURL) else { continue }
            guard let localName = await downloadAsset(assetURL, into: folder, preferredExtension: "css") else { continue }
            downloadCount += 1
            html = html.replacingOccurrences(of: href, with: localName)

            let cssFile = folder.appendingPathComponent(localName)
            guard var css = try? String(contentsOf: cssFile, encoding: .utf8) else { continue }
            for cssRef in Self.cssUrls(in: css) {
                guard downloadCount < maxAssets, let cssAssetURL = Self.resolve(cssRef, relativeTo: assetURL) else { continue }
                guard let cssLocalName = await downloadAsset(cssAssetURL, into: folder, preferredExtension: nil) else { continue }
                downloadCount += 1
                css = css.replacingOccurrences(of: cssRef, with: cssLocalName)
            }
            try? css.write(to: cssFile, atomically: true, encoding: .utf8)
        }

        // 2. Images
        for src in Self.extractImageSources(in: html) {
            guard downloadCount < maxAssets, let assetURL = Self.resolve(src, relativeTo: baseURL) else { continue }
            guard let localName = await downloadAsset(assetURL, into: folder, preferredExtension: nil) else { continue }
            downloadCount += 1
            
            html = html.replacingOccurrences(of: src, with: localName)
            
            // Upgrade lazy-load tags to active src tags so they render without JS
            html = html.replacingOccurrences(of: "data-src=\"\(localName)\"", with: "src=\"\(localName)\"")
            html = html.replacingOccurrences(of: "data-original=\"\(localName)\"", with: "src=\"\(localName)\"")
        }

        let indexURL = folder.appendingPathComponent("index.html")
        try html.write(to: indexURL, atomically: true, encoding: .utf8)

        return SavedSongInfo(documentID: documentID, htmlContent: html, folderURL: folder)
    }


    // MARK: - Downloading
    
    private static func resetDocumentFolder(documentID: String) throws -> URL {
        let folder = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MusicExplorer", isDirectory: true)
            .appendingPathComponent(documentID, isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func downloadAsset(_ url: URL, into folder: URL, preferredExtension: String?) async -> String? {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            
            // Spoof standard browser headers to bypass CDN bot-protection (Cloudflare)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            request.setValue("text/css,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("https://namu.wiki/", forHTTPHeaderField: "Referer")

            let (data, response) = try await session.data(for: request)

            // Ensure we didn't get a 403 Forbidden or 404 Not Found error page
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                print("[SongInfoAssetSaver] Server rejected download \(url) with status: \(httpResponse.statusCode)")
                return nil
            }

            let ext: String
            if let preferredExtension {
                ext = preferredExtension
            } else if !url.pathExtension.isEmpty {
                // Strip out query parameters from the extension (e.g. .css?v=123 -> .css)
                ext = url.pathExtension.components(separatedBy: CharacterSet(charactersIn: "?#")).first ?? "bin"
            } else {
                ext = response.mimeTypeFileExtension ?? "bin"
            }

            let base = url.lastPathComponent.isEmpty ? "asset" : (url.lastPathComponent as NSString).deletingPathExtension
            let safeName = "\(UUID().uuidString.prefix(8))_\(base).\(ext)"
            try data.write(to: folder.appendingPathComponent(safeName))
            return safeName
        } catch {
            print("[SongInfoAssetSaver] failed to download \(url): \(error)")
            return nil
        }
    }

    // MARK: - Parsing helpers

    /// Finds all tags matching `tagPattern`, optionally filters to ones
    /// containing `requiredSubstring` (e.g. "stylesheet"), then pulls the
    /// named attribute's value out of each -- order-independent, so
    /// `rel="stylesheet" href="..."` and `href="..." rel="stylesheet"` both
    /// match, unlike a single combined regex would.
    private static func extractAttribute(
        _ attr: String, fromTags tagPattern: String, in html: String, requiredSubstring: String? = nil
    ) -> [String] {
        guard let tagRegex = try? NSRegularExpression(pattern: tagPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let ns = html as NSString
        var results: [String] = []
        tagRegex.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match, let tagRange = Range(match.range, in: html) else { return }
            let tag = String(html[tagRange])
            if let requiredSubstring, !tag.lowercased().contains(requiredSubstring) { return }
            guard let attrRegex = try? NSRegularExpression(pattern: "\(attr)=[\"']([^\"']+)[\"']", options: [.caseInsensitive]) else { return }
            let tagNS = tag as NSString
            if let attrMatch = attrRegex.firstMatch(in: tag, range: NSRange(location: 0, length: tagNS.length)),
               let valueRange = Range(attrMatch.range(at: 1), in: tag) {
                results.append(String(tag[valueRange]))
            }
        }
        return results
    }
    
    private static func extractStylesheetHrefs(in html: String) -> [String] {
        guard let tagRegex = try? NSRegularExpression(pattern: "<(?:link|style)[^>]*>", options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let ns = html as NSString
        var results: [String] = []
        tagRegex.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match, let tagRange = Range(match.range, in: html) else { return }
            let tag = String(html[tagRange])
            let lower = tag.lowercased()
            
            for attr in ["href", "data-href"] {
                if let val = attributeValue(attr, in: tag) {
                    let cleanVal = val.components(separatedBy: "?").first ?? val
                    if lower.contains("stylesheet") || cleanVal.lowercased().hasSuffix(".css") {
                        results.append(val)
                    }
                }
            }
        }
        return Array(Set(results))
    }

    private static func extractImageSources(in html: String) -> [String] {
        guard let tagRegex = try? NSRegularExpression(pattern: "<(?:img|source)[^>]*>", options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let ns = html as NSString
        var results: [String] = []
        tagRegex.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match, let tagRange = Range(match.range, in: html) else { return }
            let tag = String(html[tagRange])
            
            // Prioritize lazy-load attributes over the standard src
            for attr in ["data-src", "data-original", "src", "srcset"] {
                if let value = attributeValue(attr, in: tag), !value.isEmpty, !value.hasPrefix("data:") {
                    if attr == "srcset" {
                        let firstUrl = value.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .whitespaces).first
                        if let firstUrl = firstUrl, !firstUrl.hasPrefix("data:") {
                            results.append(firstUrl)
                        }
                    } else {
                        results.append(value)
                    }
                    break
                }
            }
        }
        return Array(Set(results))
    }

    private static func attributeValue(_ attr: String, in tag: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\(attr)=[\"']([^\"']+)[\"']", options: [.caseInsensitive]) else { return nil }
        let ns = tag as NSString
        guard let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: ns.length)),
              let r = Range(match.range(at: 1), in: tag) else { return nil }
        return String(tag[r])
    }

    private static func cssUrls(in css: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"url\(\s*["']?([^"')]+)["']?\s*\)"#, options: [.caseInsensitive]) else { return [] }
        let ns = css as NSString
        var results: [String] = []
        regex.enumerateMatches(in: css, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match, let r = Range(match.range(at: 1), in: css) else { return }
            let url = String(css[r])
            
            // Strip query parameters to properly identify file extensions
            let cleanUrl = url.components(separatedBy: "?").first?.components(separatedBy: "#").first?.lowercased() ?? url.lowercased()
            
            // Skip fonts properly to prevent hitting the download cap
            if cleanUrl.hasSuffix(".woff") || cleanUrl.hasSuffix(".woff2") || cleanUrl.hasSuffix(".ttf") || cleanUrl.hasSuffix(".eot") { return }
            if cleanUrl.hasPrefix("data:") { return }
            
            results.append(url)
        }
        return Array(Set(results))
    }

    private static func resolve(_ refPath: String, relativeTo base: URL) -> URL? {
        if refPath.hasPrefix("data:") { return nil } // already inline, nothing to fetch
        
        var path = refPath
        // Fix for protocol-relative URLs (e.g., //i.namu.wiki/...)
        if path.hasPrefix("//") {
            path = (base.scheme ?? "https") + ":" + path
        }
        
        if let absolute = URL(string: path), absolute.scheme != nil {
            return absolute
        }
        return URL(string: path, relativeTo: base)?.absoluteURL
    }
    
    private static func cleanNamuwikiHTML(_ html: String) -> String {
        var clean = html
        
        if let footerRegex = try? NSRegularExpression(pattern: "<footer[^>]*>.*?</footer>", options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            clean = footerRegex.stringByReplacingMatches(in: clean, range: NSRange(clean.startIndex..., in: clean), withTemplate: "")
        }
        
        if let baseRegex = try? NSRegularExpression(pattern: "<base[^>]*>", options: [.caseInsensitive]) {
            clean = baseRegex.stringByReplacingMatches(in: clean, range: NSRange(clean.startIndex..., in: clean), withTemplate: "")
        }
                let injection = """
        <style>
            #app > div > div:first-child { display: none !important; }
            .-pyz\\+wP5 { display: none !important; }
            .bvxZjb22.TrW39z5w { display: none !important; }
        </style>
        </head>
        """
        clean = clean.replacingOccurrences(of: "</head>", with: injection, options: .caseInsensitive)
        
        return clean
    }

    private static func documentFolder(documentID: String) throws -> URL {
        let folder = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MusicExplorer", isDirectory: true)
            .appendingPathComponent(documentID, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

private extension URLResponse {
    var mimeTypeFileExtension: String? {
        guard let mime = (self as? HTTPURLResponse)?.mimeType ?? mimeType else { return nil }
        switch mime {
        case "image/png": return "png"
        case "image/jpeg": return "jpg"
        case "image/webp": return "webp"
        case "image/gif": return "gif"
        case "image/svg+xml": return "svg"
        case "text/css": return "css"
        default: return nil
        }
    }
}
