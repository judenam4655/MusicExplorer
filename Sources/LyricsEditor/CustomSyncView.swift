//
//  CustomSyncView.swift
//  MusicExplorer
//
//  Created by Juhyeon Nam on 8/22/26.
//

import SwiftUI

enum SyncEditMode: String, CaseIterable {
    case both = "Both"
    case translation = "Translation Only"
    case single = "Single Line"
}

struct CustomModeButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.1) : Color.clear))
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// A custom NSViewRepresentable text editor that properly handles cursor-level
/// text insertion and command interception (such as Tab handling in translation mode).
struct CustomTextEditor: NSViewRepresentable {
    @Binding var text: String
    var editMode: SyncEditMode

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.string = text
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            let maxLen = (text as NSString).length
            let safeLocation = min(selectedRange.location, maxLen)
            let safeLength = min(selectedRange.length, maxLen - safeLocation)
            textView.setSelectedRange(NSRange(location: safeLocation, length: safeLength))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CustomTextEditor

        init(_ parent: CustomTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                if parent.editMode == .translation {
                    textView.insertText("\n", replacementRange: textView.selectedRange())
                    return true
                }
            }
            return false
        }
    }
}

/// Lyric sync editor, rebuilt around a single plain-text buffer instead of a
/// `ForEach` of one live `TextField` pair per lyric line.
///
/// The old design kept every line's timestamp + text as a `SyncBlock` in a
/// `@State` array, with a whole SwiftUI row (two focus-tracked TextFields,
/// buttons, bindings) alive for each one -- for a full song that's 100-300
/// persistent views, all being diffed/laid out/kept warm the entire time
/// the page is open, which is exactly what was costing performance and
/// battery. Here there's exactly one `TextEditor` on screen, bound to one
/// `String`. Timestamps live *inside* that string as `[mm:ss.xx]` tags;
/// `RawLyricsParser` is a pure function that reads them out only when
/// something actually needs them (saving, or the spacebar-sync status
/// line) rather than mirroring them into persistent view state.
struct CustomSyncView: View {
    @EnvironmentObject var appState: AppState

    @State private var rawText: String = ""
    @State private var editMode: SyncEditMode = .both
    @State private var syncModeActive = false
    // Index into RawLyricsParser.parseBlocks(rawText) -- which block the
    // next spacebar press will stamp.
    @State private var syncBlockIndex: Int = 0
    @State private var spacebarMonitor: Any?

    // Recomputed on demand, not cached in @State: parsing a few hundred
    // short lines is cheap, and keeping it derived (rather than a second
    // source of truth that could drift from rawText) is what makes the
    // "one String, no per-block state" approach actually simpler.
    private var blocks: [RawLyricsBlock] {
        RawLyricsParser.parseBlocks(rawText, ignoreBlankLines: editMode == .single) 
    }

