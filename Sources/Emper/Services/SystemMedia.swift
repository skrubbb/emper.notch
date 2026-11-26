import AppKit
import Foundation

/// Now-playing info from any app (browsers, other players) through macOS's MediaRemote framework.
/// macOS 27 refuses it inside Emper, so a tiny helper (`libEmperMR.dylib`, loaded by the system perl)
/// streams one JSON line per change and takes commands on stdin. Event-driven: idle cost is one
/// sleeping process. Also covers Spotify and Apple Music while direct control (AppleScript) is off.
@MainActor
final class SystemMedia {
    static let shared = SystemMedia()

    struct Info {
        let bundle: String
        let playing: Bool
        let title: String
        let artist: String
        let album: String
        let duration: Double
        let elapsed: Double
        let timestamp: Date?
        let artwork: Data?
    }

    var onInfo: (Info) -> Void = { _ in }
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()

    static var helperPath: String? {
        let p = Bundle.main.resourceURL?.appendingPathComponent("libEmperMR.dylib").path
        return p.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
    }

    var isRunning: Bool { process?.isRunning == true }

    func setActive(_ on: Bool) {
        if on, !isRunning { start() } else if !on, isRunning { stop() }
    }

    private func start() {
        guard let dylib = Self.helperPath else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = ["-e", #"use DynaLoader; my $l=DynaLoader::dl_load_file($ARGV[0],0) or die; my $s=DynaLoader::dl_find_symbol($l,"emper_mediaremote_stream") or die; my $x=DynaLoader::dl_install_xsub("main::s",$s); &$x;"#, dylib]
        let out = Pipe(), inp = Pipe()
        p.standardOutput = out
        p.standardInput = inp
        p.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { SystemMedia.shared.receive(d) } }
        }
        p.terminationHandler = { _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { SystemMedia.shared.ended() } }
        }
        do { try p.run() } catch { return }
        process = p
        input = inp.fileHandleForWriting
    }

    private func stop() {
        try? input?.close()   // EOF ends the helper
        input = nil
        process = nil
    }

    private func ended() {
        process = nil
        input = nil
        buffer.removeAll()
    }

    /// play, pause, toggle, next, previous, `seek <s>`, refresh.
    func send(_ cmd: String) {
        guard let input else { return }
        try? input.write(contentsOf: Data((cmd + "\n").utf8))
    }

    private func receive(_ d: Data) {
        buffer.append(d)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            if let info = Self.parse(Data(line)) { onInfo(info) }
        }
    }

    nonisolated static func parse(_ line: Data) -> Info? {
        guard let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return nil }
        let num = { (k: String) in (o[k] as? NSNumber)?.doubleValue ?? 0 }
        let parent = o["parent"] as? String ?? ""
        let bundle = parent.isEmpty ? (o["bundle"] as? String ?? "") : parent
        let ts = num("timestamp")
        let art = (o["artwork"] as? String).flatMap { $0.isEmpty ? nil : Data(base64Encoded: $0) }
        return Info(bundle: bundle, playing: num("playing") != 0,
                    title: o["title"] as? String ?? "", artist: o["artist"] as? String ?? "",
                    album: o["album"] as? String ?? "", duration: num("duration"), elapsed: num("elapsed"),
                    timestamp: ts > 0 ? Date(timeIntervalSince1970: ts) : nil, artwork: art)
    }
}
