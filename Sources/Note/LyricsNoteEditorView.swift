import SwiftUI

/// The "lyrics note page": per-word annotations (shown as a superscript
/// marker inline, with the note text listed as a footnote below) plus one
/// free-form note per track. Layout per spec: original line, translated
/// line, extra space, then annotation footnotes.
///
/// Word-level, not character-level: SwiftUI's Text has no per-character tap
/// targets without a custom TextKit/AppKit view, which is a materially
/// bigger lift than this. This gets you "annotate any word" today; if you
/// want true "any letter" precision later, that's a custom NSTextView-backed
/// editor -- happy to build that as a follow-up if word-level isn't enough.


struct LyricsNoteEditorView: View {
    @EnvironmentObject var appState: AppState
    @State private var editingWord: (lineIndex: Int, wordIndex: Int)? = nil
    @State private var draftNote: String = ""
    @State private var noteEditing = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Lyrics Notes").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if let lines = appState.syncedLines, !lines.isEmpty {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            lineBlock(index: index, line: line)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func lineBlock(index: Int, line: LyricLine) -> some View {
        let words = line.text.split(separator: " ").map(String.init)
        let lineAnnotations = appState.annotationsByLine[index] ?? []
        let translation = appState.translatedLines?.first(where: { $0.timeMs == line.timeMs })?.text

        var displayNotes: [DisplayNote] = []
        var counter = 1
        for note in lineAnnotations.sorted(by: { $0.wordIndex < $1.wordIndex }) {
            if let custom = note.marker, !custom.isEmpty {
                displayNotes.append(DisplayNote(tag: "[\(custom)]", note: note))
            } else {
                displayNotes.append(DisplayNote(tag: "[\(counter)]", note: note))
                counter += 1
            }
        }

