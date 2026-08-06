import Foundation
import Network

enum LocalNetworkErrorText {
    /// Map Bonjour / local-network NWErrors to actionable localized copy.
    static func describe(_ error: Error) -> String {
        let text = error.localizedDescription
        if text.contains("-65555") || text.contains("NoAuth") {
            return L10n.text("error.bonjour.noauth")
        }
        if text.contains("-65570") || text.contains("PolicyDenied") {
            return L10n.text("error.local.network")
        }
        if text.contains("Address already in use") || text.contains("error 48") {
            return L10n.text("error.port.occupied")
        }
        return text
    }

    static func isBonjourAuthFailure(_ error: Error) -> Bool {
        let text = error.localizedDescription
        return text.contains("-65555")
            || text.contains("NoAuth")
            || text.contains("-65570")
            || text.contains("PolicyDenied")
    }
}

public struct DiscoveredPeer: Identifiable, Hashable, Sendable {
    public var id: String { endpointDebug }
    public var name: String
    public var endpointDebug: String
    public var nwEndpoint: NWEndpoint

    public init(name: String, endpoint: NWEndpoint) {
        self.name = name
        self.nwEndpoint = endpoint
        self.endpointDebug = String(describing: endpoint)
    }

    public static func == (lhs: DiscoveredPeer, rhs: DiscoveredPeer) -> Bool {
        lhs.endpointDebug == rhs.endpointDebug
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(endpointDebug)
    }
}

@MainActor
public final class PeerBrowser: ObservableObject {
    @Published public private(set) var peers: [DiscoveredPeer] = []
    @Published public private(set) var statusText = L10n.text("status.searching")
    @Published public private(set) var lastError: String?

    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "stereosync.browser")

    public init() {}

    public func start() {
        stop()
        statusText = L10n.text("status.searching")
        lastError = nil
        // This app is LAN-only. `nil` includes default/wide-area browse domains,
        // which can fail with DNSService NoAuth on managed networks.
        let descriptor = NWBrowser.Descriptor.bonjour(
            type: SyncBonjour.type,
            domain: SyncBonjour.domain
        )
        let browser = NWBrowser(for: descriptor, using: .tcp)

        browser.stateUpdateHandler = { [weak self] (state: NWBrowser.State) in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.statusText = L10n.text("status.search.ready")
                    self?.lastError = nil
                case .failed(let error):
                    self?.statusText = L10n.text("status.search.failed")
                    self?.lastError = LocalNetworkErrorText.describe(error)
                case .cancelled:
                    self?.statusText = L10n.text("status.search.stopped")
                case .waiting(let error):
                    self?.statusText = L10n.text("status.wait.network")
                    self?.lastError = LocalNetworkErrorText.describe(error)
                default:
                    break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] (results: Set<NWBrowser.Result>, _: Set<NWBrowser.Result.Change>) in
            let peers = results.compactMap { (result: NWBrowser.Result) -> DiscoveredPeer? in
                Self.makePeer(from: result)
            }
            .sorted { $0.name < $1.name }

            Task { @MainActor in
                self?.peers = peers
                if peers.isEmpty {
                    self?.statusText = L10n.text("status.no.devices")
                } else {
                    self?.statusText = "发现 \(peers.count) 台设备"
                }
            }
        }

        browser.start(queue: queue)
        self.browser = browser
    }

    public func stop() {
        browser?.cancel()
        browser = nil
        peers = []
    }

    nonisolated private static func makePeer(from result: NWBrowser.Result) -> DiscoveredPeer? {
        switch result.endpoint {
        case .service(let name, _, _, _):
            return DiscoveredPeer(name: name, endpoint: result.endpoint)
        default:
            return nil
        }
    }
}

@MainActor
public final class PeerAdvertiser: ObservableObject {
    @Published public private(set) var isAdvertising = false
    @Published public private(set) var lastError: String?
    @Published public private(set) var listeningPort: UInt16 = SyncBonjour.controlPort
    @Published public private(set) var localIPv4: String?
    /// True when TCP is up but Bonjour advertise was skipped/failed (manual IP still works).
    @Published public private(set) var bonjourUnavailable = false

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "stereosync.advertiser")
    private let deviceName: String
    private var advertiseBonjour = true
    public var onConnection: ((NWConnection) -> Void)?
    public var onStatusChange: (() -> Void)?

    public init(deviceName: String) {
        self.deviceName = deviceName
    }

    public func start() {
        start(advertiseBonjour: true)
    }

    private func start(advertiseBonjour: Bool) {
        stop(clearAddress: false)
        self.advertiseBonjour = advertiseBonjour
        lastError = nil
        bonjourUnavailable = !advertiseBonjour
        isAdvertising = false
        localIPv4 = LocalNetworkAddress.primaryIPv4()
        listeningPort = SyncBonjour.controlPort
        do {
            // Fixed port so Mac can connect manually when Bonjour is blocked.
            let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: SyncBonjour.controlPort)!)
            if advertiseBonjour {
                // Register only in the multicast-DNS local domain. Avoids attempting
                // a wide-area DNS registration that requires credentials (NoAuth).
                listener.service = NWListener.Service(
                    name: deviceName,
                    type: SyncBonjour.type,
                    domain: SyncBonjour.domain
                )
            }

            listener.stateUpdateHandler = { [weak self] (state: NWListener.State) in
                Task { @MainActor in
                    guard let self else { return }
                    // Ignore events from a listener we've already replaced (Bonjour → TCP fallback).
                    guard self.listener === listener else { return }
                    switch state {
                    case .ready:
                        self.isAdvertising = true
                        if let port = self.listener?.port?.rawValue {
                            self.listeningPort = port
                        }
                        self.localIPv4 = LocalNetworkAddress.primaryIPv4()
                        if self.bonjourUnavailable {
                            self.lastError = "自动发现不可用，请在 Mac 用本机 IP 手动连接。"
                        } else {
                            self.lastError = nil
                        }
                        self.onStatusChange?()
                    case .failed(let error):
                        // Bonjour privacy failure kills the whole listener — fall back to TCP-only.
                        if self.advertiseBonjour, LocalNetworkErrorText.isBonjourAuthFailure(error) {
                            let message = LocalNetworkErrorText.describe(error)
                            self.start(advertiseBonjour: false)
                            self.lastError = message
                            self.onStatusChange?()
                            return
                        }
                        self.isAdvertising = false
                        self.lastError = LocalNetworkErrorText.describe(error)
                        self.onStatusChange?()
                    case .cancelled:
                        self.isAdvertising = false
                    default:
                        break
                    }
                }
            }

            listener.newConnectionHandler = { [weak self] (connection: NWConnection) in
                Task { @MainActor in
                    self?.onConnection?(connection)
                }
            }

            listener.start(queue: queue)
            self.listener = listener
        } catch {
            lastError = error.localizedDescription
            isAdvertising = false
            onStatusChange?()
        }
    }

    public func stop() {
        stop(clearAddress: true)
    }

    private func stop(clearAddress: Bool) {
        listener?.cancel()
        listener = nil
        isAdvertising = false
        bonjourUnavailable = false
        if clearAddress {
            localIPv4 = nil
        }
    }
}
