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

    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "stereosync.browser")

    public init() {}

    public func start() {
        stop()
        let descriptor = NWBrowser.Descriptor.bonjour(type: SyncBonjour.type, domain: SyncBonjour.domain)
        let browser = NWBrowser(for: descriptor, using: .tcp)
        browser.stateUpdateHandler = { [weak self] _, _, _ in
            // Intentionally quiet; results handler drives UI.
            _ = self
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.peers = results.compactMap { result in
                    guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                    return DiscoveredPeer(name: name, endpoint: result.endpoint)
                }
                .sorted { $0.name < $1.name }
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
}

@MainActor
public final class PeerAdvertiser: ObservableObject {
    @Published public private(set) var isAdvertising = false
    @Published public private(set) var lastError: String?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "stereosync.advertiser")
    private let deviceName: String
    public var onConnection: ((NWConnection) -> Void)?

    public init(deviceName: String) {
        self.deviceName = deviceName
    }

    public func start() {
        stop()
        do {
            let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: SyncBonjour.controlPort)!)
            listener.service = NWListener.Service(name: deviceName, type: SyncBonjour.type, domain: SyncBonjour.domain)
            listener.stateUpdateHandler = { [weak self] _, state, _ in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isAdvertising = true
                        self?.lastError = nil
                    case .failed(let error):
                        self?.isAdvertising = false
                        self?.lastError = error.localizedDescription
                    case .cancelled:
                        self?.isAdvertising = false
                    default:
                        break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
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
    }
}
