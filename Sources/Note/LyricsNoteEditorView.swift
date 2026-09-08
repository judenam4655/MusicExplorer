import SwiftUI

/// The "lyrics note page": per-letter annotations (shown as a superscript
/// marker inline, with the note text listed as a footnote below) plus one
/// free-form note per track. Layout per spec: original line, translated
/// line, extra space, then annotation footnotes.
///
/// Letter-level: each character gets its own tap target (grouped visually by
/// word so wrapping still looks like normal text). Annotations are keyed by
/// a letter's index within the full line string.
///
/// A line isn't limited to one annotation per letter: the "+ Add annotation"
/// button below each line opens another editor that isn't pinned to any
/// letter at all, using a synthetic (negative) index so it can't collide
/// with a real character position. Add as many of these as you like.


/// Reports the natural (unconstrained) size of one representative note-editor
/// row up to `ContentView`, which uses it to set the window's *minimum*
/// size while the Notes panel is open -- see the "Dynamic window minimum
/// size" section there. Deliberately measures only the first line (via a
/// single GeometryReader), not every row: the goal is "don't let the window
/// get smaller than one comfortable row", not "fit the whole song", which
/// would defeat scrolling and also reintroduce the per-row GeometryReader
/// cost we removed for the letter-annotation performance fix.
struct NotesIdealSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        value = CGSize(width: max(value.width, next.width), height: max(value.height, next.height))
    }
}

struct LyricsNoteEditorView: View {
    @EnvironmentObject var appState: AppState
    @State private var editingWord: (lineIndex: Int, wordIndex: Int)? = nil
    @State private var draftNote: String = ""
    @State private var noteEditing = false
    
    // Bulk-editing path: hand the whole page off to the person's actual
    // text editor instead of this view. See ExternalTextEditorBridge and
    // LyricNoteTextFormat -- this view never touches the file's contents
    // directly, it only knows the URL to read back from.
    @State private var externalFileURL: URL? = nil
    @State private var externalEditAlert: String? = nil
    
