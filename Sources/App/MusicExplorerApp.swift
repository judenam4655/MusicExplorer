import SwiftUI
import CoreImage
import UniformTypeIdentifiers

@main
struct MusicExplorerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(appState.playback)
                .onAppear { appState.services.start() }
        }
    }
}

final class PlaybackState: ObservableObject {
    @Published var positionMs: Int = 0
    @Published var currentLineIndex: Int? = nil
    @Published var currentTranslationText: String = ""
}

/// Minimal ObservableObject bridge so SwiftUI can react to AppServices'
/// closures.
final class AppState: ObservableObject {
    let services = AppServices()
    let playback = PlaybackState() // part of optimziation

    @Published var syncedLines: [LyricLine]? = nil
//    @Published var currentLineIndex: Int? = nil

    @Published var trackTitle: String = "Nothing playing"
    @Published var artist: String = ""

    // Synced state
    @Published var currentLineText: String = "Searching lyrics..."
//    @Published var currentTranslationText: String = ""
    @Published var translatedLines: [LyricLine]? = nil

    // Plain state fallback
    @Published var plainLyricsText: String? = nil

//    @Published var positionMs: Int = 0

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
                    self?.playback.currentTranslationText = ""
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
                self.playback.positionMs = ms

                if self.plainLyricsText == nil {
                    let newIndex = self.services.currentLineIndex(atMs: ms)
                    if self.playback.currentLineIndex != newIndex {
                        self.playback.currentLineIndex = newIndex
                    }
                    let translation = self.services.currentTranslationLine(atMs: ms) ?? ""
                    if translation != self.playback.currentTranslationText {
                        self.playback.currentTranslationText = translation
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