        return HStack(alignment: .top, spacing: 20) {
            // LEFT COLUMN: Lyrics & Annotation Editors
            VStack(alignment: .leading, spacing: 6) {
                WrapHStack(words.indices.map { $0 }, spacing: 4) { wordIndex in
                    let noteObj = displayNotes.first(where: { $0.note.wordIndex == wordIndex })
                    wordView(
                        lineIndex: index,
                        wordIndex: wordIndex,
                        word: words[wordIndex],
                        tag: noteObj?.tag,
                        hasExisting: noteObj != nil
                    )
                }

                if let translation = translation, !translation.isEmpty {
                    Text(translation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }

                // 1. EXIST BY DEFAULT: Editors for already-annotated words
                if !displayNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(displayNotes) { item in
                            AnnotationEditorBox(
                                lineIndex: index,
                                wordIndex: item.note.wordIndex,
                                word: words.indices.contains(item.note.wordIndex) ? words[item.note.wordIndex] : "?",
                                initialMarker: item.note.marker ?? "",
                                initialText: item.note.noteText
                            )
                        }
                    }
                    .padding(.top, 8)
                }
                
                // 2. NEW ANNOTATION: Appears only when an empty word is clicked
                if let editing = editingWord, editing.lineIndex == index, !displayNotes.contains(where: { $0.note.wordIndex == editing.wordIndex }) {
                    let currentWord = words.indices.contains(editing.wordIndex) ? words[editing.wordIndex] : "?"
                    NewAnnotationEditorBox(lineIndex: index, wordIndex: editing.wordIndex, word: currentWord) {
                        editingWord = nil
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            // RIGHT COLUMN: Per-line Note Text Box
            VStack(alignment: .leading, spacing: 4) {
                Text("Line Note").font(.caption2).foregroundStyle(.secondary)
                LineNoteEditorBox(lineIndex: index)
            }
            .frame(width: 260)
        }
    }

    @ViewBuilder
    private func wordView(lineIndex: Int, wordIndex: Int, word: String, tag: String?, hasExisting: Bool) -> some View {
        Button(action: {
            if hasExisting {
                // Do nothing if clicked; the editor is already permanently visible below!
                return
            }
            
            if editingWord?.lineIndex == lineIndex && editingWord?.wordIndex == wordIndex {
                editingWord = nil // Toggle off
            } else {
                editingWord = (lineIndex, wordIndex) // Open new editor
            }
        }) {
            HStack(spacing: 1) {
                Text(word)
                    .font(.system(size: 18, weight: .medium))
                
                if let tag = tag {
                    Text(tag)
                        .font(.system(size: 12, weight: .bold))
                        .baselineOffset(8)
                        .foregroundStyle(.orange)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// Minimal wrapping-HStack helper (words wrap like text). This is the
/// well-known GeometryReader/alignment-guide workaround for pre-Layout-
/// protocol SwiftUI -- functional, but flag it if you see any jitter on
/// resize; a macOS-14+ `Layout` conformance would be a cleaner long-term fix.
struct WrapHStack<Content: View>: View {
    let items: [Int]
    let spacing: CGFloat
    let content: (Int) -> Content

    init(_ items: [Int], spacing: CGFloat = 4, @ViewBuilder content: @escaping (Int) -> Content) {
        self.items = items
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        FlexibleView(data: items, spacing: spacing, content: content)
    }
}

struct FlexibleView<Data: BidirectionalCollection, Content: View>: View where Data.Element: Hashable {
    let data: Data
    let spacing: CGFloat
    let content: (Data.Element) -> Content

    @State private var totalHeight = CGFloat.zero

    var body: some View {
        VStack {
            GeometryReader { geometry in
                self.generateContent(in: geometry)
            }
        }
        .frame(height: totalHeight)
    }

    private func generateContent(in geometry: GeometryProxy) -> some View {
        let state = FlexibleLayoutState()
        return ZStack(alignment: .topLeading) {
            ForEach(Array(data), id: \.self) { item in
                itemView(for: item, geometry: geometry, state: state)
            }
        }
        .background(viewHeightReader($totalHeight))
    }

    @ViewBuilder
    private func itemView(for item: Data.Element, geometry: GeometryProxy, state: FlexibleLayoutState) -> some View {
        content(item)
            .padding(.trailing, spacing)
            .alignmentGuide(.leading) { d in
                self.leadingGuide(d, item: item, geometry: geometry, state: state)
            }
            .alignmentGuide(.top) { d in
                self.topGuide(d, item: item, state: state)
            }
    }

    private func leadingGuide(
        _ d: ViewDimensions, item: Data.Element, geometry: GeometryProxy, state: FlexibleLayoutState
    ) -> CGFloat {
        if abs(state.width - d.width) > geometry.size.width {
            state.width = 0
            state.height -= d.height + spacing
        }
        let result = state.width
        if item == data.last {
            state.width = 0
        } else {
            state.width -= d.width + spacing
        }
        return result
    }

    private func topGuide(_ d: ViewDimensions, item: Data.Element, state: FlexibleLayoutState) -> CGFloat {
        let result = state.height
        if item == data.last {
            state.height = 0
        }
        return result
    }

    private func viewHeightReader(_ binding: Binding<CGFloat>) -> some View {
        GeometryReader { geo -> Color in
            DispatchQueue.main.async {
                binding.wrappedValue = geo.frame(in: .local).size.height
            }
            return .clear
        }
    }
}

private final class FlexibleLayoutState {
    var width: CGFloat = 0
    var height: CGFloat = 0
}

struct DisplayNote: Identifiable {
    var id: Int { note.wordIndex }
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
            // Custom designed, true multi-line editor
            TextEditor(text: $draftText)
                .font(.body)
                .frame(minHeight: 80) // 100% taller height
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
            
            // Save button only appears if there are unsaved changes
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
            if !isEditing { // Prevents overwriting what you are currently typing
                draftText = newVal ?? ""
            }
        }
    }
}

struct AnnotationEditorBox: View {
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
                        appState.services.saveAnnotation(lineIndex: lineIndex, wordIndex: wordIndex, text: text, marker: marker)
                        appState.refreshAnnotations()
                        isEditing = false
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
//                    .buttonStyle(.borderedProminent).controlSize(.small)
                }
                Button {
                    appState.services.saveAnnotation(lineIndex: lineIndex, wordIndex: wordIndex, text: "", marker: nil)
                    appState.refreshAnnotations()
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
//        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.3), lineWidth: 1))
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
//                .buttonStyle(.borderedProminent).controlSize(.small)
                
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
//        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.4), lineWidth: 1))
        .padding(.top, 8)
    }
}
