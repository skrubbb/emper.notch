/// Which app is playing, for the small badge left of the music controls (round 23). Round 24: no
/// YouTube detection (it needed Screen Recording); a browser shows its own app icon.
public enum MediaSource: Equatable, Sendable {
    case spotify
    case appleMusic
    /// Any other app (a browser, another player): shown with its own app icon.
    case app(String)
    case none

    public static func detect(bundle: String?, nativeSpotify: Bool, title: String) -> MediaSource {
        guard let b = bundle else { return title.isEmpty ? .none : (nativeSpotify ? .spotify : .appleMusic) }
        if b == "com.spotify.client" { return .spotify }
        if b == "com.apple.Music" { return .appleMusic }
        return .app(b)
    }
}
