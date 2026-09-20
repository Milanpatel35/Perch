import Foundation

/// What is on the shelf, and the rules about it.
///
/// Pure. It holds records, orders them, bounds them and encodes them; it
/// never touches the filesystem. Copying a dropped file into the container is
/// the module's job, which is what lets every rule here — ordering, capacity,
/// availability, clear-on-quit — be a fast unit test (`CLAUDE.md` §3).
public struct ShelfStore: Equatable, Sendable, Codable {

    /// Above this, the oldest item is dropped.
    ///
    /// A shelf is a staging area, not storage. Someone who drags fifty files
    /// at once (TC-SHF-003) must get all fifty; someone who never clears it
    /// must not accumulate forever.
    public static let capacity = 64

    /// Newest first, which is the order the expanded island draws them in and
    /// the order a person expects — the thing you just dropped is on top.
    public private(set) var items: [ShelfItem] = []

    public init(items: [ShelfItem] = []) {
        self.items = items
        sort()
    }

    public var isEmpty: Bool { items.isEmpty }
    public var count: Int { items.count }

    /// The badge on the collapsed island (`docs/FEATURES.md` §2).
    public var badgeCount: Int { items.count }

    /// Total size of everything held, for the expanded header.
    public var byteCount: Int64 {
        items.reduce(0) { $0 + $1.byteCount }
    }

    // MARK: - Mutation

    /// Adds items, newest first, and enforces capacity.
    ///
    /// - Returns: the items actually added. A drop of something already on
    ///   the shelf is not an error and not a duplicate — it refreshes what is
    ///   there, because dragging the same file twice is a thing people do and
    ///   two identical rows is never what they meant.
    @discardableResult
    public mutating func add(_ incoming: [ShelfItem]) -> [ShelfItem] {
        var added: [ShelfItem] = []

        for item in incoming {
            if let index = items.firstIndex(where: { $0.isSameSource(as: item) }) {
                items[index].addedAt = item.addedAt
                items[index].isAvailable = true
            } else {
                items.append(item)
                added.append(item)
            }
        }

        sort()
        evictIfNeeded()
        return added
    }

    @discardableResult
    public mutating func remove(_ id: ShelfItem.ID) -> ShelfItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: index)
    }

    public mutating func removeAll() {
        items.removeAll()
    }

    /// Marks an item unavailable rather than removing it.
    ///
    /// Deliberately not a removal: an item vanishing from the shelf with no
    /// explanation reads as Perch having lost it. A greyed row with the name
    /// still on it reads as what actually happened (TC-SHF-005).
    public mutating func markUnavailable(_ id: ShelfItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isAvailable = false
    }

    /// Re-checks availability against whatever the caller can see.
    ///
    /// Takes a predicate rather than reaching for `FileManager`, which is how
    /// this type stays pure and how TC-SHF-005 stays a unit test.
    public mutating func refreshAvailability(using exists: (String) -> Bool) {
        for index in items.indices {
            guard let path = items[index].storedPath else { continue }
            items[index].isAvailable = exists(path)
        }
    }

    // MARK: - Ordering

    private mutating func sort() {
        items.sort { $0.addedAt > $1.addedAt }
    }

    private mutating func evictIfNeeded() {
        guard items.count > Self.capacity else { return }
        items.removeLast(items.count - Self.capacity)
    }
}