    // Internal Editor Modes & Options
    @State private var isRawTextMode: Bool = false
    @State private var enableAnnotationEdits: Bool = false
    @State private var rawText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                // Mode Switcher (Visual vs Raw Text)
                HStack(spacing: 4) {
                    CustomModeButton(icon: "eye", isSelected: !isRawTextMode) {
                        if isRawTextMode { saveFromRawText() }
                        isRawTextMode = false
                    }
                    CustomModeButton(icon: "text.alignleft", isSelected: isRawTextMode) {
                        loadIntoRawText()
                        isRawTextMode = true
                    }
                }
                .padding(4)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 1))

                // Optional Annotation Edits Toggle (Visual Mode only)
                if !isRawTextMode {
                    Toggle("Edits", isOn: $enableAnnotationEdits)
                        .toggleStyle(.checkbox)
                } else {
                    Button("Save Text Changes") {
                        saveFromRawText()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Spacer()

                // Existing External Editor Buttons
                Button(action: openInExternalEditor) {
                    Label("External Editor", systemImage: "square.and.pencil")
                }
                .buttonStyle(.plain)

                Button(action: loadFromExternalEditor) {
                    Label("Load External", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.plain)
                .disabled(externalFileURL == nil)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // EDITOR CONTENT (Visual View vs Large Internal Text Editor)
            if isRawTextMode {
                TextEditor(text: $rawText)
                    .font(.system(.body, design: .monospaced))
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        if let lines = appState.syncedLines, !lines.isEmpty {
                            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                if index == 0 {
                                    lineBlock(index: index, line: line)
                                        .background(
                                            GeometryReader { geo in
                                                Color.clear.preference(key: NotesIdealSizeKey.self, value: geo.size)
                                            }
                                        )
                                } else {
                                    lineBlock(index: index, line: line)
                                }
                            }
                        } else {
                            Text("No synced lyrics loaded for this track yet.")
                                .foregroundStyle(.secondary)
                                .padding()
                        }

                        Divider().padding(.vertical, 8)

                        // Global Track Notes
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Track Notes").font(.subheadline).bold()
                                Spacer()
                                Button(noteEditing ? "Save" : "Edit") {
                                    if noteEditing {
                                        appState.services.saveLyricNote(draftNote)
                                        appState.lyricNoteText = draftNote
                                    } else {
                                        draftNote = appState.lyricNoteText
                                    }
                                    noteEditing.toggle()
                                }
                            }
                            if noteEditing {
                                TextEditor(text: $draftNote)
                                    .frame(minHeight: 120)
                                    .font(.body)
                            } else {
                                Text(appState.lyricNoteText.isEmpty ? "No notes yet." : appState.lyricNoteText)
                                    .foregroundStyle(appState.lyricNoteText.isEmpty ? .secondary : .primary)
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Load Changes", isPresented: Binding(
            get: { externalEditAlert != nil },
            set: { if !$0 { externalEditAlert = nil } }
        )) {
            Button("OK") { externalEditAlert = nil }
        } message: {
            Text(externalEditAlert ?? "")
        }
    }

    // MARK: - External text editor bridge

    private func buildDocumentForExternalEditor() -> ParsedLyricDocument {
        var doc = ParsedLyricDocument()
        doc.songNote = appState.lyricNoteText

        let lines = appState.syncedLines ?? []
        for (index, line) in lines.enumerated() {
            var parsedLine = ParsedLyricLine(timeMs: line.timeMs, text: line.text)
            let existing = appState.annotationsByLine[index] ?? []
            for note in existing.sorted(by: { $0.wordIndex < $1.wordIndex }) {
                let marker = (note.marker?.isEmpty == false) ? note.marker! : "\(note.wordIndex)"
                parsedLine.annotations.append(
                    ParsedAnnotation(charIndex: note.wordIndex, marker: marker, noteText: note.noteText)
                )
            }
            parsedLine.lineNote = appState.lineNotes[index] ?? ""
            doc.lines.append(parsedLine)
        }
        return doc
    }

    private func openInExternalEditor() {
        let doc = buildDocumentForExternalEditor()
        let text = LyricNoteTextFormat.serialize(doc)
        let filename = ExternalTextEditorBridge.sanitizedFilename(appState.trackTitle, suffix: "notes")
        externalFileURL = ExternalTextEditorBridge.open(text: text, filename: filename)
        
        if let window = NSApplication.shared.windows.first(where: { $0.isKeyWindow ?? false }) {
            if let screen = window.screen {
                let screenRect = screen.visibleFrame
                let newWidth: CGFloat = screenRect.width * 0.7
                let newHeight = screenRect.height
                
                let newFrame = NSRect(
                    x: screenRect.minX,
                    y: screenRect.minY,
                    width: newWidth,
                    height: newHeight
                )
                
                window.setFrame(newFrame, display: true, animate: true)
            }
        }
    }

    private func loadFromExternalEditor() {
        guard let url = externalFileURL else { return }
        guard let text = ExternalTextEditorBridge.load(from: url) else {
            externalEditAlert = "Couldn't read the file. Make sure it's saved."
            return
        }

        let doc = LyricNoteTextFormat.parse(text)

        appState.services.saveLyricNote(doc.songNote)
        appState.lyricNoteText = doc.songNote

        let lines = appState.syncedLines ?? []
        var mismatchWarning = ""
        if doc.lines.count != lines.count {
            mismatchWarning = " Note: the file has \(doc.lines.count) lyric lines but the song has \(lines.count) -- lines were matched by position, so double-check anything near the end."
        }

        for (index, _) in lines.enumerated() {
            let oldAnnotations = appState.annotationsByLine[index] ?? []
            let newAnnotations = index < doc.lines.count ? doc.lines[index].annotations : []
            let newIndices = Set(newAnnotations.map { $0.charIndex })

            for old in oldAnnotations where !newIndices.contains(old.wordIndex) {
                appState.services.saveAnnotation(lineIndex: index, wordIndex: old.wordIndex, text: "", marker: nil)
            }
            for ann in newAnnotations {
                appState.services.saveAnnotation(lineIndex: index, wordIndex: ann.charIndex, text: ann.noteText, marker: ann.marker)
            }

            let newLineNote = index < doc.lines.count ? doc.lines[index].lineNote : ""
            appState.lineNotes[index] = newLineNote
            appState.services.saveLineNote(lineIndex: index, text: newLineNote)
        }

        appState.refreshAnnotations()
        externalEditAlert = "Changes loaded." + mismatchWarning
    }
    
    // MARK: - Internal Raw Text Logic
    
    private func loadIntoRawText() {
        let doc = buildDocumentForExternalEditor()
        rawText = LyricNoteTextFormat.serialize(doc)
    }

    private func saveFromRawText() {
        let doc = LyricNoteTextFormat.parse(rawText)

        appState.services.saveLyricNote(doc.songNote)
        appState.lyricNoteText = doc.songNote

        let lines = appState.syncedLines ?? []
        for (index, _) in lines.enumerated() {
            let oldAnnotations = appState.annotationsByLine[index] ?? []
            let newAnnotations = index < doc.lines.count ? doc.lines[index].annotations : []

            var oldByIndex = Dictionary(oldAnnotations.map { ($0.wordIndex, $0) }, uniquingKeysWith: { a, _ in a })

            for ann in newAnnotations {
                if let existing = oldByIndex.removeValue(forKey: ann.charIndex), let id = existing.id {
                    // Existing annotation at this position -> update in place.
                    appState.services.saveAnnotation(id: id, lineIndex: index, wordIndex: ann.charIndex, text: ann.noteText, marker: ann.marker)
                } else {
                    // No existing annotation here -> genuinely new.
                    appState.services.saveAnnotation(lineIndex: index, wordIndex: ann.charIndex, text: ann.noteText, marker: ann.marker)
                }
            }

            // Anything left in oldByIndex had no counterpart in the new text -> actually delete it.
            for (_, old) in oldByIndex {
                if let id = old.id {
                    appState.services.deleteAnnotation(id: id)
                }
            }

            let newLineNote = index < doc.lines.count ? doc.lines[index].lineNote : ""
            appState.lineNotes[index] = newLineNote
            appState.services.saveLineNote(lineIndex: index, text: newLineNote)
        }

        appState.refreshAnnotations()
    }

    private func lineBlock(index: Int, line: LyricLine) -> some View {
        let groups = lyricLetterGroups(for: line.text)
        let lineAnnotations = appState.annotationsByLine[index] ?? []
        let translated = appState.translatedLines
        let translation = (translated != nil && index < translated!.count) ? translated![index].text : nil

        var displayNotes: [DisplayNote] = []
        var counter = 1
        let sortedAnnotations = lineAnnotations.sorted { a, b in
            if a.wordIndex != b.wordIndex { return a.wordIndex < b.wordIndex }
            return (a.id ?? 0) < (b.id ?? 0)
        }
        for note in sortedAnnotations {
            if let custom = note.marker, !custom.isEmpty {
                displayNotes.append(DisplayNote(tag: "[\(custom)]", note: note))
            } else {
                displayNotes.append(DisplayNote(tag: "[\(counter)]", note: note))
                counter += 1
            }
        }

        func label(for wordIndex: Int) -> String {
            if wordIndex < 0 { return "Note" }
            let chars = Array(line.text)
            return chars.indices.contains(wordIndex) ? String(chars[wordIndex]) : "?"
        }

        return HStack(alignment: .top, spacing: 20) {
            // LEFT COLUMN: Lyrics & Annotation Editors
            VStack(alignment: .leading, spacing: 6) {
                FlowLayout(spacing: 6, lineSpacing: 8) {
                    ForEach(groups.indices, id: \.self) { groupIndex in
                        HStack(spacing: 0) {
                            ForEach(groups[groupIndex]) { letter in
                                let tagsForLetter = displayNotes.filter { $0.note.wordIndex == letter.id }.map { $0.tag }
                                letterView(lineIndex: index, charIndex: letter.id, char: String(letter.char), tags: tagsForLetter)
                            }
                        }
                        .fixedSize()
                    }
                }

                if let translation = translation, !translation.isEmpty {
                    Text(translation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }

                // Annotation Editors rendered only if enabled
                if enableAnnotationEdits {
                    if !displayNotes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(displayNotes) { item in
                                AnnotationEditorBox(
                                    id: item.note.id,
                                    lineIndex: index,
                                    wordIndex: item.note.wordIndex,
                                    word: label(for: item.note.wordIndex),
                                    initialMarker: item.note.marker ?? "",
                                    initialText: item.note.noteText
                                )
                            }
                        }
                        .padding(.top, 8)
                    }
                    
                    if let editing = editingWord, editing.lineIndex == index {
                        NewAnnotationEditorBox(lineIndex: index, wordIndex: editing.wordIndex, word: label(for: editing.wordIndex)) {
                            editingWord = nil
                        }
                    }

                    Button {
                        let lowestUsed = lineAnnotations.map { $0.wordIndex }.min() ?? 0
                        editingWord = (index, min(0, lowestUsed) - 1)
                    } label: {
                        Label("Add annotation", systemImage: "plus.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func letterView(lineIndex: Int, charIndex: Int, char: String, tags: [String]) -> some View {
        HStack(spacing: 0) {
            Text(char)
                .font(.system(size: 18, weight: .medium))
                .fixedSize()
            
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 10, weight: .bold))
                    .baselineOffset(8)
                    .foregroundStyle(.orange)
                    .fixedSize()
            }
        }
        .fixedSize()
        .contentShape(Rectangle())
        .onTapGesture {
            guard enableAnnotationEdits else { return }
            if editingWord?.lineIndex == lineIndex && editingWord?.wordIndex == charIndex {
                editingWord = nil
            } else {
                editingWord = (lineIndex, charIndex)
            }
        }
    }
}

