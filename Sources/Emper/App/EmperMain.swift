import AppKit

@main
enum EmperMain {
    @MainActor private static var delegate: AppDelegate?

    @MainActor static func main() {
        let app = NSApplication.shared
        let d = AppDelegate(selfTest: CommandLine.arguments.contains("--selftest") || CommandLine.arguments.contains("--render") || CommandLine.arguments.contains("--bench") || CommandLine.arguments.contains("--zones"))
        delegate = d
        app.delegate = d
        app.setActivationPolicy(.accessory) // no Dock icon, lives in the menu bar
        app.run()
    }
}
