import SwiftUI

@main
struct MusicExplorerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear { appState.services.start() }
        }
    }
}

/// Minimal ObservableObject bridge so SwiftUI can react to AppServices'
/// closures.
final class AppState: ObservableObject {
    let services = AppServices()

    @Published var syncedLines: [LyricLine]? = nil
    @Published var currentLineIndex: Int? = nil

    @Published var trackTitle: String = "Nothing playing"
    @Published var artist: String = ""

    // Synced state
    @Published var currentLineText: String = "Searching lyrics..."
    @Published var currentTranslationText: String = ""
    @Published var translatedLines: [LyricLine]? = nil

    // Plain state fallback
    @Published var plainLyricsText: String? = nil

    @Published var positionMs: Int = 0

    // Song info (wiki) + lyrics notes/annotations
    @Published var songInfoText: String? = nil
    @Published var songInfoSource: String? = nil
    @Published var songInfoDocumentID: String? = nil
    @Published var lyricNoteText: String = ""
    @Published var annotationsByLine: [Int: [LyricAnnotation]] = [:]
    @Published var lineNotes: [Int: String] = [:]

    init() {
        services.onCurrentTrackUpdated = { [weak self] track, fetchState, _, note in
            DispatchQueue.main.async {
                self?.trackTitle = track.title
                self?.artist = track.artist
                self?.songInfoText = note?.content ?? ""
                self?.lyricNoteText = self?.services.getLyricNote(trackId: track.id) ?? ""
                self?.annotationsByLine = self?.services.annotationsByLine(for: track.id) ?? [:]
                self?.lineNotes = self?.services.lineNotes(for: track.id) ?? [:]
                self?.songInfoSource = note?.source
                self?.songInfoDocumentID = note?.documentID

                switch fetchState {
                case .success(let result):
                    self?.syncedLines = result.synced
                    self?.translatedLines = result.translatedSynced

                    self?.currentLineText = ""
                    self?.currentTranslationText = ""
                    if result.synced == nil || result.synced!.isEmpty {
                        self?.plainLyricsText = result.plainText
                    } else {
                        self?.plainLyricsText = nil
                    }
                case .notFound:
                    self?.currentLineText = "No synced lyrics found"
                    self?.plainLyricsText = nil
                    self?.syncedLines = nil
                    self?.translatedLines = nil
                case .timeout:
                    self?.currentLineText = "Lyrics request timed out"
                    self?.plainLyricsText = nil
                    self?.syncedLines = nil
                    self?.translatedLines = nil
                case .error:
                    self?.currentLineText = "Error loading lyrics"
                    self?.plainLyricsText = nil
                    self?.syncedLines = nil
                    self?.translatedLines = nil
                }
            }
        }

        services.onPositionTick = { [weak self] ms in
            DispatchQueue.main.async {
                guard let self else { return }
                self.positionMs = ms

                if self.plainLyricsText == nil {
                    let newIndex = self.services.currentLineIndex(atMs: ms)
                    if self.currentLineIndex != newIndex {
                        self.currentLineIndex = newIndex
                    }

                    if let translation = self.services.currentTranslationLine(atMs: ms) {
                        self.currentTranslationText = translation
                    }
                }
            }
        }
    }

    /// Called after saving/deleting an annotation so the main lyrics view
    /// and the notes page both pick up the change immediately.
    func refreshAnnotations() {
        guard let id = services.currentTrack?.id else { return }
        annotationsByLine = services.annotationsByLine(for: id)
    }
}

enum TextAlignmentChoice: String, CaseIterable {
    case left, center, right
    var alignment: TextAlignment {
        switch self { case .left: return .leading; case .center: return .center; case .right: return .trailing }
    }
}

struct SettingsMenu: View {
    @AppStorage("titleSize") var titleSize: Double = 28
    @AppStorage("artistSize") var artistSize: Double = 18
    @AppStorage("lyricSize") var lyricSize: Double = 26
    @AppStorage("transSize") var transSize: Double = 16
    @AppStorage("annotationSize") var annotationSize: Double = 14
    @AppStorage("noteSize") var noteSize: Double = 14
    @AppStorage("lyricAlign") var align: TextAlignmentChoice = .center
    
