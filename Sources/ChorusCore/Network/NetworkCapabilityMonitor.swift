import Foundation
import Network

/// Observes path + interface shape so UI can warn about VPN / restricted LANs
/// where Bonjour and peer-to-peer TCP often fail.
@MainActor
public final class NetworkCapabilityMonitor: ObservableObject {
    @Published public private(set) var isSatisfied = false
    @Published public private(set) var usesWiFi = false
    @Published public private(set) var usesWired = false
    @Published public private(set) var vpnLikely = false
    @Published public private(set) var localIPv4: String?
    @Published public private(set) var interfaceName: String?
    /// Short actionable banner for Host / Speaker UI (nil when network looks fine).
    @Published public private(set) var warningText: String?

    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "chorus.path")

    public init() {}

    public func start() {
        stop()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.apply(path)
            }
        }
        monitor.start(queue: queue)
        self.monitor = monitor
        refreshAddresses()
    }

    public func stop() {
        monitor?.cancel()
        monitor = nil
    }

    public func refreshAddresses() {
        let primary = LocalNetworkAddress.primaryAddress()
        localIPv4 = primary?.address
        interfaceName = primary?.interface
        updateWarning()
    }

    private func apply(_ path: NWPath) {
        isSatisfied = path.status == .satisfied
        usesWiFi = path.usesInterfaceType(.wifi)
        usesWired = path.usesInterfaceType(.wiredEthernet)
        let primary = LocalNetworkAddress.primaryAddress()
        localIPv4 = primary?.address
        interfaceName = primary?.interface

        // Hotspot / USB tether may report `.other`; that alone is not a VPN.
        // Only warn when a tunnel interface actually owns the preferred IPv4,
        // or when path is `.other`-only with no Wi‑Fi/Ethernet (typical VPN).
        let primaryOnTunnel = primary.map { LocalNetworkAddress.isVPNInterfaceName($0.interface) } ?? false
        let otherOnlyPath = path.usesInterfaceType(.other) && !usesWiFi && !usesWired
        vpnLikely = primaryOnTunnel || otherOnlyPath
        updateWarning()
    }

    private func updateWarning() {
        if !isSatisfied {
            warningText = L10n.text("network.warn.offline")
            return
        }
        if LocalNetworkAddress.isPersonalHotspotActive() {
            // Hotspot host or client — expected path for locked-down Wi‑Fi.
            warningText = nil
            vpnLikely = false
            return
        }
        if vpnLikely {
            warningText = L10n.text("network.warn.vpn")
            return
        }
        if !usesWiFi && !usesWired {
            warningText = L10n.text("network.warn.no.lan")
            return
        }
        warningText = nil
    }
}

enum ConnectFailureText {
    /// Map TCP / NWConnection failures to localized, actionable copy.
    static func describe(_ reason: String?) -> String {
        guard let reason, !reason.isEmpty else {
            return L10n.text("error.connect.failed")
        }
        let lower = reason.lowercased()
        if lower.contains("timed out")
            || lower.contains("timeout")
            || lower.contains("60")
            || lower.contains("etimedout") {
            return L10n.text("error.connect.timeout")
        }
        if lower.contains("host is down")
            || lower.contains("no route")
            || lowerContainsAny(lower, ["ehostunreach", "enetunreach", "unreachable"]) {
            return L10n.text("error.connect.unreachable")
        }
        if lower.contains("connection refused")
            || lower.contains("econnrefused")
            || lower.contains("61") {
            return L10n.text("error.connect.refused")
        }
        if lower.contains("network is down") || lower.contains("enotconn") {
            return L10n.text("error.connect.unreachable")
        }
        return reason
    }

    private static func lowerContainsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    static func likelyDifferentSubnet(local: String?, remote: String) -> Bool {
        guard let local else { return false }
        return !LocalNetworkAddress.sameIPv4Subnet(local, remote)
    }
}
