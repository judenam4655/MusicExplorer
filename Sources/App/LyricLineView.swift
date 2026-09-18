//
//  LyricLineView.swift
//  MusicExplorer
//
//  Created by Juhyeon Nam on 9/8/26.
//

import SwiftUI

struct LyricLineView: View {
    let originalText: String
    let translationText: String?
    let lineIndex: Int
    let annotations: [LyricAnnotation]
    let lineNote: String?
    let isCurrent: Bool
    let action: () -> Void

    @AppStorage("lyricSize") var lyricSize: Double = 32
    @AppStorage("transSize") var transSize: Double = 28
    @AppStorage("annotationSize") var annotationSize: Double = 24
    @AppStorage("noteSize") var noteSize: Double = 14
    @AppStorage("lyricAlign") var align: TextAlignmentChoice = .center
    @AppStorage("showTranslation") var showTranslation: Bool = true
    @AppStorage("showAnnotations") var showAnnotations: Bool = false

    @State private var isHovered = false
    @State private var isNoteExpanded = false

    private var displayNotes: [(tag: String, note: LyricAnnotation)] {
        var results: [(tag: String, note: LyricAnnotation)] = []
        var counter = 1
        let sorted = annotations.sorted { a, b in
            if a.wordIndex != b.wordIndex { return a.wordIndex < b.wordIndex }
            return (a.id ?? 0) < (b.id ?? 0)
        }
        for note in sorted {
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

    // Anchor for the current/non-current scale animation, matched to the
    // chosen text alignment so lines scale from the edge they're pinned to
    // rather than visibly shifting sideways.
    private var scaleAnchor: UnitPoint {
        switch align {
        case .left: return .leading
        case .right: return .trailing
        case .center: return .center
        }
    }

    // Horizontal alignment for the VStacks inside mainLyricContent. Without this,
    // those VStacks default to .center, which centers the translation/annotation
    // lines relative to the (usually differently-sized) original lyric line instead
    // of flushing everything to the same left/right edge as the rest of the row.
    private var contentAlignment: HorizontalAlignment {
        switch align {
        case .left: return .leading
        case .right: return .trailing
        case .center: return .center
        }
    }

    // Non-current lines are slightly smaller. Using a constant font size +
    // scaleEffect (instead of literally changing the font size/weight)
    // keeps each row's layout height constant, so the ScrollView doesn't
    // have to reflow mid-scroll -- that reflow was what made the jump
    // between lines look janky. Scale is fully animatable; Font is not.
    private let inactiveScale: CGFloat = 0.82

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
                }
            }
            .frame(maxWidth: .infinity, alignment: align == .left ? .leading : (align == .right ? .trailing : .center))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            action()
        }
    }

    @ViewBuilder
    private var mainLyricContent: some View {
        VStack(alignment: contentAlignment, spacing: 6) {
            if originalText.isEmpty {
                Text("♪")
                    .font(.system(size: lyricSize, weight: .black))
                    .foregroundStyle(isCurrent ? Color.primary : Color.primary.opacity(0.3))
                    .padding(.bottom, 5)
//                    .scaleEffect(isCurrent ? 1.0 : inactiveScale, anchor: scaleAnchor)
            } else if showAnnotations && !annotations.isEmpty {
                let groups = lyricLetterGroups(for: originalText)
                HStack(spacing: 4) {
                    ForEach(Array(groups.indices), id: \.self) { g in
                        HStack(spacing: 0) {
                            ForEach(groups[g]) { letter in
                                HStack(spacing: 0) {
                                    Text(String(letter.char))
                                    ForEach(displayNotes.filter { $0.note.wordIndex == letter.id }, id: \.note.id) { item in
                                        Text(item.tag)
                                            .font(.system(size: annotationSize, weight: .bold))
                                            .baselineOffset(20)
                                            .foregroundStyle(isCurrent ? Color.primary : Color.primary.opacity(0.3))
                                    }
                                }
                            }
                        }
                    }
                }
                .font(.system(size: lyricSize, weight: .heavy))
                .foregroundStyle(isCurrent ? Color.primary : Color.primary.opacity(0.3))
                .underline(isHovered)
                .padding(.bottom, 8)
//                .scaleEffect(isCurrent ? 1.0 : inactiveScale, anchor: scaleAnchor)
            } else {
                Text(originalText)
                    .font(.system(size: lyricSize, weight: .heavy))
                    .foregroundStyle(isCurrent ? Color.primary : Color.primary.opacity(0.3))
                    .underline(isHovered)
                    .padding(.bottom, 8)
//                    .scaleEffect(isCurrent ? 1.0 : inactiveScale, anchor: scaleAnchor)
            }

            if showTranslation, let trans = translationText, !trans.isEmpty {
                Text(trans)
                    .font(.system(size: transSize, weight: .bold))
                    .foregroundStyle(isCurrent ? Color.primary : Color.primary.opacity(0.3))
                    .underline(isHovered)
                    .padding(.bottom, 8)
//                    .scaleEffect(isCurrent ? 1.0 : inactiveScale, anchor: scaleAnchor)
            }

            if showAnnotations && !displayNotes.isEmpty {
                VStack(alignment: contentAlignment, spacing: 2) {
                    ForEach(displayNotes, id: \.note.id) { item in
                        Text("\(item.tag): \(item.note.noteText)")
                            .font(.system(size: annotationSize*0.8, weight: .medium))
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
                    .lineLimit(isNoteExpanded ? nil : 6)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                
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
            .frame(minHeight: 120, alignment: .topLeading)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
    }
}
