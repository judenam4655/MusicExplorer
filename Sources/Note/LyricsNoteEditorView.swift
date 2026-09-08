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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func lineBlock(index: Int, line: LyricLine) -> some View {
        let groups = lyricLetterGroups(for: line.text)
        let lineAnnotations = appState.annotationsByLine[index] ?? []
        // Paired by position, not by timeMs -- timeMs is nil for custom
        // untimed lines, and matching on nil == nil would wrongly pin every
        // untimed line to the first untimed translation ("recurring").
        let translated = appState.translatedLines
        let translation = (translated != nil && index < translated!.count) ? translated![index].text : nil

        var displayNotes: [DisplayNote] = []
        var counter = 1
        // Ties (several annotations on the same letter) ordered by id, i.e.
        // roughly creation order.
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

        // Negative indices are "general" line annotations added via the "+"
        // button (not tied to a letter), so they get a neutral label instead
        // of looking up a nonexistent character.
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

                // 1. EXIST BY DEFAULT: Editors for every saved annotation on
                // this line -- a letter can have more than one now, plus any
                // free-standing "general" annotations for this line.
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
                
                // 2. NEW ANNOTATION: Appears when a letter is clicked -- its
                // first annotation, or one more on top of existing ones --
                // or after tapping "Add annotation" below.
                if let editing = editingWord, editing.lineIndex == index {
                    NewAnnotationEditorBox(lineIndex: index, wordIndex: editing.wordIndex, word: label(for: editing.wordIndex)) {
                        editingWord = nil
                    }
                }

                // A line isn't limited to one annotation per letter -- this
                // opens another editor that isn't pinned to any letter,
                // using a synthetic negative index so it can't collide with
                // a real character position (which are always >= 0).
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
            .frame(maxWidth: .infinity, alignment: .topLeading)

            // RIGHT COLUMN: Per-line Note Text Box
            VStack(alignment: .leading, spacing: 4) {
//                Text("Line Note").font(.caption2).foregroundStyle(.secondary)
                LineNoteEditorBox(lineIndex: index).padding(.top, 40)
            }
            .frame(width: 260)
        }
    }

    // A `Button` per letter (hundreds per screen now that annotation is
    // letter-level) carries focus/hover/accessibility overhead that adds up.
    // A plain tappable `Text` does the same job for a fraction of the cost.
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
            // A letter can carry more than one annotation, so this always
            // opens (or, if already open on this exact letter, closes)
            // another "new annotation" editor -- it never refuses just
            // because the letter already has one.
            if editingWord?.lineIndex == lineIndex && editingWord?.wordIndex == charIndex {
                editingWord = nil
            } else {
                editingWord = (lineIndex, charIndex)
            }
        }
    }
}

/// A single annotatable unit for the letter-level annotation UI: `id` is
/// that character's index within the *full* line string, so it stays a
/// stable, unique key even though letters are grouped visually by word.
/// Not `private` -- `LyricLineView` in MusicExplorerApp.swift uses the same
/// grouping so its inline superscripts line up with what you tagged here.
struct LyricLetter: Identifiable {
    let id: Int
    let char: Character
}

/// Splits `text` into per-word groups of `LyricLetter`s (spaces separate
/// groups but aren't themselves annotatable) while preserving each letter's
/// global character index.
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

/// Wrapping container for word groups (and, elsewhere, annotation-marker
/// rows). Replaces the old `WrapHStack`/`FlexibleView`, which measured every
/// item through a `GeometryReader` plus O(n) `alignmentGuide` callbacks --
/// fine for a handful of words, but once annotations went letter-level
/// (hundreds of tap targets per screen) that approach was doing real,
/// visible work on every layout pass and was a chunk of the lag. SwiftUI's
/// `Layout` protocol does the same wrapping in one measurement pass with no
/// extra state or reflow, and needs no GeometryReader at all.
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
            // Custom designed, true multi-line editor
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
//                    .buttonStyle(.borderedProminent).controlSize(.small)
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
