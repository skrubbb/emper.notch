import AppKit
import Combine
import EmperCore

/// A music app Emper can follow. Both post a distributed notification on every play/pause/track change
/// and are scriptable with AppleScript.
enum Player: String, CaseIterable {
    case spotify = "com.spotify.client"
    case music = "com.apple.Music"

    var bundleID: String { rawValue }
    var name: String { self == .spotify ? "Spotify" : "Apple Music" }
    var notification: Notification.Name {
        Notification.Name(self == .spotify ? "com.spotify.client.PlaybackStateChanged" : "com.apple.Music.playerInfo")
    }
    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
    /// AppleScript `duration` unit: Spotify milliseconds, Music seconds.
    var scriptDurationScale: Double { self == .spotify ? 1000 : 1 }
}

/// Shared "what's playing" state for Spotify and Apple Music. One instance for all islands.
/// The player that last started playing is the active one; controls go to it.
/// - Track/state: each app's distributed notification (no permission needed).
/// - Controls, artwork, position: macOS Now Playing by default (no permission); AppleScript only after the
///   person allows direct control (macOS then asks for Automation once per app).
/// - Lyrics (opt-in): lrclib.net.
/// Never launches a music app by itself.
@MainActor
final class NowPlaying: ObservableObject {
    static let shared = NowPlaying()

    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var album = ""
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: Double = 0
    @Published private(set) var artwork: NSImage?
    @Published private(set) var lyrics: [LyricLine] = []
    @Published private(set) var lyricsStatus = ""
    /// Index of the lyric line playing now (published only when it changes).
    @Published private(set) var lyricIndex: Int?
    @Published private(set) var player: Player = .spotify
    /// Bundle id of another app playing (browser, other player) via system detection; nil = Spotify/Music.
    @Published private(set) var systemSource: String?
    /// Round 23: badge left of the controls (Spotify / Apple Music / YouTube / the app's own icon).
    @Published private(set) var source: MediaSource = .none
    @Published var status = ""
    @Published var lyricsEnabled = false {
        didSet { if lyricsEnabled != oldValue { loadLyrics() } }
    }
    /// Show the current lyric line inside the idle live activity.
    @Published var idleLyrics = true
    /// Self-test: no AppleScript, no network.
    var offline = false
    /// AppleScript to Spotify / Music is allowed (Settings › Music). Off = no Automation prompt ever.
    var scriptingAllowed = false
    /// macOS Now Playing is running, so it also covers Spotify / Music while scripting is off.
    var systemAudioOn = false
    /// Spotify / Music come through macOS Now Playing instead of their own notifications + AppleScript.
    private var musicViaSystem: Bool { !scriptingAllowed && systemAudioOn }
    /// Spotify / Music played but macOS Now Playing never reported it (e.g. a macOS update broke it).
    @Published private(set) var systemMissedMusic = false
    /// Turns on Settings › Music › direct control (set by the island manager).
    static var enableAppControl: () -> Void = {}
    /// The Music tab shows an Allow button: Spotify / Music is around but only direct control would make
    /// it work (controls without Now Playing, or Now Playing missed it).
    var needsAppControl: Bool {
        guard !scriptingAllowed, !offline else { return false }
        if systemMissedMusic { return true }
        if hasTrack { return systemSource == nil }
        return !systemAudioOn && Player.allCases.contains { $0.isRunning }
    }

    private var position: Double = 0
    private var positionStamp = Date()
    private var trackKey = ""
    private var artworkTask: Task<Void, Never>?
    private var lyricsTask: Task<Void, Never>?
    private var resyncTimer: Timer?