    var body: some View {
        Form {
            Picker("Alignment", selection: $align) {
                ForEach(TextAlignmentChoice.allCases, id: \.self) { choice in
                    Text(choice.rawValue.capitalized).tag(choice)
                }
            }
            Slider(value: $titleSize, in: 16...40) { Text("Title Size") }
            Slider(value: $artistSize, in: 12...30) { Text("Artist Size") }
            Slider(value: $lyricSize, in: 16...40) { Text("Lyrics Size") }
            Slider(value: $transSize, in: 10...30) { Text("Translation Size") }
            
            Divider().padding(.vertical, 4)
            
            Slider(value: $annotationSize, in: 8...24) { Text("Annotation Size") }
            Slider(value: $noteSize, in: 8...24) { Text("Line Note Size") }
        }
        .padding().frame(width: 300)
    }
}

enum AppPanel { case lyrics, info, history, sync, notes }

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var activePanels: Set<AppPanel> = [.lyrics] // Lyrics open by default
    @State private var showSettings = false

    // Settings loaded for the main view
    @AppStorage("titleSize") var titleSize: Double = 28
    @AppStorage("artistSize") var artistSize: Double = 18
    @AppStorage("showTranslation") var showTranslation: Bool = true
    @AppStorage("showAnnotations") var showAnnotations: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            // 1. LEFT SIDEBAR
            VStack(spacing: 12) {
                SidebarButton(icon: "gearshape", isActive: showSettings) {
                    showSettings.toggle()
                }
                .popover(isPresented: $showSettings) { SettingsMenu() }

                Divider().padding(.horizontal, 8)

                SidebarButton(icon: "music.mic", isActive: activePanels.contains(.lyrics)) { toggle(.lyrics) }
                SidebarButton(icon: "info.circle", isActive: activePanels.contains(.info)) { toggle(.info) }
                SidebarButton(icon: "clock", isActive: activePanels.contains(.history)) { toggle(.history) }
                SidebarButton(icon: "music.quarternote.3", isActive: activePanels.contains(.sync)) { toggle(.sync) }
                // NEW: opens the lyrics notes/annotation editor page.
                SidebarButton(icon: "note.text", isActive: activePanels.contains(.notes)) { toggle(.notes) }
                    .help("Lyrics Notes")

                Divider().padding(.horizontal, 8)

                SidebarButton(icon: "captions.bubble", isActive: showTranslation) {
                    showTranslation.toggle()
                }
                .help("Toggle Translations")

                // NEW: display toggle (not a page button) -- shows/hides
                // annotation superscripts + footnotes in the main lyrics view.
                SidebarButton(icon: "textformat.superscript", isActive: showAnnotations) {
                    showAnnotations.toggle()
                }
                .help("Toggle Annotations")

                Spacer()
            }
            .padding(.top, 20).frame(width: 60)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // 2. RESIZABLE PANELS WITH GEOMETRY RATIOS
            GeometryReader { geometry in
                HSplitView {

                    if activePanels.contains(.lyrics) {
                        LyricsMainView()
                            .frame(minWidth: geometry.size.width * 0.3, maxWidth: .infinity)
                    }

                    if activePanels.contains(.info) {
                        SongInfoEditorView()
                            .frame(minWidth: 260, idealWidth: geometry.size.width * 0.4, maxWidth: geometry.size.width * 0.6)
                    }

                    if activePanels.contains(.history) {
                        Text("Play History")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .frame(minWidth: 260, idealWidth: geometry.size.width * 0.4, maxWidth: geometry.size.width * 0.6)
                    }

                    if activePanels.contains(.sync) {
                        CustomSyncView()
                            .frame(minWidth: 260, idealWidth: geometry.size.width * 0.4, maxWidth: geometry.size.width * 0.6)
                    }

                    if activePanels.contains(.notes) {
                        LyricsNoteEditorView()
                            .frame(minWidth: 260, idealWidth: geometry.size.width * 0.4, maxWidth: geometry.size.width * 0.6)
                    }

                }
            }
        }
        .frame(minWidth: 800, minHeight: 500)
    }

    private func toggle(_ panel: AppPanel) {
        if activePanels.contains(panel) {
            if activePanels.count > 1 { activePanels.remove(panel) } // Prevents closing the last panel
        } else {
            activePanels.insert(panel)
        }
    }
}

