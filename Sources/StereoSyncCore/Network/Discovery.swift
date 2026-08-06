import Foundation
import Network

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
    @Published public private(set) var statusText = "正在搜索…"
    @Published public private(set) var lastError: String?

    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "stereosync.browser")

    public init() {}

    public func start() {
        stop()
        statusText = "正在搜索局域网扬声器…"
        lastError = nil
        // `nil` domain searches default browse domains (more reliable than hardcoding local.)
        let descriptor = NWBrowser.Descriptor.bonjour(type: SyncBonjour.type, domain: nil)
        let browser = NWBrowser(for: descriptor, using: .tcp)

        browser.stateUpdateHandler = { [weak self] (state: NWBrowser.State) in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.statusText = "已开始搜索，等待设备广播…"
                    self?.lastError = nil
                case .failed(let error):
                    self?.statusText = "搜索失败"
                    self?.lastError = error.localizedDescription
                case .cancelled:
                    self?.statusText = "搜索已停止"
                case .waiting(let error):
                    self?.statusText = "等待本地网络权限…"
                    self?.lastError = error.localizedDescription
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
                    self?.statusText = "未发现设备，可用下方手动 IP 连接"
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

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "stereosync.advertiser")
    private let deviceName: String
    public var onConnection: ((NWConnection) -> Void)?

    public init(deviceName: String) {
        self.deviceName = deviceName
    }

    public func start() {
        stop()
        lastError = nil
        isAdvertising = false
        localIPv4 = LocalNetworkAddress.primaryIPv4()
        listeningPort = SyncBonjour.controlPort
        do {
            // Fixed port so Mac can connect manually when Bonjour is blocked.
            let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: SyncBonjour.controlPort)!)
            listener.service = NWListener.Service(name: deviceName, type: SyncBonjour.type)

            listener.stateUpdateHandler = { [weak self] (state: NWListener.State) in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.isAdvertising = true
                        self.lastError = nil
                        if let port = self.listener?.port?.rawValue {
                            self.listeningPort = port
                        }
                        self.localIPv4 = LocalNetworkAddress.primaryIPv4()
                    case .failed(let error):
                        self.isAdvertising = false
                        self.lastError = error.localizedDescription
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
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        isAdvertising = false
        localIPv4 = nil
    }
}
