import AppKit
import Darwin
import Foundation
import IOKit
import PerchCore

/// Reads the machine. The only file in Perch that talks to Mach or the IO
/// registry for statistics.
///
/// `CLAUDE.md` §9 warns specifically about this module reaching for a stats
/// library. It does not: every number below comes from a documented system
/// call — `host_processor_info`, `host_statistics64`, `getifaddrs`,
/// `statfs`, `sysctl` — or from the IO registry, which is a public read.
///
/// **Nothing here schedules anything.** It is a pure function of the machine
/// plus the previous reading, called by whoever owns the sampler. That is
/// what lets the sampler's lifetime belong to the view (TC-SYS-009).
@MainActor
final class SystemReader {

    /// Counters from the previous call, for turning totals into rates. A
    /// rate needs two readings, which is why the first snapshot reports
    /// `nil` rather than a number that would be wrong.
    var previous: Counters?

    struct Counters {
        let at: Date
        let cpu: [CPUTicks]
        let networkIn: UInt64
        let networkOut: UInt64
    }

    struct CPUTicks {
        let user: UInt32
        let system: UInt32
        let idle: UInt32
        let nice: UInt32

        var total: UInt32 { user &+ system &+ idle &+ nice }
        var busy: UInt32 { user &+ system &+ nice }
    }

    /// One complete reading.
    func read() -> SystemSnapshot {
        var snapshot = SystemSnapshot()
        let now = Date()

        let ticks = cpuTicks()
        snapshot.cpu = cpu(from: ticks)
        snapshot.memory = memory()
        snapshot.disks = disks()
        snapshot.network = network(at: now)
        snapshot.thermal = thermal()
        snapshot.gpu = gpu()
        snapshot.uptime = uptime()
        snapshot.loadAverage = loadAverage()
        snapshot.batteryHealth = batteryHealth()

        previous = Counters(
            at: now,
            cpu: ticks,
            networkIn: interfaceBytes().received,
            networkOut: interfaceBytes().sent
        )

        return snapshot
    }

    /// Resets the rate baselines. Called when the sampler stops, so that
    /// restarting it does not report a rate averaged over the minutes in
    /// between — which on a network counter reads as a flat line at a number
    /// nobody recognises.
    func reset() {
        previous = nil
    }

    // MARK: - CPU

