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

/// Not `private` to `CustomSyncView` on purpose -- shared by `SyncBlockRow`
/// too, and there's nowhere else it needs hiding from.
fileprivate func isValidTime(_ text: String) -> Bool {
    if text.isEmpty { return true }
    return LRCTimeFormatter.stringToMs(text) != nil
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
    // ID-based, not index-based: indices shift on every insert/delete, which
    // used to force the whole `blocks` array to be re-touched (and every
    // row's inline bindings rebuilt) just to keep the "current" pointer
    // valid. Tracking the block's own id sidesteps that entirely.
    @State private var currentSyncID: UUID? = nil
    @State private var editMode: SyncEditMode = .both
    @State private var spacebarMonitor: Any?
    // Only the spacebar sync trigger writes here. currentSyncID still
    // updates on click/typing (for the highlight), but that alone must never
    // scroll -- only this should.
    @State private var scrollTargetID: UUID? = nil

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
            //
            // Perf note: each row used to be built inline here with
            // `Binding(get:set:)` closures reading/writing `blocks[index]`
            // directly. Because that binding's storage IS this view's
            // @State array, typing a single character invalidated the
            // *whole* array, which re-ran this ForEach and rebuilt every
            // row's closures -- for a full song that's 100-300 rows
            // reconstructed per keystroke, which is what was laggy.
            //
            // Now each row is its own `Equatable` view fed a `Binding` to
            // just its own element via `ForEach($blocks)`. SwiftUI compares
            // old vs. new row values via `.equatable()` and skips re-running
            // `body` for every row except the one that actually changed.
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach($blocks) { $block in
                            SyncBlockRow(
                                block: $block,
                                editMode: editMode,
                                isSyncTarget: syncModeActive && block.id == currentSyncID,
                                canDelete: blocks.count > 1,
                                focusedField: $focusedField,
                                onSeek: {
                                    if let ms = LRCTimeFormatter.stringToMs(block.timeText) {
                                        appState.services.seek(to: ms)
                                    }
                                },
                                onAdd: { addBlock(afterID: block.id) },
                                onDelete: { deleteBlock(id: block.id) },
                                onLyricsChange: { newValue in handleLyricsChange(newValue, id: block.id) }
                            )
                            .equatable()
                            .id(block.id)
                        }
                    }
                }
                .onChange(of: scrollTargetID) { id in
                    guard let id else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
                .onChange(of: focusedField) { newFocus in
                    // Clicking or typing into a block updates which block is
                    // "current" (for the highlight), but must NOT auto-scroll.
                    if editMode == .both {
                        if case .lyrics(let id) = newFocus {
                            currentSyncID = id
                        } else if case .time(let id) = newFocus {
                            currentSyncID = id
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
    
    private func handleLyricsChange(_ newValue: String, id: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        guard newValue.contains("\n\n") else {
            blocks[index].lyricsText = newValue
            return
        }
        
        DispatchQueue.main.async {
            // Re-resolve the index: the array may have changed (another
            // async split, a delete, etc.) between now and when this was
            // scheduled.
            guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
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
    
    private func addBlock(afterID id: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        let newBlock = SyncBlock()
        blocks.insert(newBlock, at: index + 1)
        DispatchQueue.main.async { focusedField = .lyrics(newBlock.id) }
    }
    
    private func deleteBlock(id: UUID) {
        guard blocks.count > 1, let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks.remove(at: index)
        if currentSyncID == id {
            currentSyncID = blocks.indices.contains(index) ? blocks[index].id : blocks.last?.id
        }
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
            guard let currentID = currentSyncID, let idx = blocks.firstIndex(where: { $0.id == currentID }) else {
                currentSyncID = blocks.first?.id
                return
            }
            let currentMs = appState.positionMs
            blocks[idx].timeText = LRCTimeFormatter.msToString(currentMs)
            let nextIdx = idx + 1
            // Spacebar syncing is the one case that should auto-scroll, so
            // it's the only place that sets scrollTargetID.
            if blocks.indices.contains(nextIdx) {
                currentSyncID = blocks[nextIdx].id
                scrollTargetID = blocks[nextIdx].id
            }
        }
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
        currentSyncID = blocks.first?.id
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

/// A single editor row, isolated so a keystroke in one row doesn't force
/// SwiftUI to re-diff every other row in the (potentially 100-300 row) list.
/// `.equatable()` at the call site is what actually activates the skip --
/// see the perf note above `ScrollViewReader` in `CustomSyncView`.
struct SyncBlockRow: View, Equatable {
    @Binding var block: SyncBlock
    let editMode: SyncEditMode
    let isSyncTarget: Bool
    let canDelete: Bool
    let focusedField: FocusState<SyncFocusField?>.Binding
    let onSeek: () -> Void
    let onAdd: () -> Void
    let onDelete: () -> Void
    let onLyricsChange: (String) -> Void

    // Closures are intentionally excluded: they're re-created every parent
    // render regardless (cheap), but comparing them would make `.equatable()`
    // always report "changed" and defeat the whole point.
    static func == (lhs: SyncBlockRow, rhs: SyncBlockRow) -> Bool {
        lhs.block == rhs.block
            && lhs.editMode == rhs.editMode
            && lhs.isSyncTarget == rhs.isSyncTarget
            && lhs.canDelete == rhs.canDelete
    }

    private var lyricsBinding: Binding<String> {
        Binding(get: { block.lyricsText }, set: onLyricsChange)
    }

    var body: some View {
        VStack(spacing: 0) {
            if editMode == .both {
                // MODE: BOTH (Full Sync Controls)
                HStack(alignment: .top, spacing: 16) {
                    Button(action: onSeek) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12))
                            .foregroundColor(block.timeText.isEmpty ? .gray.opacity(0.4) : .accentColor)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)

                    TextField("00:00.00", text: $block.timeText)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.plain)
                        .focused(focusedField, equals: .time(block.id))
                        .frame(width: 70)
                        .foregroundColor(isValidTime(block.timeText) ? .primary : .red)
                        .padding(.top, 6)

                    TextField("Lyrics...", text: lyricsBinding, axis: .vertical)
                        .textFieldStyle(.plain)
                        .focused(focusedField, equals: .lyrics(block.id))
                        .lineLimit(2...10)
                        .padding(.top, 6)

                    VStack(spacing: 16) {
                        Button(action: onAdd) { Image(systemName: "plus").foregroundColor(.secondary) }.buttonStyle(.plain)
                        Button(action: onDelete) { Image(systemName: "minus").foregroundColor(.secondary) }.buttonStyle(.plain).disabled(!canDelete)
                    }
                    .padding(.top, 6)
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 24)
                .background(isSyncTarget ? Color.accentColor.opacity(0.1) : Color.clear)

            } else {
                // FIX: MODE: TRANSLATION ONLY (Simplified UI)
                HStack(alignment: .top, spacing: 16) {
                    // Read-Only Time
                    Text(block.timeText.isEmpty ? "--:--.--" : block.timeText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 70, alignment: .leading)
                        .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 10) {
                        // Read-Only Original Lyrics
                        Text(block.originalText ?? "♪")
                            .font(.system(.body, weight: .semibold))
                            .foregroundColor(.primary)

                        // Translation Editor Box
                        TextField("Translation...", text: $block.lyricsText, axis: .vertical)
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
    }
}
