import Foundation
#if canImport(UIKit)
import UIKit
#endif

public struct LocalIPv4Address: Equatable, Sendable {
    public let interface: String
    public let address: String

    public init(interface: String, address: String) {
        self.interface = interface
        self.address = address
    }
}

public enum LocalNetworkAddress {
    /// Prefer IPv4 Wi‑Fi / Ethernet / hotspot-bridge addresses for manual LAN connect.
    public static func preferredAddresses() -> [LocalIPv4Address] {
        var addresses: [LocalIPv4Address] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(first) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) == IFF_UP
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK
            guard isUp, !isLoopback else { continue }
            guard let addr = current.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }
            let ip = String(cString: hostname)
            if ip.hasPrefix("127.") { continue }
            let interface = String(cString: current.pointee.ifa_name)
            addresses.append(LocalIPv4Address(interface: interface, address: ip))
        }
        return addresses.sorted { lhs, rhs in
            let lp = interfacePriority(lhs.interface, address: lhs.address)
            let rp = interfacePriority(rhs.interface, address: rhs.address)
            if lp != rp { return lp < rp }
            // Prefer hotspot gateway/client addresses over unrelated IPs on same iface class.
            let lh = looksLikePersonalHotspot(lhs.address)
            let rh = looksLikePersonalHotspot(rhs.address)
            if lh != rh { return lh && !rh }
            return lhs.address < rhs.address
        }
    }

    public static func preferredIPv4Addresses() -> [String] {
        preferredAddresses().map(\.address)
    }

    public static func primaryIPv4() -> String? {
        primaryAddress()?.address
    }

    public static func primaryAddress() -> LocalIPv4Address? {
        let all = preferredAddresses()
        // When this device is the Personal Hotspot host, `bridge100` owns
        // 172.20.10.1 while `en0` may still rank higher — prefer the hotspot IP.
        if let hotspot = all.first(where: { looksLikePersonalHotspot($0.address) }) {
            return hotspot
        }
        return all.first
    }

    /// True when the *primary* address sits on a tunnel (real VPN), not merely
    /// that some idle system `utun*` also has an IPv4.
    public static func vpnInterfacesPresent() -> Bool {
        guard let primary = primaryAddress() else { return false }
        return isVPNInterface(primary.interface)
    }

    /// True if this device is on / hosting a personal hotspot LAN.
    public static func isPersonalHotspotActive() -> Bool {
        preferredAddresses().contains { looksLikePersonalHotspot($0.address) }
            || preferredAddresses().contains { $0.interface.hasPrefix("bridge") }
    }

    /// Personal hotspot ranges used by iPhone/Android tethering.
    public static func looksLikePersonalHotspot(_ ip: String) -> Bool {
        // iPhone Personal Hotspot defaults to 172.20.10.0/28
        if sameIPv4Subnet(ip, "172.20.10.1", prefixLength: 28) { return true }
        // Common Android hotspot: 192.168.43.0/24
        if sameIPv4Subnet(ip, "192.168.43.1", prefixLength: 24) { return true }
        // macOS Internet Sharing often uses 192.168.2.0/24
        if sameIPv4Subnet(ip, "192.168.2.1", prefixLength: 24) { return true }
        return false
    }

    public static func sameIPv4Subnet(_ lhs: String, _ rhs: String, prefixLength: Int = 24) -> Bool {
        guard let a = ipv4Octets(lhs), let b = ipv4Octets(rhs), prefixLength > 0, prefixLength <= 32 else {
            return false
        }
        let mask: UInt32
        if prefixLength == 32 {
            mask = 0xffff_ffff
        } else {
            mask = 0xffff_ffff << (32 - prefixLength)
        }
        return (a & mask) == (b & mask)
    }

    /// iOS Wi‑Fi is normally `en0`; hotspot host uses `bridge100` with 172.20.10.1.
    /// Virtual/VPN interfaces must not win as the manual LAN address.
    private static func interfacePriority(_ name: String, address: String) -> Int {
        if isVPNInterface(name) { return 40 }
        if address.hasPrefix("169.254.") { return 35 } // link-local
        if looksLikePersonalHotspot(address) || name.hasPrefix("bridge") {
            return 0
        }
        switch name {
        case "en0":
            return 1
        case "en1":
            return 2
        default:
            if name.hasPrefix("en") { return 3 }
            if name.hasPrefix("pdp_ip") { return 10 }
            return 5
        }
    }

    /// Exposed for path diagnostics; prefer `vpnInterfacesPresent()` for UI.
    public static func isVPNInterfaceName(_ name: String) -> Bool {
        isVPNInterface(name)
    }

    private static func isVPNInterface(_ name: String) -> Bool {
        name.hasPrefix("utun")
            || name.hasPrefix("ipsec")
            || name.hasPrefix("ppp")
            || name.hasPrefix("wg")
            || name.hasPrefix("tun")
            || name.hasPrefix("tap")
    }

    private static func ipv4Octets(_ text: String) -> UInt32? {
        let parts = text.split(separator: ".")
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard let octet = UInt32(part), octet <= 255 else { return nil }
            value = (value << 8) | octet
        }
        return value
    }
}
