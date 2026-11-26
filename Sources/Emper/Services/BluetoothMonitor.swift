import Foundation
import IOBluetooth

/// Bluetooth connect events for the toast. Connection notifications come from IOBluetooth (no polling);
/// the battery level and device kind are read once per connect from `system_profiler`, which only
/// reports a battery for some devices (Apple accessories: assumed, unverified here).
@MainActor
final class BluetoothMonitor: NSObject {
    static let shared = BluetoothMonitor()

    struct Event {
        let name: String
        let symbol: String
        let battery: Double?
    }

    var onConnect: (Event) -> Void = { _ in }
    private var connectNote: IOBluetoothUserNotification?
    private var disconnectNotes: [IOBluetoothUserNotification] = []
    private var started = Date.distantFuture
    private var active = false

    func setActive(_ on: Bool) {
        guard on != active else { return }
        active = on
        if on {
            started = Date()
            connectNote = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connected(_:device:)))
        } else {
            connectNote?.unregister()
            connectNote = nil
        }
    }

    @objc private func connected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        // The register call reports every device that is already connected: skip that first burst.
        guard Date().timeIntervalSince(started) > 2 else { return }
        let name = device.name ?? "Bluetooth device"
        let address = device.addressString ?? ""
        Task.detached(priority: .utility) {
            let info = Self.profile(address: address, name: name)
            await MainActor.run {
                BluetoothMonitor.shared.onConnect(Event(name: name, symbol: Self.symbol(info.kind), battery: info.battery))
            }
        }
    }

    nonisolated static func symbol(_ kind: String?) -> String {
        switch kind?.lowercased() ?? "" {
        case let k where k.contains("headset") || k.contains("headphone"): "headphones"
        case let k where k.contains("speaker"): "hifispeaker.fill"
        case let k where k.contains("keyboard"): "keyboard"
        case let k where k.contains("mouse"): "computermouse.fill"
        case let k where k.contains("trackpad"): "rectangle.and.hand.point.up.left.fill"
        case let k where k.contains("gamepad") || k.contains("game"): "gamecontroller.fill"
        default: "wave.3.right"
        }
    }

    /// Device kind and battery (lowest of main/left/right; case ignored) from system_profiler.
    nonisolated static func profile(address: String, name: String) -> (kind: String?, battery: Double?) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["SPBluetoothDataType", "-json"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return (nil, nil) }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return parse(data, address: address, name: name)
    }

    nonisolated static func parse(_ data: Data, address: String, name: String) -> (kind: String?, battery: Double?) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bt = (root["SPBluetoothDataType"] as? [[String: Any]])?.first,
              let connected = bt["device_connected"] as? [[String: Any]] else { return (nil, nil) }
        let norm = { (s: String) in s.lowercased().replacingOccurrences(of: "-", with: ":") }
        for entry in connected {
            for (n, v) in entry {
                guard let d = v as? [String: Any] else { continue }
                let addr = (d["device_address"] as? String).map(norm) ?? ""
                guard addr == norm(address) || n == name else { continue }
                let levels = ["device_batteryLevelMain", "device_batteryLevelLeft", "device_batteryLevelRight", "device_batteryLevel"]
                    .compactMap { d[$0] as? String }
                    .compactMap { Double($0.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) }
                return (d["device_minorType"] as? String, levels.min().map { $0 / 100 })
            }
        }
        return (nil, nil)
    }
}
