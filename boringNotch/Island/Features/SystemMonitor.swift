//
//  SystemMonitor.swift
//  MacIsle
//
//  Lightweight CPU / memory / network sampler. Only runs while someone is looking.
//

import Combine
import Darwin
import Foundation

@MainActor
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()

    static let historyLength = 48

    @Published private(set) var cpu: Double = 0           // 0...1
    @Published private(set) var memoryUsed: Double = 0    // bytes
    @Published private(set) var memoryTotal: Double = Double(ProcessInfo.processInfo.physicalMemory)
    @Published private(set) var downBytesPerSec: Double = 0
    @Published private(set) var upBytesPerSec: Double = 0
    @Published private(set) var cpuHistory: [Double] = Array(repeating: 0, count: historyLength)
    @Published private(set) var downHistory: [Double] = Array(repeating: 0, count: historyLength)
    @Published private(set) var upHistory: [Double] = Array(repeating: 0, count: historyLength)

    var memoryFraction: Double { memoryTotal > 0 ? memoryUsed / memoryTotal : 0 }

    private var watchers = 0
    private var timer: AnyCancellable?
    private var lastCPU: host_cpu_load_info?
    private var lastNet: (rx: UInt64, tx: UInt64, at: Date)?

    func retain() {
        watchers += 1
        if watchers == 1 { startSampling() }
    }

    func release() {
        watchers = max(0, watchers - 1)
        if watchers == 0 { timer = nil }
    }

    private func startSampling() {
        sample()
        timer = Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in self?.sample() }
            }
    }

    private func sample() {
        sampleCPU()
        sampleMemory()
        sampleNetwork()
    }

    private func push(_ value: Double, into history: inout [Double]) {
        history.append(value)
        if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }
    }

    private func sampleCPU() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        defer { lastCPU = info }
        guard let last = lastCPU else { return }

        func delta(_ a: UInt32, _ b: UInt32) -> Double { Double(a &- b) }
        let user = delta(info.cpu_ticks.0, last.cpu_ticks.0)
        let system = delta(info.cpu_ticks.1, last.cpu_ticks.1)
        let idle = delta(info.cpu_ticks.2, last.cpu_ticks.2)
        let nice = delta(info.cpu_ticks.3, last.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else { return }
        cpu = (user + system + nice) / total
        push(cpu, into: &cpuHistory)
    }

    private func sampleMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let page = Double(vm_kernel_page_size)
        // "Memory used" as Activity Monitor shows it: app (internal - purgeable) + wired + compressed.
        let app = Double(stats.internal_page_count) - Double(stats.purgeable_count)
        let used = (app + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
        memoryUsed = max(0, used)
    }

    private func sampleNetwork() {
        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return }
        defer { freeifaddrs(ifaddr) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = cursor {
            let ifa = ptr.pointee
            if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
               (ifa.ifa_flags & UInt32(IFF_LOOPBACK)) == 0,
               (ifa.ifa_flags & UInt32(IFF_UP)) != 0,
               let data = ifa.ifa_data?.assumingMemoryBound(to: if_data.self) {
                let name = String(cString: ifa.ifa_name)
                // Physical interfaces only, so VPN tunnels are not double counted.
                if name.hasPrefix("en") || name.hasPrefix("pdp_ip") || name.hasPrefix("bridge") {
                    rx += UInt64(data.pointee.ifi_ibytes)
                    tx += UInt64(data.pointee.ifi_obytes)
                }
            }
            cursor = ifa.ifa_next
        }

        let now = Date.now
        defer { lastNet = (rx, tx, now) }
        guard let last = lastNet else { return }
        let dt = now.timeIntervalSince(last.at)
        guard dt > 0 else { return }
        // Counters are 32-bit per interface and can wrap; ignore negative deltas.
        downBytesPerSec = rx >= last.rx ? Double(rx - last.rx) / dt : downBytesPerSec
        upBytesPerSec = tx >= last.tx ? Double(tx - last.tx) / dt : upBytesPerSec
        push(downBytesPerSec, into: &downHistory)
        push(upBytesPerSec, into: &upHistory)
    }
}

extension Double {
    /// 1.2 MB/s, 830 KB/s
    var islandRate: String {
        let units = ["B", "KB", "MB", "GB"]
        var value = self
        var i = 0
        while value >= 1000, i < units.count - 1 {
            value /= 1000
            i += 1
        }
        let format = value >= 100 || i == 0 ? "%.0f %@/s" : "%.1f %@/s"
        return String(format: format, value, units[i])
    }

    var islandBytes: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .memory)
    }
}
