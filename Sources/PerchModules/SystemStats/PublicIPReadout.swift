import Defaults
import Foundation
import PerchCore

/// The one network request in Perch outside the Sparkle update feed.
///
/// `CLAUDE.md` §5.2 allows exactly two exceptions and names this as one of
/// them: **off by default, disclosed in its own Preferences pane, and not in
/// the default install.** It lives in a file by itself so that all of it is
/// visible at once — the same reason the camera's snapshot does.
///
/// TC-SYS-012 asserts the default state: off, and no request made. TC-SYS-013
/// asserts that when it is on, the one request is made and fails silently
/// offline rather than putting an error in the island.
extension SystemStatsService {

    /// Whether the readout has been switched on by hand. Nothing else in the
    /// app reads this, and nothing turns it on for you.
    var isPublicIPEnabled: Bool { Defaults[.publicIPReadout] }

    func setPublicIPEnabled(_ isEnabled: Bool) {
        Defaults[.publicIPReadout] = isEnabled

        guard isEnabled else {
            clearPublicIP()
            return
        }
        refreshPublicIP()
    }

    /// Asks once. Not on a schedule: a public IP changes when a network
    /// changes, and a timer asking a third party every minute is exactly the
    /// behaviour this project exists in opposition to.
    func refreshPublicIP() {
        guard isActive, isPublicIPEnabled else { return }

        Task { [weak self] in
            guard let self else { return }
            let address = await Self.fetchPublicIP()
            guard isActive, isPublicIPEnabled else { return }
            setPublicIP(address)
        }
    }

    /// `https://api.ipify.org` — no account, no key, no logging claim beyond
    /// its own privacy page, and it answers with the address as plain text
    /// and nothing else. The request carries no identifier of any kind.
    ///
    /// Fails to `nil`. Offline is the normal case for a laptop, and an error
    /// message in a monitor is worse than a blank row (TC-SYS-013).
    private static func fetchPublicIP() async -> String? {
        guard let url = URL(string: "https://api.ipify.org") else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData

        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let text = String(data: data, encoding: .utf8)
        else { return nil }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // An address, or nothing. A body that is not an address is a captive
        // portal, and showing its HTML in the island would be absurd.
        return Self.isPlausibleAddress(trimmed) ? trimmed : nil
    }

    static func isPlausibleAddress(_ text: String) -> Bool {
        guard !text.isEmpty, text.count <= 45 else { return false }

        let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF.:")
        return text.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

extension Defaults.Keys {

    /// **Off.** The only switch in Perch that enables a network request, and
    /// the pane it lives in says so in as many words (TC-SYS-012).
    static let publicIPReadout = Key<Bool>("systemstats.publicIP", default: false)
}
