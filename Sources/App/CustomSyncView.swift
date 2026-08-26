//
//  CustomSyncView.swift
//  MusicExplorer
//
//  Created by Juhyeon Nam on 8/22/26.
//

import SwiftUI

struct SyncBlock: Identifiable, Equatable {
    let id = UUID()
    var timeText: String = ""
    var lyricsText: String = ""
    var originalText: String? = nil
}

enum SyncFocusField: Hashable {
    case time(UUID)
    case lyrics(UUID)
}

enum SyncEditMode: String, CaseIterable {
    case both = "Both"
    case translation = "Translation Only"
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

struct CustomSyncView: View {
    @EnvironmentObject var appState: AppState
    
    @State private var blocks: [SyncBlock] = [SyncBlock()]
    @State private var syncModeActive = false
    @State private var currentSyncIndex = 0
    @State private var editMode: SyncEditMode = .both
    @State private var spacebarMonitor: Any?

    @FocusState private var focusedField: SyncFocusField?

    var body: some View {
        VStack(spacing: 0) {
            // TOOLBAR
            HStack(spacing: 24) {
                
                // FIX: Replaced Apple Picker with Custom Mode Buttons
                HStack(spacing: 4) {
                    
                    CustomModeButton(icon: "music.mic", isSelected: editMode == .both) {
                        saveCustomLRC()
                        setMode(.both)
                    }
                    CustomModeButton(icon: "translate", isSelected: editMode == .translation) {
                        setMode(.translation)
                    }
                }
                .padding(4)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                
                Spacer()
                
                if editMode == .both {
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
            
            // EDITOR BLOCKS
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                            VStack(spacing: 0) {
                                
                                if editMode == .both {
                                    // MODE: BOTH (Full Sync Controls)
                                    HStack(alignment: .top, spacing: 16) {
                                        Button(action: {
                                            if let ms = LRCTimeFormatter.stringToMs(blocks[index].timeText) {
                                                appState.services.seek(to: ms)
                                            }
                                        }) {
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 12))
                                                .foregroundColor(blocks[index].timeText.isEmpty ? .gray.opacity(0.4) : .accentColor)
                                                .frame(width: 24, height: 24)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.top, 4)
                                        
                                        TextField("00:00.00", text: Binding(
                                            get: { blocks[index].timeText },
                                            set: { blocks[index].timeText = $0 }
                                        ))
                                        .font(.system(.body, design: .monospaced))
                                        .textFieldStyle(.plain)
                                        .focused($focusedField, equals: .time(block.id))
                                        .frame(width: 70)
                                        .foregroundColor(isValidTime(blocks[index].timeText) ? .primary : .red)
                                        .padding(.top, 6)
                                        
                                        TextField("Lyrics...", text: Binding(
                                            get: { blocks[index].lyricsText },
                                            set: { handleLyricsChange($0, at: index) }
                                        ), axis: .vertical)
                                        .textFieldStyle(.plain)
                                        .focused($focusedField, equals: .lyrics(block.id))
                                        .lineLimit(2...10)
                                        .padding(.top, 6)
                                        
                                        VStack(spacing: 16) {
                                            Button(action: { addBlock(after: index) }) { Image(systemName: "plus").foregroundColor(.secondary) }.buttonStyle(.plain)
                                            Button(action: { deleteBlock(at: index) }) { Image(systemName: "minus").foregroundColor(.secondary) }.buttonStyle(.plain).disabled(blocks.count <= 1)
                                        }
                                        .padding(.top, 6)
                                    }
                                    .padding(.vertical, 16)
                                    .padding(.horizontal, 24)
                                    .background(syncModeActive && index == currentSyncIndex ? Color.accentColor.opacity(0.1) : Color.clear)
                                    
                                } else {
                                    // FIX: MODE: TRANSLATION ONLY (Simplified UI)
                                    HStack(alignment: .top, spacing: 16) {
                                        // Read-Only Time
                                        Text(blocks[index].timeText.isEmpty ? "--:--.--" : blocks[index].timeText)
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .frame(width: 70, alignment: .leading)
                                            .padding(.top, 8)
                                        
                                        VStack(alignment: .leading, spacing: 10) {
                                            // Read-Only Original Lyrics
                                            Text(blocks[index].originalText ?? "♪")
                                                .font(.system(.body, weight: .semibold))
                                                .foregroundColor(.primary)
                                            
                                            // Translation Editor Box
                                            TextField("Translation...", text: Binding(
                                                get: { blocks[index].lyricsText },
                                                set: { blocks[index].lyricsText = $0 }
                                            ), axis: .vertical)
                                            .textFieldStyle(.plain)
                                            .lineLimit(1...5)
                                            .padding(10)
                                            .background(Color.primary.opacity(0.05))
                                            .cornerRadius(6)
                                        }
                                    }
                                    .padding(.vertical, 16)
                                    .padding(.horizontal, 24)
                                }
                                
                                Divider()
                            }
                            .id(block.id)
                        }
                    }
                }
                .onChange(of: currentSyncIndex) { newIndex in
                    guard newIndex < blocks.count else { return }
                    withAnimation { proxy.scrollTo(blocks[newIndex].id, anchor: .center) }
                }
                .onChange(of: focusedField) { newFocus in
                    if editMode == .both {
                        if case .lyrics(let id) = newFocus, let index = blocks.firstIndex(where: { $0.id == id }) {
                            currentSyncIndex = index
                        } else if case .time(let id) = newFocus, let index = blocks.firstIndex(where: { $0.id == id }) {
                            currentSyncIndex = index
                        }
                    }
                }
            }
        }
        .onAppear { setupKeyboardMonitor() }
        .onDisappear { teardownKeyboardMonitor() }
    }
    
    // MARK: - Logic
    
    private func setMode(_ mode: SyncEditMode) {
        editMode = mode
        if mode == .translation {
            syncModeActive = false // Disable spacebar syncing automatically
        }
        loadCurrentLyrics()
    }
    
    private func handleLyricsChange(_ newValue: String, at index: Int) {
        guard newValue.contains("\n\n") else {
            blocks[index].lyricsText = newValue
            return
        }
        
        DispatchQueue.main.async {
            let parts = newValue.components(separatedBy: "\n\n")
            blocks[index].lyricsText = parts[0]
            
            var newBlocks: [SyncBlock] = []
            for i in 1..<parts.count {
                let text = parts[i].trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { newBlocks.append(SyncBlock(lyricsText: text)) }
            }
            guard !newBlocks.isEmpty else { return }
            
            blocks.insert(contentsOf: newBlocks, at: index + 1)
            if let firstNew = newBlocks.first { focusedField = .lyrics(firstNew.id) }
        }
    }
    
    private func addBlock(after index: Int) {
        let newBlock = SyncBlock()
        blocks.insert(newBlock, at: index + 1)
        DispatchQueue.main.async { focusedField = .lyrics(newBlock.id) }
    }
    
    private func deleteBlock(at index: Int) {
        guard blocks.count > 1 else { return }
        blocks.remove(at: index)
        if currentSyncIndex >= blocks.count { currentSyncIndex = blocks.count - 1 }
    }
    
    private func setupKeyboardMonitor() {
        spacebarMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if syncModeActive && event.keyCode == 49 {
                handleSyncTrigger()
                return nil
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
            guard currentSyncIndex < blocks.count else { return }
            let currentMs = appState.positionMs
            blocks[currentSyncIndex].timeText = LRCTimeFormatter.msToString(currentMs)
            currentSyncIndex += 1
        }
    }
    
    private func isValidTime(_ text: String) -> Bool {
        if text.isEmpty { return true }
        return LRCTimeFormatter.stringToMs(text) != nil
    }
    
    private func loadCurrentLyrics() {
        let originalLines = appState.syncedLines ?? []
        let translatedLines = appState.translatedLines ?? []

        // Paired by position, not by timeMs — custom lyrics can include
        // untimed lines, which can't be used as a dictionary key.
        let count = max(originalLines.count, translatedLines.count)
        var pairs: [(timeMs: Int?, original: String, trans: String)] = []
        for i in 0..<count {
            let o = i < originalLines.count ? originalLines[i] : nil
            let t = i < translatedLines.count ? translatedLines[i] : nil
            pairs.append((o?.timeMs, o?.text ?? "", t?.text ?? ""))
        }

        if editMode == .translation {
            if !pairs.isEmpty {
                blocks = pairs.map { pair in
                    let timeString = pair.timeMs.map(LRCTimeFormatter.msToString) ?? ""
                    let transText = (pair.trans == "(end)" || pair.trans == "(끝)") ? "(end)" : pair.trans
                    return SyncBlock(timeText: timeString, lyricsText: transText, originalText: pair.original)
                }
            } else {
                blocks = [SyncBlock()]
            }
        } else {
            if !pairs.isEmpty {
                blocks = pairs.map { pair in
                    let timeString = pair.timeMs.map(LRCTimeFormatter.msToString) ?? ""
                    var editorText = pair.original
                    if pair.original == "(end)" || pair.original == "(끝)" {
                        editorText = "(end)"
                    } else if !pair.trans.isEmpty {
                        editorText += "\n\(pair.trans)"
                    }
                    return SyncBlock(timeText: timeString, lyricsText: editorText)
                }
            } else if let plainText = appState.plainLyricsText, !plainText.isEmpty {
                let rawBlocks = plainText.contains("\n\n")
                    ? plainText.components(separatedBy: "\n\n")
                    : plainText.components(separatedBy: .newlines)

                blocks = rawBlocks
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .map { SyncBlock(lyricsText: $0) }
            } else {
                blocks = [SyncBlock()]
            }
        }

        if blocks.isEmpty { blocks = [SyncBlock()] }
        currentSyncIndex = 0
    }

    private func saveCustomLRC() {
        var originalLRC = ""
        var translationLRC = ""
        
        for block in blocks {
            let timeStr = block.timeText.trimmingCharacters(in: .whitespaces)
            let prefix = timeStr.isEmpty ? "" : "[\(timeStr)] "

            if editMode == .translation {
                let originalLower = (block.originalText ?? "").lowercased()

                if originalLower == "(intl)" || originalLower == "(간주중)" {
                    translationLRC += "\(prefix)♪\n"
                } else if originalLower == "(end)" || originalLower == "(끝)" {
                    translationLRC += "\(prefix)(end)\n"
                } else {
                    let transClean = block.lyricsText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !transClean.isEmpty {
                        translationLRC += "\(prefix)\(transClean)\n"
                    }
                }
            } else {
                let rawLyrics = block.lyricsText.trimmingCharacters(in: .whitespacesAndNewlines)
                if rawLyrics.isEmpty { continue }

                let lines = rawLyrics.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                guard !lines.isEmpty else { continue }

                let firstLineLower = lines[0].lowercased()

                if firstLineLower == "(intl)" || firstLineLower == "(간주중)" {
                    originalLRC += "\(prefix)♪\n"
                    translationLRC += "\(prefix)♪\n"
                } else if firstLineLower == "(end)" || firstLineLower == "(끝)" {
                    originalLRC += "\(prefix)(end)\n"
                    translationLRC += "\(prefix)(end)\n"
                } else {
                    originalLRC += "\(prefix)\(lines[0])\n"
                    if lines.count == 2 {
                        translationLRC += "\(prefix)\(lines[1])\n"
                    } else if lines.count >= 3 {
                        translationLRC += "\(prefix)\(lines[2])\n"
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
