//
//  ContentView.swift
//  MusicExplorer
//
//  Created by Juhyeon Nam on 9/8/26.
//

import SwiftUI

enum TextAlignmentChoice: String, CaseIterable {
    case left, center, right
    var alignment: TextAlignment {
        switch self { case .left: return .leading; case .center: return .center; case .right: return .trailing }
    }
}

struct SettingsMenu: View {
    @AppStorage("titleSize") var titleSize: Double = 40
    @AppStorage("artistSize") var artistSize: Double = 24
    @AppStorage("lyricSize") var lyricSize: Double = 32
    @AppStorage("transSize") var transSize: Double = 28
    @AppStorage("annotationSize") var annotationSize: Double = 20
    @AppStorage("noteSize") var noteSize: Double = 14
    @AppStorage("lyricAlign") var align: TextAlignmentChoice = .center
    @AppStorage("lyricsEdgeGap") var edgeGap: Double = 40
    
    var body: some View {
        Form {
            Picker("Alignment", selection: $align) {
                ForEach(TextAlignmentChoice.allCases, id: \.self) { choice in
                    Text(choice.rawValue.capitalized).tag(choice)
                }
            }
            Slider(value: $titleSize, in: 16...70) { Text("Title Size") }
            Slider(value: $artistSize, in: 12...50) { Text("Artist Size") }
            Slider(value: $lyricSize, in: 16...70) { Text("Lyrics Size") }
            Slider(value: $transSize, in: 10...50) { Text("Translation Size") }
            
            Divider().padding(.vertical, 4)
            
            Slider(value: $annotationSize, in: 8...40) { Text("Annotation Size") }
            Slider(value: $noteSize, in: 8...24) { Text("Line Note Size") }
            
            Divider().padding(.vertical, 4)
            
            Slider(value: $edgeGap, in: 0...1000) { Text("Edge Gap") }
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
                SidebarButton(icon: "note.text", isActive: activePanels.contains(.notes)) { toggle(.notes) }
                    .help("Lyrics Notes")

                Divider().padding(.horizontal, 8)

                SidebarButton(icon: "captions.bubble", isActive: showTranslation) {
                    showTranslation.toggle()
                }
                .help("Toggle Translations")

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
                let secondaryMaxWidth: CGFloat = activePanels.contains(.lyrics) ? geometry.size.width * 0.6 : .infinity

                HSplitView {

                    if activePanels.contains(.lyrics) {
                        LyricsMainView()
                            .frame(minWidth: geometry.size.width * 0.3, maxWidth: .infinity)
                    }

                    if activePanels.contains(.info) {
                        SongInfoEditorView()
                            .frame(minWidth: 260, idealWidth: geometry.size.width * 0.4, maxWidth: secondaryMaxWidth)
                    }

                    if activePanels.contains(.history) {
                        Text("Play History")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .frame(minWidth: 260, idealWidth: geometry.size.width * 0.4, maxWidth: secondaryMaxWidth)
                    }

                    if activePanels.contains(.sync) {
                        CustomSyncView()
                            .frame(minWidth: 260, idealWidth: geometry.size.width * 0.4, maxWidth: secondaryMaxWidth)
                    }

                    if activePanels.contains(.notes) {
                        LyricsNoteEditorView()
                            .frame(minWidth: 320, idealWidth: geometry.size.width * 0.4, maxWidth: secondaryMaxWidth)
                    }

                }
            }
        }
        .frame(minWidth: effectiveMinWidth, minHeight: effectiveMinHeight)
        .onPreferenceChange(NotesIdealSizeKey.self) { notesIdealSize = $0 }
    }

    // MARK: - Dynamic window minimum size
    @State private var notesIdealSize: CGSize = .zero
    private let baseMinWidth: CGFloat = 800
    private let baseMinHeight: CGFloat = 500
    private let sidebarChromeWidth: CGFloat = 100   // sidebar (60) + dividers/padding
    private let toolbarChromeHeight: CGFloat = 120  // notes page header + outer padding

    private var effectiveMinWidth: CGFloat {
        guard activePanels.contains(.notes), notesIdealSize.width > 0 else { return baseMinWidth }
        return max(baseMinWidth, notesIdealSize.width + sidebarChromeWidth)
    }

    private var effectiveMinHeight: CGFloat {
        guard activePanels.contains(.notes), notesIdealSize.height > 0 else { return baseMinHeight }
        return max(baseMinHeight, notesIdealSize.height + toolbarChromeHeight)
    }

    private func toggle(_ panel: AppPanel) {
        if activePanels.contains(panel) {
            if activePanels.count > 1 { activePanels.remove(panel) } // Prevents closing the last panel
        } else {
            activePanels.insert(panel)
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
