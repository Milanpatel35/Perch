import Foundation

/// One connected thing that reports a charge level.
///
/// AirPods report three levels and a mouse reports one, so the levels are a
/// value of their own rather than a single `Int` with two of them left nil at
/// every call site.
public struct AccessoryBattery: Identifiable, Equatable, Sendable {

    /// What the thing is. Drives the symbol, and the sort order — a keyboard
    /// that is about to die matters more than a game controller that is not
    /// switched on.
    public enum Kind: String, Equatable, Sendable, CaseIterable {
        case earbuds
        case headphones
        case mouse
        case keyboard
        case trackpad
        case gameController
        case other

        /// What kind of thing a product name describes.
        ///
        /// IOKit hands back a marketing string — "AirPods Pro", "Magic
        /// Trackpad" — and nothing machine-readable about what the device
        /// *is*. Matching on the name is a heuristic, so it lives here where
        /// it can be tested against the real strings rather than buried in
        /// the scanner where it cannot.
        public static func classify(productName: String) -> Self {
            let name = productName.lowercased()

            // Order matters: "AirPods Max" are headphones, and they match
            // both patterns.
            if name.contains("airpods max") || name.contains("beats studio") {
                return .headphones
            }
            if name.contains("airpods") || name.contains("buds") {
                return .earbuds
            }
            if name.contains("headphone") || name.contains("beats") {
                return .headphones
            }
            if name.contains("trackpad") { return .trackpad }
            if name.contains("keyboard") { return .keyboard }
            if name.contains("mouse") { return .mouse }
            if name.contains("controller") || name.contains("gamepad") {
                return .gameController
            }
            return .other
        }

        /// Lower sorts first. Stable, so the list does not reorder itself
        /// every time a level moves by a point.
        public var rank: Int {
            switch self {
            case .earbuds: 0
            case .headphones: 1
            case .keyboard: 2
            case .trackpad: 3
            case .mouse: 4
            case .gameController: 5
            case .other: 6
            }
        }
    }

    /// What a device reports. AirPods fill `left`, `right` and `caseLevel`;
    /// everything else fills `single`.
    public struct Levels: Equatable, Sendable {
        public var single: Int?
        public var left: Int?
        public var right: Int?
        public var caseLevel: Int?

        public init(
            single: Int? = nil,
            left: Int? = nil,
            right: Int? = nil,
            caseLevel: Int? = nil
        ) {
            self.single = single
            self.left = left
            self.right = right
            self.caseLevel = caseLevel
        }

        public var all: [Int] {
            [single, left, right, caseLevel].compactMap { $0 }
        }

        /// The one to warn about. A case at 80% is no comfort when the left
        /// bud is at 3%.
        public var lowest: Int? { all.min() }

        public var isEmpty: Bool { all.isEmpty }

        /// True when the device reports per-bud levels rather than one.
        public var isSplit: Bool { left != nil || right != nil }

        /// Zero means "not reporting", not "flat".
        ///
        /// A bud sitting in its case publishes its key with a zero in it, and
        /// the Mac's own keyboard publishes the whole service with no battery
        /// in it at all. Drawing either as an empty battery would have people
        /// charging something that is already full (TC-BAT-008).
        public static func reported(_ percent: Int?) -> Int? {
            guard let percent, percent > 0, percent <= 100 else { return nil }
            return percent
        }
    }

    /// The IORegistry entry's address or serial. Stable across a level
    /// change, which is what stops a reconnecting device appearing twice.
    public let id: String

    public var name: String
    public var kind: Kind
    public var levels: Levels

    /// Individually reported by very few devices; false is the honest
    /// default rather than a guess.
    public var isCharging: Bool

    public init(
        id: String,
        name: String,
        kind: Kind,
        levels: Levels,
        isCharging: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.levels = levels
        self.isCharging = isCharging
    }

    public var lowest: Int? { levels.lowest }
}

/// Every accessory currently reporting, in a stable order.
///
/// Replacing the roster wholesale is deliberate: the scan is the truth, and a
/// device that has stopped reporting has gone. Merging instead would leave a
/// disconnected mouse showing the level it had when it left (TC-BAT-004).
public struct AccessoryRoster: Equatable, Sendable {

    /// What changed between two scans, so the module knows whether it has
    /// anything worth putting on the island.
    public struct Changes: Equatable, Sendable {
        public var connected: [AccessoryBattery] = []
        public var disconnected: [AccessoryBattery] = []

        public var isEmpty: Bool { connected.isEmpty && disconnected.isEmpty }
    }

    public private(set) var accessories: [AccessoryBattery] = []

    public init(accessories: [AccessoryBattery] = []) {
        self.accessories = Self.sorted(accessories)
    }

    public var isEmpty: Bool { accessories.isEmpty }
    public var count: Int { accessories.count }

    /// The whole roster, from a fresh scan.
    @discardableResult
    public mutating func replace(with scanned: [AccessoryBattery]) -> Changes {
        let sorted = Self.sorted(scanned)
        let before = Dictionary(
            accessories.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let after = Dictionary(
            sorted.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var changes = Changes()
        changes.connected = sorted.filter { before[$0.id] == nil }
        changes.disconnected = accessories.filter { after[$0.id] == nil }

        accessories = sorted
        return changes
    }

    public func accessory(_ id: String) -> AccessoryBattery? {
        accessories.first { $0.id == id }
    }

    /// The one closest to dying, if any of them report at all.
    public var lowest: AccessoryBattery? {
        accessories
            .filter { $0.lowest != nil }
            .min { ($0.lowest ?? 100) < ($1.lowest ?? 100) }
    }

    /// Kind first, then name. Never by level — a list that reorders itself as
    /// numbers tick is a list you cannot click on.
    private static func sorted(_ items: [AccessoryBattery]) -> [AccessoryBattery] {
        items.sorted {
            $0.kind.rank == $1.kind.rank
                ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                : $0.kind.rank < $1.kind.rank
        }
    }
}
