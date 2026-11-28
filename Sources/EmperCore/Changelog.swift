/// What changed in each release, newest first, shown in Settings › About (0.1.3).
/// Only the last `keep` releases ship, so someone who skipped a few updates in a busy week still sees them.
public enum Changelog {
    public struct Release: Equatable, Sendable {
        public let version: String
        public let date: String
        public let changes: [String]
    }

    public static let keep = 5

    public static let all: [Release] = [
        Release(version: "0.1.3", date: "2026-11-28", changes: [
            "Lighter while music plays: the animated equalizer is now a plain play/pause button, so macOS no longer redraws the Emper on every frame.",
            "The ✕ beside the music controls stays in place and is dimmed until the track is paused, so play and pause never move.",
            "Music in a side placeholder shows the player logo, artist and ✕ at every size; larger sizes add lyrics and the progress bar with times.",
            "New music layouts for placeholders on left and right Empers, including a tall one with large artwork.",
            "The Spotify or Apple Music logo shows right away when Emper opens with a track already playing.",
            "One Players menu replaces the separate music-detection toggle, and its caption says which choices need Automation permission.",
            "Hitbox Width and Depth rows show the size of the area they cover.",
            "Permissions can be allowed straight from Settings: macOS shows its own prompt, no searching in System Settings.",
            "About shows this changelog and a shorter update status.",
        ]),
        Release(version: "0.1.2", date: "2026-11-27", changes: [
            "Shrink button next to the pencil: turns an Emper into a thin line for full-screen apps.",
            "✕ on a paused track hides it until that app plays again.",
            "Fixed an old Spotify song staying on the Emper when another app took over Now Playing.",
            "The Now Playing helper restarts on its own if it stops.",
            "Spotify covers load even when the player doesn't provide one.",
        ]),
        Release(version: "0.1.1", date: "2026-11-26", changes: [
            "First public release of Emper.",
        ]),
    ]

    /// The newest `keep` releases.
    public static var recent: [Release] { Array(all.prefix(keep)) }
}