struct LyricLetter: Identifiable {
    let id: Int
    let char: Character
}

func lyricLetterGroups(for text: String) -> [[LyricLetter]] {
    var groups: [[LyricLetter]] = []
    var current: [LyricLetter] = []
    for (i, ch) in text.enumerated() {
        if ch == " " {
            if !current.isEmpty { groups.append(current); current = [] }
        } else {
            current.append(LyricLetter(id: i, char: ch))
        }
    }
    if !current.isEmpty { groups.append(current) }
    return groups
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        let width = maxWidth.isFinite ? maxWidth : x
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct DisplayNote: Identifiable {
    var id: Int64 { note.id ?? -1 }
    let tag: String
    let note: LyricAnnotation
}

struct LineNoteEditorBox: View {
    let lineIndex: Int
    @EnvironmentObject var appState: AppState
    
    @State private var draftText: String = ""
    @State private var isEditing: Bool = false
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            TextEditor(text: $draftText)
                .font(.body)
                .frame(minHeight: 80)
                .padding(6)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .onChange(of: draftText) { _ in
                    isEditing = true
                }
            
            if isEditing && draftText != (appState.lineNotes[lineIndex] ?? "") {
                Button("Save") {
                    appState.lineNotes[lineIndex] = draftText
                    appState.services.saveLineNote(lineIndex: lineIndex, text: draftText)
                    isEditing = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .onAppear {
            draftText = appState.lineNotes[lineIndex] ?? ""
            isEditing = false
        }
        .onChange(of: appState.lineNotes[lineIndex]) { newVal in
            if !isEditing {
                draftText = newVal ?? ""
            }
        }
    }
}

struct AnnotationEditorBox: View {
    let id: Int64?
    let lineIndex: Int
    let wordIndex: Int
    let word: String
    let initialMarker: String
    let initialText: String
    
    @EnvironmentObject var appState: AppState
    @State private var marker: String = ""
    @State private var text: String = ""
    @State private var isEditing: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Marker", text: $marker)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 75)
                
                Spacer()
                
                if isEditing {
                    Button {
                        appState.services.saveAnnotation(id: id, lineIndex: lineIndex, wordIndex: wordIndex, text: text, marker: marker)
                        appState.refreshAnnotations()
                        isEditing = false
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                Button {
                    if let id {
                        appState.services.deleteAnnotation(id: id)
                        appState.refreshAnnotations()
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain).foregroundStyle(.red).font(.caption)
            }
            
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 50)
                .padding(4)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
        }
        .padding(10)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
        .onAppear {
            marker = initialMarker
            text = initialText
        }
        .onChange(of: marker) { _ in isEditing = true }
        .onChange(of: text) { _ in isEditing = true }
    }
}

struct NewAnnotationEditorBox: View {
    let lineIndex: Int
    let wordIndex: Int
    let word: String
    let onClose: () -> Void
    
    @EnvironmentObject var appState: AppState
    @State private var marker: String = ""
    @State private var text: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Marker", text: $marker)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 75)
                
                Spacer()
                
                Button {
                    appState.services.saveAnnotation(lineIndex: lineIndex, wordIndex: wordIndex, text: text, marker: marker)
                    appState.refreshAnnotations()
                    onClose()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                
                Button(action: onClose){
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain).foregroundStyle(.red).font(.caption)
            }
            
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 50)
                .padding(4)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
        }
        .padding(10)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
        .padding(.top, 8)
    }
}
