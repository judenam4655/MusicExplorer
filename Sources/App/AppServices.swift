import Foundation
 
final class AppServices {
    let db: SQLiteDB
    let tracker = PlaybackTrackerService()
    let lyricsRepo: LyricsRepository
    let trackStore: TrackStore
    let translationStore: TranslationStore
    let songInfoStore: SongInfoStore
    let historyStore: PlayHistoryStore
    let historyLogger: PlayHistoryLogger
    let customLyricsStore: CustomLyricsStore
    let annotationStore: LyricAnnotationStore
    let lyricNoteStore: LyricNoteStore
    let lineNoteStore: LineNoteStore
//    let artworkStore: ArtworkStore
 
    private(set) var currentTrack: Track?
    private(set) var currentLyricsState: LyricsFetchState = .notFound
    private(set) var currentLyrics: LyricsResult?
    
    private var cachedSyncedTimed: [LRCParser.TimedIndex] = []
    private var cachedTranslatedTimed: [LRCParser.TimedIndex] = []
 
    /// Fired once per track change, after lyrics/translation/notes are loaded.
    var onCurrentTrackUpdated: ((Track, LyricsFetchState, TranslationDocument?, SongInfoNote?) -> Void)?
    /// Fired ~4x/sec with the interpolated playback position.
    var onPositionTick: ((Int) -> Void)?
    var isPlaying: Bool { tracker.isPlaying }
 
    init() {
        db = SQLiteDB()
        trackStore = TrackStore(db: db)
        customLyricsStore = CustomLyricsStore(db: db)
//        artworkStore = ArtworkStore(db: db)
        annotationStore = LyricAnnotationStore(db: db)
        lyricNoteStore = LyricNoteStore(db: db)
        lyricsRepo = LyricsRepository(
            primaryProviders: [LRCLibProvider()],
            customStore: customLyricsStore,
            cache: LyricsCacheStore(db: db)
        )
        translationStore = TranslationStore(db: db)
        songInfoStore = SongInfoStore(db: db)
        historyStore = PlayHistoryStore(db: db)
        historyLogger = PlayHistoryLogger(store: historyStore)
        lineNoteStore = LineNoteStore(db: db)
 
        tracker.onTrackChanged = { [weak self] old, new in
            self?.historyLogger.trackChanged(from: old, to: new)
            self?.handleTrackChanged(new)
        }
        tracker.onPositionTick = { [weak self] positionMs in
            self?.historyLogger.positionUpdated(positionMs)
            self?.onPositionTick?(positionMs)
        }
    }
 
    func start() {
        tracker.start()
    }
 
    func seek(to positionMs: Int) {
        tracker.seek(to: positionMs)
    }
 
    func togglePlayPause() {
        tracker.togglePlayPause()
    }
 
    private func handleTrackChanged(_ track: Track) {
        let _ = print("trackId: " + track.id)
        
        currentTrack = track
        trackStore.upsert(track)

        // TEMPORARY -- see AutoOfflineSongInfoSaver.swift. Delete this one
        // line (and that file) once the backfill is done.
        AutoOfflineSongInfoSaver.shared.handle(track: track, services: self)
 
        Task {
            let state = await lyricsRepo.lyrics(for: track)
            await MainActor.run {
                self.currentLyricsState = state
                if case .success(let result) = state {
                    self.currentLyrics = result
                    self.cachedSyncedTimed = LRCParser.timedIndices(for: result.synced ?? [])
                    self.cachedTranslatedTimed = LRCParser.timedIndices(for: result.translatedSynced ?? [])
                } else {
                    self.currentLyrics = nil
                    self.cachedSyncedTimed = []
                    self.cachedTranslatedTimed = []
                }

                let translation = self.translationStore.get(trackId: track.id)
                let note = self.songInfoStore.get(trackId: track.id)
//                let lineNotes = self.lineNoteStore.all(trackId: track.id)
                self.onCurrentTrackUpdated?(track, state, translation, note)
            }
        }
    }
 
    /// Index into currentLyrics.synced for whatever position the caller has
    /// (typically straight from onPositionTick).
    func currentLineIndex(atMs positionMs: Int) -> Int? {
        LRCParser.currentLineIndex(in: cachedSyncedTimed, atMs: positionMs)
    }

    func currentTranslationLine(atMs positionMs: Int) -> String? {
        guard let translated = currentLyrics?.translatedSynced else { return nil }
        guard let idx = LRCParser.currentLineIndex(in: cachedTranslatedTimed, atMs: positionMs) else { return nil }
        return translated[idx].text
    }
 
    // Convenience passthroughs for manual-entry tabs.
    func saveTranslation(_ text: String) {
        guard let id = currentTrack?.id else { return }
        translationStore.save(trackId: id, rawText: text)
    }
 
    func saveSongInfo(_ link: String?, _ text: String, _ documentID: String?) {
        guard let id = currentTrack?.id else { return }
        songInfoStore.save(trackId: id, source: link, content: text, documentID: documentID)
    }
    
    func saveSongInfo(_ text: String) {
        guard let id = currentTrack?.id else { return }
        songInfoStore.save(trackId: id, source: nil, content: text, documentID: nil)
    }
    
    func saveSongInfoSource(_ source: String?) {
        guard let id = currentTrack?.id else { return }
        songInfoStore.saveSource(trackId: id, source: source ?? "")
    }
 
    func saveSongInfoOfflineCopy(content: String, documentID: String) {
        guard let id = currentTrack?.id else { return }
        songInfoStore.saveOfflineCopy(trackId: id, content: content, documentID: documentID)
    }
    
    func saveCustomOriginal(lrcText: String, reloadUI: Bool = true) {
        guard let id = currentTrack?.id else { return }
        customLyricsStore.saveOriginal(trackId: id, lrcText: lrcText)
        if reloadUI, let current = currentTrack {
            handleTrackChanged(current)
        }
    }
 
    func saveCustomTranslation(lrcText: String, reloadUI: Bool = true) {
        guard let id = currentTrack?.id else { return }
        customLyricsStore.saveTranslation(trackId: id, lrcText: lrcText)
        if reloadUI, let current = currentTrack {
            handleTrackChanged(current)
        }
    }
 
    // MARK: - Lyrics notes / annotations
 
    func annotationsByLine(for trackId: String? = nil) -> [Int: [LyricAnnotation]] {
        guard let id = trackId ?? currentTrack?.id else { return [:] }
        return annotationStore.grouped(trackId: id)
    }
    
    @discardableResult
    func saveAnnotation(id: Int64? = nil, lineIndex: Int, wordIndex: Int, text: String, marker: String?) -> Int64? {
        guard let trackId = currentTrack?.id else { return nil }
        return annotationStore.save(trackId: trackId, lineIndex: lineIndex, wordIndex: wordIndex, noteText: text, marker: marker ?? "1", id: id)
    }
 
    func deleteAnnotation(id: Int64) {
        annotationStore.delete(id: id)
    }
 
    func lineNotes(for trackId: String) -> [Int: String] {
        lineNoteStore.all(trackId: trackId)
    }
 
    func saveLineNote(lineIndex: Int, text: String) {
        guard let id = currentTrack?.id else { return }
        lineNoteStore.save(trackId: id, lineIndex: lineIndex, text: text)
    }
 
    func getLyricNote(trackId: String) -> String {
        lyricNoteStore.get(trackId: trackId) ?? ""
    }
 
    func saveLyricNote(_ text: String) {
        guard let id = currentTrack?.id else { return }
        lyricNoteStore.save(trackId: id, content: text)
    }
}
