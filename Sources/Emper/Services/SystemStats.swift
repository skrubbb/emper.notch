import AppKit
import Darwin
import Foundation
import IOKit

/// CPU, memory and GPU load, sampled every 1.5 s only while a stats widget is on screen.
/// GPU comes from IOAccelerator's "Device Utilization %" (assumed present on this Mac; nil when missing).
@MainActor
final class SystemStats: ObservableObject {
    static let shared = SystemStats()

    @Published private(set) var cpu: Double = 0
    @Published private(set) var memory: Double = 0
    @Published private(set) var gpu: Double?
    @Published private(set) var memoryUsedGB: Double = 0
    /// Last `historyLength` samples (oldest first), recorded only while something is watching.
    @Published private(set) var history: [Sample] = []
    static let historyLength = 60

    struct Sample {
        let cpu: Double
        let memory: Double
        let gpu: Double?
    }

    private var users = 0
    private var timer: Timer?
    private var lastTicks: (busy: UInt64, total: UInt64)?

    /// Widgets call these on appear/disappear; sampling runs while at least one is visible.
    func retain() {
        users += 1
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
    }

    func release() {
        users = max(users - 1, 0)
        if users == 0 {
            timer?.invalidate()
            timer = nil
        }
    }

    var isSampling: Bool { timer != nil }

    func sample() {
        if let t = Self.cpuTicks() {
            if let l = lastTicks, t.total > l.total {
                cpu = Double(t.busy - l.busy) / Double(t.total - l.total)
            }
            lastTicks = t
        }
        if let m = Self.memoryUsed() {
            memoryUsedGB = m / 1_073_741_824
            memory = m / Double(ProcessInfo.processInfo.physicalMemory)
        }
        gpu = Self.gpuUtilization()
        history.append(Sample(cpu: cpu, memory: memory, gpu: gpu))
        if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }
    }

    static func openActivityMonitor() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"),
                                           configuration: NSWorkspace.OpenConfiguration())
    }

    private static func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)) }
        var busy: UInt64 = 0, total: UInt64 = 0
        for i in 0..<Int(count) {
            let b = i * Int(CPU_STATE_MAX)
            let user = UInt64(UInt32(bitPattern: info[b + Int(CPU_STATE_USER)]))
            let sys = UInt64(UInt32(bitPattern: info[b + Int(CPU_STATE_SYSTEM)]))
            let nice = UInt64(UInt32(bitPattern: info[b + Int(CPU_STATE_NICE)]))
            let idle = UInt64(UInt32(bitPattern: info[b + Int(CPU_STATE_IDLE)]))
            busy += user + sys + nice
            total += user + sys + nice + idle
        }
        return (busy, total)
    }

    /// Roughly Activity Monitor's "Memory Used": app memory + wired + compressed.
    private static func memoryUsed() -> Double? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard r == KERN_SUCCESS else { return nil }
        let page = Double(vm_kernel_page_size)
        let app = Double(stats.internal_page_count) - Double(stats.purgeable_count)
        return (max(app, 0) + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
    }

    private static func gpuUtilization() -> Double? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(it) }
        var best: Double?
        while case let s = IOIteratorNext(it), s != 0 {
            defer { IOObjectRelease(s) }
            guard let p = IORegistryEntryCreateCFProperty(s, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
                  let u = (p["Device Utilization %"] as? NSNumber)?.doubleValue else { continue }
            best = max(best ?? 0, u / 100)
        }
        return best
    }
}
