import Foundation

/// Everything the monitor knows, at one moment.
///
/// Built by `SystemReader` in the module layer from Mach and IOKit. Every
/// field is optional where the hardware may not answer, because
/// `docs/FEATURES.md` §10 says the rows degrade gracefully and TC-SYS-005
/// and TC-SYS-006 say what that means: the row is hidden, not zeroed.
public struct SystemSnapshot: Equatable, Sendable {

    public var cpu = CPU()
    public var memory = Memory()
    public var disks: [Disk] = []
    public var network = Network()

    /// `nil` on hardware that does not publish sensors, or where reading
    /// them would need a private interface. Hidden rather than zeroed
    /// (TC-SYS-005).
    public var thermal: Thermal?

    /// `nil` on Intel, where the Apple Silicon accelerator statistics do not
    /// exist. No Apple-Silicon-only API is called there at all (TC-SYS-006).
    public var gpu: GPU?

    public var uptime: Duration = .seconds(0)

    public var loadAverage = LoadAverage()

    /// The three numbers `uptime` prints. A value rather than a tuple so it
    /// can be compared, printed and labelled — a `(Double, Double, Double)`
    /// is three anonymous numbers nobody can read at the call site.
    public struct LoadAverage: Equatable, Sendable {
        public var oneMinute: Double = 0
        public var fiveMinutes: Double = 0
        public var fifteenMinutes: Double = 0

        public init(oneMinute: Double = 0, fiveMinutes: Double = 0, fifteenMinutes: Double = 0) {
            self.oneMinute = oneMinute
            self.fiveMinutes = fiveMinutes
            self.fifteenMinutes = fifteenMinutes
        }
    }

    /// Complements module 7, which owns charge and time remaining. This is
    /// the part a battery *monitor* wants and a battery *indicator* does not.
    public var batteryHealth: BatteryHealth?

    public init() {}

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.cpu == rhs.cpu
            && lhs.memory == rhs.memory
            && lhs.disks == rhs.disks
            && lhs.network == rhs.network
            && lhs.thermal == rhs.thermal
            && lhs.gpu == rhs.gpu
            && lhs.uptime == rhs.uptime
            && lhs.loadAverage == rhs.loadAverage
            && lhs.batteryHealth == rhs.batteryHealth
    }

    // MARK: - CPU

    public struct CPU: Equatable, Sendable {
        /// 0–1, all cores together.
        public var total: Double = 0

        /// 0–1 per core, in the order the kernel reports them.
        public var perCore: [Double] = []

        /// The process using the most CPU right now, if one stands out.
        public var topProcess: Process?

        public init(total: Double = 0, perCore: [Double] = [], topProcess: Process? = nil) {
            self.total = total
            self.perCore = perCore
            self.topProcess = topProcess
        }

        public struct Process: Equatable, Sendable {
            public let name: String
            public let usage: Double

            public init(name: String, usage: Double) {
                self.name = name
                self.usage = usage
            }
        }
    }

    // MARK: - Memory

    public struct Memory: Equatable, Sendable {
        public var used: UInt64 = 0
        public var cached: UInt64 = 0
        public var swapUsed: UInt64 = 0
        public var total: UInt64 = 0

        /// Activity Monitor's own reading, from the same numbers it uses.
        public var pressure: Pressure = .normal

        public init() {}

        /// The colour Activity Monitor draws, and the thresholds it draws it
        /// at (`docs/FEATURES.md` §10). Matching them is the point: a
        /// monitor that disagrees with the system monitor is the one people
        /// stop trusting.
        public enum Pressure: String, Equatable, Sendable, CaseIterable {
            case normal
            case warning
            case critical
        }

        public var usedFraction: Double {
            total > 0 ? Double(used) / Double(total) : 0
        }
    }

    // MARK: - Disk

    public struct Disk: Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let free: UInt64
        public let total: UInt64

        /// Bytes per second since the previous sample. `nil` on the first
        /// one, because a rate needs two readings.
        public let readRate: Double?
        public let writeRate: Double?

        public init(
            id: String,
            name: String,
            free: UInt64,
            total: UInt64,
            readRate: Double? = nil,
            writeRate: Double? = nil
        ) {
            self.id = id
            self.name = name
            self.free = free
            self.total = total
            self.readRate = readRate
            self.writeRate = writeRate
        }

        public var usedFraction: Double {
            total > 0 ? Double(total - free) / Double(total) : 0
        }
    }

    // MARK: - Network

    public struct Network: Equatable, Sendable {
        /// Bytes per second. `nil` on the first sample.
        public var downRate: Double?
        public var upRate: Double?

        public var ssid: String?
        public var isVPNActive = false

        /// Only ever set when the readout has been switched on by hand.
        /// **The one network request in the whole app** outside Sparkle
        /// (`CLAUDE.md` §5.2, TC-SYS-012).
        public var publicIP: String?

        public init() {}
    }

    // MARK: - Thermal and GPU

    public struct Thermal: Equatable, Sendable {
        public var temperature: Double?
        public var fanRPM: [Int] = []

        public init(temperature: Double? = nil, fanRPM: [Int] = []) {
            self.temperature = temperature
            self.fanRPM = fanRPM
        }

        /// A reading with nothing readable in it is not a reading. The view
        /// checks this rather than drawing a row of dashes.
        public var isEmpty: Bool { temperature == nil && fanRPM.isEmpty }
    }

    public struct GPU: Equatable, Sendable {
        public var utilisation: Double?
        public var vramUsed: UInt64?
        public var vramTotal: UInt64?

        public init(
            utilisation: Double? = nil,
            vramUsed: UInt64? = nil,
            vramTotal: UInt64? = nil
        ) {
            self.utilisation = utilisation
            self.vramUsed = vramUsed
            self.vramTotal = vramTotal
        }

        public var isEmpty: Bool { utilisation == nil && vramUsed == nil }
    }

    public struct BatteryHealth: Equatable, Sendable {
        public let cycleCount: Int
        public let maximumCapacity: Double

        public init(cycleCount: Int, maximumCapacity: Double) {
            self.cycleCount = cycleCount
            self.maximumCapacity = maximumCapacity
        }
    }
}