    var body: some View {
        VStack(spacing: 0) {
            // TOOLBAR
            HStack(spacing: 24) {
                HStack(spacing: 4) {
                    CustomModeButton(icon: "music.mic", isSelected: editMode == .both) {
                        saveCustomLRC()
                        setMode(.both)
                    }
                    CustomModeButton(icon: "translate", isSelected: editMode == .translation) {
                        saveCustomLRC()
                        setMode(.translation)
                    }
                    CustomModeButton(icon: "text.alignleft", isSelected: editMode == .single) {
                        saveCustomLRC()
                        setMode(.single)
                    }
                }
                .padding(4)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 1))

                Spacer()

                if editMode == .both {
                    HStack(spacing: 8) {
                        Button(action: goToPreviousSyncLine) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(syncBlockIndex > 0 ? .primary : .primary.opacity(0.3))
                                .frame(width: 36, height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.gray.opacity(0.1))
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(syncBlockIndex == 0)
                        .help("Previous Line (Back Arrow)")

                        Button(action: { syncModeActive.toggle() }) {
                            Image(systemName: "space")
                                .font(.system(size: 18, weight: syncModeActive ? .bold : .medium))
                                .foregroundColor(syncModeActive ? .white : .primary)
                                .frame(width: 40, height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(syncModeActive ? Color.accentColor : Color.gray.opacity(0.1))
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Toggle Sync Mode (Spacebar)")
                    }
                }

                Button(action: loadCurrentLyrics) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 24))
                        .foregroundColor(.primary)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .help("Load Current Lyrics")

                Button(action: saveCustomLRC) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 24))
                        .foregroundColor(.accentColor)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .help("Save to LRC")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if syncModeActive {
                syncStatusBar
                Divider()
            }

            // THE EDITOR. Wrapped to support cursor-aware text insertion for tabs.
            CustomTextEditor(text: $rawText, editMode: editMode)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: rawText) { _ in
                    // The buffer shifted, so any in-flight sync target-by-
                    // index may no longer point at the same block. Clamping
                    // (rather than resetting to 0) keeps sync position
                    // roughly stable through small edits.
                    if syncBlockIndex > blocks.count {
                        syncBlockIndex = blocks.count
                    }
                }
        }
        .onAppear { setupKeyboardMonitor() }
        .onDisappear { teardownKeyboardMonitor() }
    }

    /// Lightweight replacement for the old per-block highlight: a single
    /// status line naming which block is next, instead of a persistent view
    /// per block just to show which one is "current."
    private var syncStatusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "space")
                .foregroundStyle(Color.accentColor)
            if syncBlockIndex < blocks.count {
                Text("Syncing \(syncBlockIndex + 1) / \(blocks.count):")
                    .font(.callout.bold())
                Text(blocks[syncBlockIndex].text.replacingOccurrences(of: "\n", with: "  /  "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("All lines synced.").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08))
    }

    // MARK: - Logic

    private func setMode(_ mode: SyncEditMode) {
        editMode = mode
        if mode == .translation || mode == .single {
            syncModeActive = false
        }
        loadCurrentLyrics()
    }

    private func setupKeyboardMonitor() {
        spacebarMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if syncModeActive {
                if event.keyCode == 49 { // Spacebar
                    handleSyncTrigger()
                    return nil
                } else if event.keyCode == 123 { // Left Arrow (Back Arrow)
                    goToPreviousSyncLine()
                    return nil
                }
            }
            return event
        }
    }

    private func teardownKeyboardMonitor() {
        if let monitor = spacebarMonitor {
            NSEvent.removeMonitor(monitor)
            spacebarMonitor = nil
        }
    }

    private func handleSyncTrigger() {
        if !appState.services.isPlaying {
            appState.services.togglePlayPause()
        } else {
            let currentBlocks = blocks
            guard syncBlockIndex < currentBlocks.count else { return }
            let ms = appState.positionMs
            rawText = RawLyricsParser.applyingTimestamp(ms, atLineIndex: currentBlocks[syncBlockIndex].firstLineIndex, to: rawText)
            syncBlockIndex += 1
        }
    }

    private func goToPreviousSyncLine() {
        if syncBlockIndex > 0 {
            syncBlockIndex -= 1
        }
    }

    private func loadCurrentLyrics() {
        let originalLines = appState.syncedLines ?? []
        let translatedLines = appState.translatedLines ?? []

        if editMode == .single {
            let blockStrings = originalLines.map { line in
                let tag = line.timeMs.map { "[\(LRCTimeFormatter.msToString($0))] " } ?? ""
                return "\(tag)\(line.text)"
            }
            rawText = !blockStrings.isEmpty ? blockStrings.joined(separator: "\n") : (appState.plainLyricsText ?? "")
            syncBlockIndex = 0
            return
        }

        // Build a lookup dictionary of translations by timestamp (timeMs)
        // to ensure original and translation lines pair up accurately regardless
        // of array length discrepancies or ordering differences.
        var translationDict: [Int: String] = [:]
        for trans in translatedLines {
            if let tMs = trans.timeMs {
                translationDict[tMs] = trans.text
            }
        }

        var pairs: [(timeMs: Int?, original: String, trans: String)] = []
        for (i, o) in originalLines.enumerated() {
            let transText: String
            if let oMs = o.timeMs, let matchedTrans = translationDict[oMs] {
                transText = matchedTrans
            } else if i < translatedLines.count {
                transText = translatedLines[i].text
            } else {
                transText = ""
            }
            pairs.append((o.timeMs, o.text, transText))
        }

        if !pairs.isEmpty {
            let blockStrings: [String] = pairs.map { pair in
                let tag = pair.timeMs.map { "[\(LRCTimeFormatter.msToString($0))] " } ?? ""
                switch editMode {
                case .translation:
                    let transText = (pair.trans == "(end)" || pair.trans == "(끝)") ? "(end)" : pair.trans
                    return "\(tag)\(pair.original)\n\(transText)"
                case .both:
                    var text = pair.original
                    if pair.original == "(end)" || pair.original == "(끝)" {
                        text = "(end)"
                    } else if !pair.trans.isEmpty {
                        text += "\n\(pair.trans)"
                    }
                    return "\(tag)\(text)"
                case .single:
                    return "\(tag)\(pair.original)"
                }
            }
            rawText = blockStrings.joined(separator: "\n\n")
        } else if let plainText = appState.plainLyricsText, !plainText.isEmpty {
            rawText = plainText
        } else {
            rawText = ""
        }

        syncBlockIndex = 0
    }

    private func saveCustomLRC() {
        var originalLRC = ""
        var translationLRC = ""

        if editMode == .single {
            for block in blocks {
                let timeStr = block.timeMs.map(LRCTimeFormatter.msToString) ?? ""
                let prefix = timeStr.isEmpty ? "" : "[\(timeStr)] "
                let lineText = block.text
                    .components(separatedBy: "\n")
                    .first?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                guard !lineText.isEmpty else { continue }
                originalLRC += "\(prefix)\(lineText)\n"
            }
            appState.services.saveCustomOriginal(lrcText: originalLRC)
            syncModeActive = false
            return
        }

        for block in blocks {
            let timeStr = block.timeMs.map(LRCTimeFormatter.msToString) ?? ""
            let prefix = timeStr.isEmpty ? "" : "[\(timeStr)] "
            let bodyLines = block.text
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !bodyLines.isEmpty else { continue }

            if editMode == .translation {
                let originalLower = bodyLines[0].lowercased()
                if originalLower == "(intl)" || originalLower == "(간주중)" {
                    translationLRC += "\(prefix)♪\n"
                } else if originalLower == "(end)" || originalLower == "(끝)" {
                    translationLRC += "\(prefix)(end)\n"
                } else {
                    let transClean = bodyLines.count > 1 ? bodyLines[1] : ""
                    if !transClean.isEmpty {
                        translationLRC += "\(prefix)\(transClean)\n"
                    }
                }
            } else {
                let firstLineLower = bodyLines[0].lowercased()
                if firstLineLower == "(intl)" || firstLineLower == "(간주중)" {
                    originalLRC += "\(prefix)♪\n"
                    translationLRC += "\(prefix)♪\n"
                } else if firstLineLower == "(end)" || firstLineLower == "(끝)" {
                    originalLRC += "\(prefix)(end)\n"
                    translationLRC += "\(prefix)(end)\n"
                } else {
                    originalLRC += "\(prefix)\(bodyLines[0])\n"
                    if bodyLines.count == 2 {
                        translationLRC += "\(prefix)\(bodyLines[1])\n"
                    } else if bodyLines.count >= 3 {
                        translationLRC += "\(prefix)\(bodyLines[2])\n"
                    }
                }
            }
        }

        if editMode == .both {
            appState.services.saveCustomOriginal(lrcText: originalLRC)
        }
        appState.services.saveCustomTranslation(lrcText: translationLRC)
        syncModeActive = false
    }
}