    var hasTrack: Bool { !title.isEmpty }
    /// The idle live activity shows the current lyric line.
    var showsIdleLyrics: Bool { lyricsEnabled && idleLyrics && !lyrics.isEmpty }
    var currentLyric: String {
        guard let i = lyricIndex, lyrics.indices.contains(i) else { return "" }
        return lyrics[i].text
    }
    var currentPosition: Double {
        isPlaying ? position + Date().timeIntervalSince(positionStamp) : position
    }
    var isRunning: Bool { player.isRunning }
    /// Search (and AppleScript extras) only exist for Spotify and Apple Music.
    /// Name of the app playing now.
    var sourceName: String {
        guard let b = systemSource else { return player.name }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: b)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? b
    }

    private var lyricTimer: Timer?

    private init() {
        for p in Player.allCases {
            DistributedNotificationCenter.default().addObserver(forName: p.notification, object: nil, queue: .main) { [weak self] note in
                let info = note.userInfo ?? [:]
                MainActor.assumeIsolated { self?.apply(info, from: p) }
            }
        }
        // Lyrics need an accurate clock; resync the position every 10 s while it matters.
        resyncTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.lyricsEnabled, self.isPlaying, !self.offline else { return }
                self.resyncPosition()
            }
        }
        // Current lyric line, published only when it changes (drives the idle island's width).
        lyricTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickLyric() }
        }
    }

    private func tickLyric() {
        let i = lyrics.isEmpty ? nil : LRC.index(at: currentPosition + 0.25, in: lyrics)
        if i != lyricIndex { lyricIndex = i }
    }

    private func resyncPosition() {
        guard systemSource == nil else { SystemMedia.shared.send("refresh"); return }
        if let p = run("tell application id \"\(player.bundleID)\" to return player position"),
           let v = Double(p.replacingOccurrences(of: ",", with: ".")) {
            position = v
            positionStamp = Date()
        }
    }

    /// Spotify: Name, Artist, Album, Player State, Playback Position (s), Duration (ms).
    /// Music: Name, Artist, Album, Player State, Total Time (ms); no position, so it is asked for.
    private func apply(_ info: [AnyHashable: Any], from p: Player) {
        if musicViaSystem {
            // Check that Now Playing really follows it; if not, the Music tab offers direct control.
            if info["Player State"] as? String == "Playing" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, self.musicViaSystem, p.isRunning else { return }
                        if !self.hasTrack, !self.systemMissedMusic { self.systemMissedMusic = true }
                    }
                }
            }
            return
        }
        let state = info["Player State"] as? String ?? ""
        let playing = state == "Playing"
        // Another app pausing/stopping must not hide the one that is playing.
        if (p != player || systemSource != nil), !playing, isPlaying { return }
        if state == "Stopped" || (info["Name"] as? String ?? "").isEmpty {
            if p == player, systemSource == nil { clear() }
            return
        }
        player = p
        systemSource = nil
        let ms = (info[p == .spotify ? "Duration" : "Total Time"] as? Double) ?? 0
        update(title: info["Name"] as? String ?? "",
               artist: info["Artist"] as? String ?? "",
               album: info["Album"] as? String ?? "",
               playing: playing,
               position: (info["Playback Position"] as? Double) ?? 0,
               duration: ms / 1000,
               artworkURL: nil)
        if p == .music, !offline { resyncPosition() }
        refreshSource()
    }

    func update(title: String, artist: String, album: String, playing: Bool,
                position: Double, duration: Double, artworkURL: String?) {
        self.position = position
        positionStamp = Date()
        if isPlaying != playing { isPlaying = playing }
        if self.duration != duration { self.duration = duration }
        status = ""
        let key = "\(title)|\(artist)"
        guard key != trackKey else { return }
        trackKey = key
        self.title = title
        self.artist = artist
        self.album = album
        artwork = nil
        loadArtwork(url: artworkURL)
        loadLyrics()
    }

    /// System detection (any app). Spotify / Music lines are skipped: their own notifications cover them.
    /// The app that starts playing takes over; a paused or stopped app only updates itself.
    func applySystem(_ i: SystemMedia.Info) {
        guard !offline, !i.bundle.isEmpty, musicViaSystem || Player(rawValue: i.bundle) == nil else { return }
        let mine = systemSource == i.bundle
        if i.title.isEmpty {
            if mine { clear(); systemSource = nil }
            return
        }
        guard mine || i.playing || !hasTrack else { return }
        systemSource = i.bundle
        if systemMissedMusic, Player(rawValue: i.bundle) != nil { systemMissedMusic = false }
        let pos = i.elapsed + (i.playing ? (i.timestamp.map { Date().timeIntervalSince($0) } ?? 0) : 0)
        let changed = "\(i.title)|\(i.artist)" != trackKey
        update(title: i.title, artist: i.artist, album: i.album, playing: i.playing,
               position: pos, duration: i.duration, artworkURL: nil)
        if let d = i.artwork, let img = NSImage(data: d) { artwork = img } else if changed { artwork = nil }
        if changed || source == .none { refreshSource() }
    }

    /// Works out the badge once per track (not per tick).
    func refreshSource() {
        let s = MediaSource.detect(bundle: systemSource, nativeSpotify: player == .spotify, title: title)
        if s != source { source = s }
    }

    func clear() {
        trackKey = ""
        title = ""; artist = ""; album = ""
        isPlaying = false
        artwork = nil
        lyrics = []
        lyricIndex = nil
        lyricsStatus = ""
        source = .none
    }

    /// Self-test hook.
    func simulate(title: String, playing: Bool) {
        offline = true
        if title.isEmpty { clear() } else {
            update(title: title, artist: "Emper", album: "", playing: playing, position: 0, duration: 180, artworkURL: nil)
            if source == .none { source = .spotify }
        }
    }

    /// Self-test hook: pretend this source is playing.
    func simulateSource(_ s: MediaSource) { source = s }

    /// Self-test hook: pretend lrclib returned these lines.
    func simulateLyrics(_ lines: [LyricLine]) {
        lyrics = lines
        lyricsStatus = ""
        tickLyric()
    }

    // MARK: Controls

    /// "previous track", "playpause" and "next track" are the same in Spotify and Music.
    func command(_ cmd: String) {
        if systemSource != nil {
            let map = ["playpause": "toggle", "next track": "next", "previous track": "previous"]
            SystemMedia.shared.send(map[cmd] ?? cmd)
            return
        }
        guard scriptingAllowed else {
            status = "Turn on Spotify & Apple Music control in Settings › Music"
            return
        }
        guard isRunning else {
            let running = Player.allCases.first { $0.isRunning }
            guard let r = running else { status = "Open Spotify or Apple Music to play"; return }
            player = r
            return command(cmd)
        }
        run("tell application id \"\(player.bundleID)\" to \(cmd)")
    }

    /// Jump to `seconds` in the current track (Spotify and Music both take seconds).
    /// Bring the player app (Spotify / Apple Music) to the front.
    func openPlayer() {
        let id = systemSource ?? player.bundleID
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
            app.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func seek(to seconds: Double) {
        guard hasTrack, duration > 0 else { return }
        let t = min(max(seconds, 0), duration)
        if systemSource != nil { SystemMedia.shared.send("seek \(String(format: "%.2f", t))") }
        else { command("set player position to \(String(format: "%.2f", t))") }
        position = t
        positionStamp = Date()
        objectWillChange.send()
        tickLyric()
    }

    /// Pull current state once (e.g. at launch, before any notification arrived). A playing app wins
    /// over a paused one. Only asks apps that are already running (AppleScript would launch them).
    func refreshIfRunning() {
        guard !offline, scriptingAllowed else { return }
        var paused: (Player, [String])?
        for p in Player.allCases where p.isRunning {
            let script = """
            tell application id "\(p.bundleID)"
                if player state is stopped then return "stopped"
                set t to current track
                return (name of t) & tab & (artist of t) & tab & (album of t) & tab & (player state as string) & tab & (player position as string) & tab & ((duration of t) as string)
            end tell
            """
            guard let out = run(script, for: p) else { continue }
            let f = out.components(separatedBy: "\t")
            guard f.count == 6 else { continue }
            if f[3] == "playing" { return apply(fields: f, from: p) }
            if paused == nil { paused = (p, f) }
        }
        if let (p, f) = paused { apply(fields: f, from: p) }
    }

    private func apply(fields f: [String], from p: Player) {
        player = p
        let num = { (s: String) in Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        update(title: f[0], artist: f[1], album: f[2], playing: f[3] == "playing",
               position: num(f[4]), duration: num(f[5]) / p.scriptDurationScale, artworkURL: nil)
    }

    // MARK: Artwork & lyrics

    private func loadArtwork(url: String?) {
        artworkTask?.cancel()
        guard !offline, systemSource == nil else { return }
        let key = trackKey
        if player == .music {
            // Music has no artwork URL; the artwork's raw image data comes straight from AppleScript.
            guard isRunning, let d = descriptor("tell application id \"\(Player.music.bundleID)\" to get raw data of artwork 1 of current track")?.data,
                  let img = NSImage(data: d) else { return }
            artwork = img
            return
        }
        let urlString = url ?? (isRunning ? run("tell application id \"\(player.bundleID)\" to return artwork url of current track") : nil)
        // Artwork over HTTPS only (no plain-HTTP fetch of a URL reported by another app).
        guard let s = urlString, let u = URL(string: s), u.scheme?.lowercased() == "https" else { return }
        artworkTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: u), let img = NSImage(data: data) else { return }
            guard let self, self.trackKey == key else { return }
            self.artwork = img
        }
    }

    private func loadLyrics() {
        lyricsTask?.cancel()
        lyrics = []
        lyricsStatus = ""
        guard lyricsEnabled, hasTrack, !offline else { return }
        var comps = URLComponents(string: "https://lrclib.net/api/get")!
        comps.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album),
        ]
        if duration > 0 { comps.queryItems?.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
        guard let url = comps.url else { return }
        var req = URLRequest(url: url)
        req.setValue("Emper/0.1 (macOS)", forHTTPHeaderField: "User-Agent")
        lyricsStatus = "Loading lyrics…"
        let key = trackKey
        lyricsTask = Task { [weak self] in
            struct Response: Decodable { let syncedLyrics: String?; let plainLyrics: String? }
            let result = try? await URLSession.shared.data(for: req)
            guard let self, self.trackKey == key else { return }
            guard let (data, resp) = result, (resp as? HTTPURLResponse)?.statusCode == 200,
                  let r = try? JSONDecoder().decode(Response.self, from: data) else {
                self.lyricsStatus = "No lyrics found"
                return
            }
            let lines = LRC.parse(r.syncedLyrics ?? "")
            self.lyrics = lines
            self.lyricsStatus = lines.isEmpty ? (r.plainLyrics == nil ? "No lyrics found" : "No synced lyrics") : ""
        }
    }

    /// Apple Music: play a song from the person's library by title and artist. False when it isn't there.
    func playFromMusicLibrary(title: String, artist: String) -> Bool {
        func q(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
        let src = """
        tell application id "com.apple.Music"
            set hits to (every track of library playlist 1 whose name is "\(q(title))" and artist contains "\(q(artist))")
            if hits is {} then return "none"
            play item 1 of hits
            return "ok"
        end tell
        """
        return run(src, for: .music) == "ok"
    }

    // MARK: AppleScript

    @discardableResult
    private func run(_ source: String, for p: Player? = nil) -> String? {
        descriptor(source, for: p)?.stringValue
    }

    private func descriptor(_ source: String, for p: Player? = nil) -> NSAppleEventDescriptor? {
        // Never touch another app without the person's opt-in (this is what makes macOS ask).
        guard scriptingAllowed, !offline else { return nil }
        let p = p ?? player
        var err: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&err)
        if let err {
            let code = err[NSAppleScript.errorNumber] as? Int ?? 0
            status = code == -1743
                ? "Allow Emper to control \(p.name) in System Settings › Privacy & Security › Automation"
                : "Couldn't reach \(p.name) (\(code))"
            return nil
        }
        return result
    }
}
