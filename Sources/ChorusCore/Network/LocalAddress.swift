import Foundation
#if canImport(UIKit)
import UIKit
#endif

public enum LocalNetworkAddress {
    /// Prefer IPv4 Wi‑Fi / Ethernet addresses for manual LAN connect.
    public static func preferredIPv4Addresses() -> [String] {
        var addresses: [(interface: String, address: String)] = []
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
            addresses.append((interface, ip))
        }
        return addresses
            .sorted { lhs, rhs in
                interfacePriority(lhs.interface) < interfacePriority(rhs.interface)
            }
            .map(\.address)
    }

    public static func primaryIPv4() -> String? {
        preferredIPv4Addresses().first
    }

    /// iOS Wi‑Fi is normally `en0`; virtual/VPN interfaces often appear first
    /// in `getifaddrs` and must not be used for a manual LAN address.
    private static func interfacePriority(_ name: String) -> Int {
        switch name {
        case "en0":
            return 0
        case "en1":
            return 1
        default:
            if name.hasPrefix("en") { return 2 }
            if name.hasPrefix("pdp_ip") { return 10 }
            if name.hasPrefix("utun") { return 20 }
            return 5
        }
    }
}
