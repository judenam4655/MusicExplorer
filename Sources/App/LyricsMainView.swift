//
//  LyricsMainView.swift
//  MusicExplorer
//
//  Created by Juhyeon Nam on 9/8/26.
//

import SwiftUI
import CoreImage

struct LyricsMainView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var playback: PlaybackState
    
    @AppStorage("titleSize") var titleSize: Double = 40
    @AppStorage("artistSize") var artistSize: Double = 24
    @AppStorage("lyricAlign") var align: TextAlignmentChoice = .center
    @AppStorage("lyricsEdgeGap") var edgeGap: Double = 40

    // UI States
    @State private var artworkImage: NSImage? = nil
    @State private var backgroundTint: Color? = nil
    @State private var isImporterPresented = false
    @State private var imageImportError: String? = nil
    @State private var isFetchingArtwork = false
    
    private let artworkSize: CGFloat = 300

    /// Safe file name derived from artist + title
    private var artworkTrackKey: String {
//        let raw = "\(appState.artist)-\(appState.album)"
        let raw = "\(appState.artist)-\(appState.trackTitle)"
        let allowed = CharacterSet.alphanumerics
        let cleaned = String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        return cleaned.isEmpty ? "untitled" : cleaned
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            Divider()

            ZStack(alignment: .topTrailing) {
                Group {
                    if let plain = appState.plainLyricsText {
                        ScrollView {
                            Text(plain)
                                .font(.system(size: 22))
                                .multilineTextAlignment(align.alignment)
                                .padding()
                        }
                    } else if let lines = appState.syncedLines {
                        syncedLyricsList(lines: lines)
                    } else {
                        VStack {
                            Spacer()
                            Text(appState.currentLineText)
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                artworkView
                    .padding(.top, 16)
                    .padding(.trailing, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundWash)
        // Triggers automatically whenever the artist/title changes
        .task(id: artworkTrackKey) {
            await loadArtworkForCurrentTrack()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var backgroundWash: some View {
        if let tint = backgroundTint {
            LinearGradient(
                colors: [tint, tint.opacity(0.4)],
                startPoint: .top,
                endPoint: .bottom
            )
            .animation(.easeInOut(duration: 0.6), value: tint)
            .ignoresSafeArea()
            .allowsHitTesting(false)
        } else {
            Color.clear
        }
    }

    private var headerView: some View {
        VStack(spacing: 4) {
            Text(appState.trackTitle)
                .font(.system(size: titleSize, weight: .bold))
                .multilineTextAlignment(align.alignment)
            Text(appState.artist)
                .font(.system(size: artistSize))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: align == .center ? .center : (align == .left ? .leading : .trailing))
        .padding(.horizontal, edgeGap)
    }

    private var artworkView: some View {
        Button {
            isImporterPresented = true
        } label: {
            ZStack {
                if let displayedImage = artworkImage {
                    Image(nsImage: displayedImage)
                        .resizable()
                        .scaledToFill()
                } else if isFetchingArtwork {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: artworkSize, height: artworkSize)
            .background(Color.secondary.opacity(artworkImage == nil ? 0.08 : 0.0))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(artworkImage == nil ? "Add a custom image (overrides automatic artwork)" : "Change image")
        .contextMenu {
            Button("Choose Image...") { isImporterPresented = true }
            if artworkImage != nil {
                Button("Remove Custom Image", role: .destructive) { clearCustomImage() }
            }
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url): loadImage(from: url)
            case .failure(let error): imageImportError = error.localizedDescription
            }
        }
        .alert("Couldn't load image", isPresented: Binding(
            get: { imageImportError != nil },
            set: { if !$0 { imageImportError = nil } }
        )) {
            Button("OK", role: .cancel) { imageImportError = nil }
        } message: {
            Text(imageImportError ?? "")
        }
    }

    private func syncedLyricsList(lines: [LyricLine]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: align == .left ? .leading : (align == .right ? .trailing : .center), spacing: 8) {
                    Color.clear.frame(height: 40)
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        lyricRow(index: index, line: line, totalLines: lines.count)
                    }
                    Color.clear.frame(height: 100)
                }
                .padding(.horizontal, edgeGap)
                .frame(maxWidth: .infinity, alignment: align == .center ? .center : (align == .left ? .leading : .trailing))
            }
            .id(appState.trackTitle)
            .onChange(of: playback.currentLineIndex) { newIndex in
                guard let idx = newIndex else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    proxy.scrollTo(idx, anchor: .center)
                }
            }
        }
    }
    
    @ViewBuilder
    private func lyricRow(index: Int, line: LyricLine, totalLines: Int) -> some View {
        let cleanText = line.text.trimmingCharacters(in: .whitespaces)
        let isLastBlock = index == totalLines - 1
        let isEndMarker = (cleanText.lowercased() == "(end)") || (isLastBlock && cleanText.isEmpty)
        let isCurrent = (index == playback.currentLineIndex) && !isEndMarker

        if isEndMarker {
            Color.clear.frame(height: 1).id(index)
        } else {
            let translated = appState.translatedLines
            let rawTransText = (translated != nil && index < translated!.count) ? translated![index].text : nil
            let transText = ["(intl)", "(end)", "(끝)", "♪"].contains(rawTransText?.trimmingCharacters(in: .whitespaces).lowercased() ?? "") ? nil : rawTransText
            
            let lineAnnotations = appState.annotationsByLine[index] ?? []
            let lineNote = appState.lineNotes[index]

            LyricLineView(
                originalText: line.text,
                translationText: transText,
                lineIndex: index,
                annotations: lineAnnotations,
                lineNote: lineNote,
                isCurrent: isCurrent
            ) {
                guard let ms = line.timeMs else { return }
                playback.positionMs = ms
                appState.services.seek(to: ms)
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: isCurrent)
            .id(index)
        }
    }

    // MARK: - Artwork Loading & File System Operations

    private func loadArtworkForCurrentTrack() async {
        let key = artworkTrackKey
        guard key != "untitled" else { return }
        
        await MainActor.run {
            isFetchingArtwork = true
            artworkImage = nil
            backgroundTint = nil
        }
        
        // 1. Check File System First (for manual overrides)
        if let localImage = Self.loadImage(forKey: key, isCustom: true) {
            await MainActor.run {
                self.artworkImage = localImage
                self.isFetchingArtwork = false
            }
            await updateBackgroundTint(from: localImage)
            return
        }
        
        // 2. Check File System for Previously Fetched iTunes Artwork
        if let cachedImage = Self.loadImage(forKey: key, isCustom: false) {
            await MainActor.run {
                self.artworkImage = cachedImage
                self.isFetchingArtwork = false
            }
            await updateBackgroundTint(from: cachedImage)
            return
        }
        
        // 3. Network Fetch (iTunes API)
        do {
            let term = "\(appState.artist) \(appState.trackTitle)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let urlString = "https://itunes.apple.com/search?term=\(term)&entity=song&limit=1"
            guard let url = URL(string: urlString) else { return }
            
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                await MainActor.run { isFetchingArtwork = false }
                return
            }
            
            let decoded = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
            guard let artworkUrlString = decoded.results.first?.artworkUrl100?.replacingOccurrences(of: "100x100bb", with: "600x600bb"),
                  let artworkUrl = URL(string: artworkUrlString) else {
                await MainActor.run { isFetchingArtwork = false }
                return
            }
            
            let (imageData, _) = try await URLSession.shared.data(from: artworkUrl)
            
            if let downloadedImage = NSImage(data: imageData) {
                // SAVE iTunes fetch to the Artwork folder so we never download it again
                Self.saveImage(downloadedImage, forKey: key, isCustom: false)
                
                await MainActor.run {
                    self.artworkImage = downloadedImage
                    self.isFetchingArtwork = false
                }
                await updateBackgroundTint(from: downloadedImage)
            }
        } catch {
            print("Artwork network/decoding error: \(error.localizedDescription)")
            await MainActor.run { isFetchingArtwork = false }
        }
    }

    private func loadImage(from url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            imageImportError = "That file couldn't be read as an image."
            return
        }
        
        let stableImage = NSImage(cgImage: cgImage, size: image.size)

        // Save manual override to File System
        Self.saveImage(stableImage, forKey: artworkTrackKey, isCustom: true)

        withAnimation(.easeInOut(duration: 0.3)) {
            artworkImage = stableImage
        }
        Task { await updateBackgroundTint(from: stableImage) }
    }

    private func clearCustomImage() {
        Self.deleteCustomImage(forKey: artworkTrackKey)
        
        withAnimation(.easeInOut(duration: 0.4)) {
            artworkImage = nil
            backgroundTint = nil
        }
        
        // Re-trigger the load to fallback to the cached iTunes version instantly
        Task { await loadArtworkForCurrentTrack() }
    }

    // MARK: - File System Storage
    
    private static var artworkDirectory: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("LyricsShower/Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func imageURL(forKey key: String, isCustom: Bool) -> URL? {
        let prefix = isCustom ? "custom_" : "auto_"
        return artworkDirectory?.appendingPathComponent("\(prefix)\(key).png")
    }

    private static func saveImage(_ image: NSImage, forKey key: String, isCustom: Bool) {
        guard let url = imageURL(forKey: key, isCustom: isCustom),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else { return }
        try? pngData.write(to: url, options: .atomic)
    }

    private static func loadImage(forKey key: String, isCustom: Bool) -> NSImage? {
        guard let url = imageURL(forKey: key, isCustom: isCustom), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    private static func deleteCustomImage(forKey key: String) {
        guard let url = imageURL(forKey: key, isCustom: true) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Color Math

    private func updateBackgroundTint(from image: NSImage) async {
        let color = await Task.detached(priority: .userInitiated) {
            Self.representativeColor(from: image)
        }.value
        
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.6)) {
                backgroundTint = color
            }
        }
    }

    private static func representativeColor(from image: NSImage) -> Color? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent
        let extentVector = CIVector(x: extent.origin.x, y: extent.origin.y, z: extent.size.width, w: extent.size.height)

        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: extentVector
        ]), let outputImage = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let rawColor = NSColor(
            red: Double(bitmap[0]) / 255.0,
            green: Double(bitmap[1]) / 255.0,
            blue: Double(bitmap[2]) / 255.0,
            alpha: 1.0
        )
        
        return Color(nsColor: rawColor.adaptiveBackgroundColor())
    }

    private struct ITunesSearchResponse: Decodable {
        struct Result: Decodable {
            let artworkUrl100: String?
        }
        let results: [Result]
    }
}

// MARK: - Adaptive Background Extension

//extension NSColor {
//    /// Mathematically adjusts a color to guarantee it looks good as a background
//    func adaptiveBackground() -> Color {
//        guard let rgb = self.usingColorSpace(.deviceRGB) else { return Color(self) }
//
//        var h: CGFloat = 0
//        var s: CGFloat = 0
//        var b: CGFloat = 0
//        var a: CGFloat = 0
//
//        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
//
//        // 1. Lift dark/muddy colors
//        if b < 0.3 {
//            b = 0.45
//            if s < 0.2 {
//                s = 0.3 // Inject saturation so it isn't just gray
//            }
//        }
//        // 2. Dim overly bright colors and prevent white
//        else if b > 0.85 {
//            b = 0.75
//            if s < 0.2 {
//                s = 0.3 // Inject saturation to prevent pure white/light gray
//            }
//        }
//
//        // 3. Boost vibrancy slightly
//        s = min(s + 0.15, 1.0)
//
//        let adaptedNSColor = NSColor(deviceHue: h, saturation: s, brightness: b, alpha: 1.0)
//        return Color(nsColor: adaptedNSColor)
//    }
//}