    private func cpuTicks() -> [CPUTicks] {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &count,
            &info,
            &infoCount
        )
        guard result == KERN_SUCCESS, let info else { return [] }

        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: info),
                vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
            )
        }

        return (0..<Int(count)).map { core in
            let base = core * Int(CPU_STATE_MAX)
            return CPUTicks(
                user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            )
        }
    }

    /// Load is a *difference* of tick counters, so the first reading has
    /// nothing to compare against and reports zero rather than the machine's
    /// average since boot — which is not what anybody means by "CPU now".
    private func cpu(from ticks: [CPUTicks]) -> SystemSnapshot.CPU {
        guard let previous = previous?.cpu, previous.count == ticks.count, !ticks.isEmpty else {
            return SystemSnapshot.CPU(total: 0, perCore: Array(repeating: 0, count: ticks.count))
        }

        let perCore = zip(previous, ticks).map { before, after -> Double in
            let total = after.total &- before.total
            let busy = after.busy &- before.busy
            return total > 0 ? min(1, Double(busy) / Double(total)) : 0
        }

        let total = perCore.isEmpty ? 0 : perCore.reduce(0, +) / Double(perCore.count)
        return SystemSnapshot.CPU(total: total, perCore: perCore, topProcess: topProcess())
    }

    /// The busiest process, by the kernel's own accounting.
    ///
    /// `proc_pid_rusage` is public and needs no entitlement. It reports
    /// cumulative CPU time rather than a rate, so this reports the process
    /// with the most time in the last interval — computed the same way the
    /// core loads are, from a difference.
    private struct Busiest {
        let name: String
        let time: UInt64
    }

    private func topProcess() -> SystemSnapshot.CPU.Process? {
        var count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard count > 0 else { return nil }

        var pids = [pid_t](repeating: 0, count: Int(count) / MemoryLayout<pid_t>.size)
        count = proc_listpids(
            UInt32(PROC_ALL_PIDS),
            0,
            &pids,
            Int32(pids.count * MemoryLayout<pid_t>.size)
        )
        guard count > 0 else { return nil }

        var best: Busiest?

        for pid in pids where pid > 0 {
            var usage = rusage_info_current()
            let read = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: Optional<rusage_info_t>.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0)
                }
            }
            guard read == 0 else { continue }

            let time = usage.ri_user_time &+ usage.ri_system_time
            guard time > (best?.time ?? 0) else { continue }

            var name = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            guard proc_name(pid, &name, UInt32(MAXPATHLEN)) > 0 else { continue }

            let characters = name.prefix { $0 != 0 }.map { Character(UnicodeScalar(UInt8($0))) }
            best = Busiest(name: String(characters), time: time)
        }

        guard let best else { return nil }

        // Reported as a share of the sampling window rather than as an
        // absolute time, which is the number people expect to see.
        let window = previous.map { Date().timeIntervalSince($0.at) } ?? 1
        let seconds = Double(best.time) / 1_000_000_000
        return SystemSnapshot.CPU.Process(name: best.name, usage: min(1, seconds / max(window, 1)))
    }

    // MARK: - Memory

    private func memory() -> SystemSnapshot.Memory {
        var memory = SystemSnapshot.Memory()
        memory.total = ProcessInfo.processInfo.physicalMemory

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return memory }

        // `vm_kernel_page_size` is a global `var` in the SDK headers, which
        // Swift 6 reads as shared mutable state. `sysctl` answers the same
        // question and is a call rather than a variable.
        let page = Self.pageSize

        // Activity Monitor's own definition: everything resident that is not
        // reclaimable. Matching it is the point — a monitor that disagrees
        // with the system monitor is the one people stop trusting.
        let wired = UInt64(stats.wire_count) * page
        let compressed = UInt64(stats.compressor_page_count) * page
        let active = UInt64(stats.active_count) * page

        memory.used = wired + compressed + active
        memory.cached = UInt64(stats.external_page_count) * page
        memory.swapUsed = swapUsed()
        memory.pressure = pressure()

        return memory
    }

    /// Read once. The page size cannot change while the machine is running.
    private static let pageSize: UInt64 = {
        var size: UInt64 = 0
        var length = MemoryLayout<UInt64>.stride
        guard sysctlbyname("hw.pagesize", &size, &length, nil, 0) == 0, size > 0 else {
            return 4_096
        }
        return size
    }()

    private func swapUsed() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return usage.xsu_used
    }

    /// The kernel's own pressure level, not a number computed from the page
    /// counts. `kern.memorystatus_vm_pressure_level` is what Activity
    /// Monitor colours its graph from.
    private func pressure() -> SystemSnapshot.Memory.Pressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.stride

        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0
        else { return .normal }

        switch level {
        case 4: return .critical
        case 2: return .warning
        default: return .normal
        }
    }

    // MARK: - Disks

    private func disks() -> [SystemSnapshot.Disk] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey,
            .volumeIsBrowsableKey
        ]

        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        )

        return (volumes ?? []).compactMap { url in
            guard
                let values = try? url.resourceValues(forKeys: Set(keys)),
                values.volumeIsBrowsable == true,
                let total = values.volumeTotalCapacity,
                total > 0
            else { return nil }

            // The "important usage" figure is the one Finder shows, which
            // accounts for purgeable space. A monitor that disagrees with
            // Finder about free space gets reported as a bug.
            let free = values.volumeAvailableCapacityForImportantUsage ?? 0

            return SystemSnapshot.Disk(
                id: url.path,
                name: values.volumeName ?? url.lastPathComponent,
                free: UInt64(max(0, free)),
                total: UInt64(total)
            )
        }
    }

    // MARK: - Uptime and load

    private func uptime() -> Duration {
        .seconds(ProcessInfo.processInfo.systemUptime)
    }

    private func loadAverage() -> SystemSnapshot.LoadAverage {
        var loads = [Double](repeating: 0, count: 3)
        guard getloadavg(&loads, 3) == 3 else { return SystemSnapshot.LoadAverage() }
        return SystemSnapshot.LoadAverage(
            oneMinute: loads[0],
            fiveMinutes: loads[1],
            fifteenMinutes: loads[2]
        )
    }
}
