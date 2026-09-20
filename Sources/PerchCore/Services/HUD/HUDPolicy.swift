import Foundation

/// Decides which readings actually reach the island.
///
/// The watchers are deliberately stupid — they report every change macOS
/// hands them, and macOS hands them a lot. Holding the brightness key sends
/// one notification per step. Every rule about what to do with that stream
/// lives here, pure and synchronous, so `docs/TEST-PLAN.md` § HUD can be
/// tested without a volume key, a display or a Bluetooth radio.
public struct HUDPolicy: Equatable, Sendable {

    /// Which HUDs are switched on. Every one is individually switchable —
    /// that is `docs/FEATURES.md` §6's last row, and TC-HUD-008.
    public var enabled: Set<HUDKind>

    /// The last reading admitted for each kind.
    private var last: [HUDKind: HUDReading] = [:]

    /// Kinds whose next reading is to be swallowed. See `suppressNext`.
    private var suppressed: Set<HUDKind> = []

    public init(enabled: Set<HUDKind> = Set(HUDKind.allCases)) {
        self.enabled = enabled
    }

    /// Whether this reading is worth showing, and records it if so.
    ///
    /// Three reasons to say no, in order:
    ///
    /// 1. **The HUD is switched off.** Individually, with the module still
    ///    on — only that one stops, and the others are unaffected
    ///    (TC-HUD-008).
    /// 2. **Perch caused this change itself.** Turning a Focus on from the
    ///    island must not then announce that a Focus turned on, which would
    ///    be Perch telling you what you just told it (TC-HUD-007).
    /// 3. **Nothing actually changed.** macOS re-reports the same value
    ///    often — on a display waking, on a device reconnecting, and at the
    ///    ends of a held brightness key where the level has already hit its
    ///    limit. Re-submitting an identical reading would restart the
    ///    island's time to live and leave the HUD hanging there; dropping it
    ///    is what makes a held key coalesce into one smooth HUD rather than
    ///    a flicker (TC-HUD-002).
    public mutating func admit(_ reading: HUDReading) -> Bool {
        guard enabled.contains(reading.kind) else { return false }

        // Both remaining cases still record the reading. A swallowed change
        // is still the current state, and forgetting it would make the *next*
        // change look like a repeat — or worse, make a repeat look new.
        guard suppressed.remove(reading.kind) == nil else {
            last[reading.kind] = reading
            return false
        }

        guard last[reading.kind] != reading else { return false }

        last[reading.kind] = reading
        return true
    }

    /// Swallow the next reading of this kind.
    ///
    /// For changes Perch made: the island toggles a Focus, macOS reports the
    /// Focus changed, and without this the HUD would announce it back
    /// (TC-HUD-007). One reading, not a window of time — a deadline would
    /// either swallow somebody else's change or miss ours, depending on how
    /// busy the machine was.
    public mutating func suppressNext(_ kind: HUDKind) {
        guard enabled.contains(kind) else { return }
        suppressed.insert(kind)
    }

    /// The last reading admitted for a kind, if any. The views use it to
    /// open into the current state rather than the one that fired.
    public func current(_ kind: HUDKind) -> HUDReading? {
        last[kind]
    }

    public func isEnabled(_ kind: HUDKind) -> Bool {
        enabled.contains(kind)
    }

    public mutating func setEnabled(_ kind: HUDKind, _ isOn: Bool) {
        if isOn {
            enabled.insert(kind)
        } else {
            enabled.remove(kind)
            // Drop what we knew about a HUD that is off, so switching it back
            // on does not compare against a value from before it was.
            last[kind] = nil
            suppressed.remove(kind)
        }
    }

    /// Forgets everything. Called when the module is switched off, so that
    /// switching it back on starts from a clean baseline rather than
    /// comparing against a value from an earlier session.
    public mutating func reset() {
        last.removeAll()
        suppressed.removeAll()
    }
}
