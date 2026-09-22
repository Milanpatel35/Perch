import Darwin
import Foundation
import PerchCore

/// The network half of the reader.
///
/// Its own file because the byte counters need two readings to mean
/// anything, and because the two rules that make them correct — skip
/// loopback and tunnels, and never report a negative delta when a counter
/// wraps — are the whole of TC-SYS-004.
extension SystemReader {

    struct InterfaceBytes {
        var received: UInt64 = 0
        var sent: UInt64 = 0
    }

    /// Every physical interface's byte counters, added up.
    ///
    /// Loopback is skipped — otherwise a local database server reads as
    /// 400MB/s of "network traffic", which is true and useless.
    func interfaceBytes() -> InterfaceBytes {
        var bytes = InterfaceBytes()

        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return bytes }
        defer { freeifaddrs(addresses) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }

            let name = String(cString: current.pointee.ifa_name)
            guard !name.hasPrefix("lo"), !name.hasPrefix("utun"), !name.hasPrefix("gif") else {
                continue
            }
            guard current.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) else { continue }
            guard let data = current.pointee.ifa_data else { continue }

            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            bytes.received &+= UInt64(stats.ifi_ibytes)
            bytes.sent &+= UInt64(stats.ifi_obytes)
        }

        return bytes
    }

    func network(at now: Date) -> SystemSnapshot.Network {
        var network = SystemSnapshot.Network()
        let bytes = interfaceBytes()

        if let previous {
            let elapsed = now.timeIntervalSince(previous.at)
            if elapsed > 0 {
                // Counters are 32-bit under the hood and wrap. A wrap would
                // otherwise read as a negative rate, or as a 4GB burst
                // (TC-SYS-004).
                let received =
                    bytes.received >= previous.networkIn
                    ? bytes.received - previous.networkIn : 0
                let sent =
                    bytes.sent >= previous.networkOut
                    ? bytes.sent - previous.networkOut : 0

                network.downRate = Double(received) / elapsed
                network.upRate = Double(sent) / elapsed
            }
        }

        network.isVPNActive = hasVPNInterface()
        return network
    }

    /// A `utun` interface with an address on it. Skipped above when counting
    /// bytes — VPN traffic is already counted on the physical interface it
    /// leaves by, and counting both doubles it.
    func hasVPNInterface() -> Bool {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return false }
        defer { freeifaddrs(addresses) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }

            let name = String(cString: current.pointee.ifa_name)
            let family = current.pointee.ifa_addr?.pointee.sa_family
            if name.hasPrefix("utun") || name.hasPrefix("ppp") || name.hasPrefix("ipsec") {
                if family == UInt8(AF_INET) { return true }
            }
        }
        return false
    }

}