struct LyricLineView: View {
    let originalText: String
    let translationText: String?
    let lineIndex: Int
    let annotations: [LyricAnnotation]
    let lineNote: String?
    let isCurrent: Bool
    let action: () -> Void

    @AppStorage("lyricSize") var lyricSize: Double = 26
    @AppStorage("transSize") var transSize: Double = 16
    @AppStorage("annotationSize") var annotationSize: Double = 14
    @AppStorage("noteSize") var noteSize: Double = 14
    @AppStorage("lyricAlign") var align: TextAlignmentChoice = .center
    @AppStorage("showTranslation") var showTranslation: Bool = true
    @AppStorage("showAnnotations") var showAnnotations: Bool = false

    @State private var isHovered = false
    @State private var isNoteExpanded = false

    private var displayNotes: [(tag: String, note: LyricAnnotation)] {
        var results: [(tag: String, note: LyricAnnotation)] = []
        var counter = 1
        for note in annotations.sorted(by: { $0.wordIndex < $1.wordIndex }) {
            if let custom = note.marker, !custom.isEmpty {
                results.append(("[\(custom)]", note))
            } else {
                results.append(("[\(counter)]", note))
                counter += 1
            }
        }
        return results
    }
    
    // 1. Tying Line Notes directly to the Annotation Toggle
    private var hasNote: Bool {
        showAnnotations && lineNote != nil && !lineNote!.isEmpty
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            
            HStack(alignment: .top, spacing: 20) {
                if align == .center && hasNote {
                    Color.clear.frame(minWidth: 200, idealWidth: 250, maxWidth: 300)
                }
                
                mainLyricContent
                    .layoutPriority(1)
                
                if hasNote {
                    lineNoteContainer
                        .frame(minWidth: 200, idealWidth: 250, maxWidth: 300, alignment: .leading)
                        .padding(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: align == .left ? .leading : (align == .right ? .trailing : .center))
            
            VStack(alignment: align == .left ? .leading : (align == .right ? .trailing : .center), spacing: 8) {
                mainLyricContent
                if hasNote {
                    lineNoteContainer
                        .frame(maxWidth: 300, alignment: align == .left ? .leading : (align == .right ? .trailing : .center))
//                        .padding(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: align == .left ? .leading : (align == .right ? .trailing : .center))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .cornerRadius(8)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            action()
        }
    }

    @ViewBuilder
    private var mainLyricContent: some View {
        VStack(spacing: 6) {
            if originalText.isEmpty {
                Text("♪")
                    .font(.system(size: isCurrent ? lyricSize : lyricSize - 4, weight: isCurrent ? .bold : .medium))
                    .foregroundStyle(isCurrent ? Color.primary : Color.primary.opacity(0.3))
            } else if showAnnotations && !annotations.isEmpty {
                // Grouped by word (for natural spacing/wrapping) but each
                // letter is its own unit -- must match lyricLetterGroups'
                // indexing so a tag lands on the exact letter it was placed
                // on in the notes editor, not just "the word containing it".
                let groups = lyricLetterGroups(for: originalText)
                HStack(spacing: 4) {
                    ForEach(Array(groups.indices), id: \.self) { g in
                        HStack(spacing: 0) {
                            ForEach(groups[g]) { letter in
                                HStack(spacing: 0) {
                                    Text(String(letter.char))
                                    if let tag = displayNotes.first(where: { $0.note.wordIndex == letter.id })?.tag {
                                        Text(tag)
                                            .font(.system(size: annotationSize, weight: .bold))
                                            .baselineOffset(8)
                                            // Matched to lyric color exactly
                                            .foregroundStyle(isCurrent ? Color.primary : Color.primary.opacity(0.3))
                                    }
                                }
                            }
                        }
                    }
                }
                .font(.system(size: isCurrent ? lyricSize : lyricSize - 4, weight: isCurrent ? .bold : .medium))
                .foregroundStyle(isCurrent ? Color.primary : Color.primary.opacity(0.3))
                .underline(isHovered)
            } else {
                Text(originalText)
                    .font(.system(size: isCurrent ? lyricSize : lyricSize - 4, weight: isCurrent ? .bold : .medium))
                    .foregroundStyle(isCurrent ? Color.primary : Color.primary.opacity(0.3))
                    .underline(isHovered)
            }

            if showTranslation, let trans = translationText, !trans.isEmpty {
                Text(trans)
                    .font(.system(size: isCurrent ? transSize : transSize - 4, weight: .medium))
                    .foregroundStyle(isCurrent ? Color.primary : Color.primary.opacity(0.3))
                    .underline(isHovered)
            }

            if showAnnotations && !displayNotes.isEmpty {
                VStack(spacing: 2) {
                    ForEach(displayNotes, id: \.note.wordIndex) { item in
                        Text("\(item.tag): \(item.note.noteText)")
                            .font(.system(size: annotationSize, weight: .bold))
                            // Matched to lyric color exactly
                            .foregroundStyle(isCurrent ? Color.primary : Color.primary.opacity(0.3))
                            .frame(maxWidth: 350)
                    }
                }
                .padding(.top, 14)
            }
        }
        .multilineTextAlignment(align.alignment)
    }

    @ViewBuilder
    private var lineNoteContainer: some View {
        if let text = lineNote, !text.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.system(size: noteSize))
                    .foregroundStyle(.secondary)
                    // Allows 6 lines (double the previous amount) before truncating
                    .lineLimit(isNoteExpanded ? nil : 6)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading) // Anchors text to the top
                
                // Lowered threshold to 60 characters per your request
                if text.count > 140 {
                    Button(action: {
                        withAnimation { isNoteExpanded.toggle() }
                    }) {
                        Text(isNoteExpanded ? "\(Image(systemName: "arrow.down.right.and.arrow.up.left"))" : "\(Image(systemName: "arrow.up.left.and.arrow.down.right"))")
                            .font(.system(size: max(noteSize - 2, 10), weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            // Forces the represented container to be 100% taller visually
            .frame(minHeight: 120, alignment: .topLeading)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

// 2. The Main Scrolling View
struct LyricsMainView: View {
    @EnvironmentObject var appState: AppState
    
    @AppStorage("titleSize") var titleSize: Double = 28
    @AppStorage("artistSize") var artistSize: Double = 18
    @AppStorage("lyricAlign") var align: TextAlignmentChoice = .center

    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            Divider()
            
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
    }
    
    // --- Extracted Sub-Views for Compiler Speed ---
    
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
        .padding(.horizontal, 40)
    }
    
    private func syncedLyricsList(lines: [LyricLine]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: align == .left ? .leading : (align == .right ? .trailing : .center), spacing: 8) {
                    
                    Color.clear.frame(height: 40)
                    
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        lyricRow(index: index, line: line, totalLines: lines.count)
                    }
                    
                    Color.clear.frame(height: 100)
                }
                .padding(.horizontal, 40)
                .frame(maxWidth: .infinity, alignment: align == .center ? .center : (align == .left ? .leading : .trailing))
            }
            .id(appState.trackTitle)
            .onChange(of: appState.currentLineIndex) { newIndex in
                guard let idx = newIndex else { return }
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
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
        let isCurrent = (index == appState.currentLineIndex) && !isEndMarker

        if isEndMarker {
            Color.clear.frame(height: 1).id(index)
        } else {
            // Paired by position, not by timeMs — timeMs may be nil for
            // custom untimed lines, and nil == nil would wrongly match
            // every untimed line to the first untimed translation.
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
                appState.positionMs = ms
                appState.services.seek(to: ms)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isCurrent)
            .id(index)
        }
    }
}

struct SidebarButton: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(isActive ? .primary : .secondary)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isActive ? Color.primary.opacity(0.1) : (isHovered ? Color.gray.opacity(0.2) : Color.clear))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
