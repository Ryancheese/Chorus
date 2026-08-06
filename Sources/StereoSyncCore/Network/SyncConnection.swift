import Foundation
import Network

public enum SyncConnectionEvent: Sendable {
    case connected
    case disconnected(String?)
    case control(ControlPayload)
    case audio(AudioChunkHeader, Data)
}

/// Bidirectional framed TCP session used by both host and speaker.
public final class SyncConnection: @unchecked Sendable {
    public let connection: NWConnection
    public let remoteLabel: String

    private let queue = DispatchQueue(label: "stereosync.connection")
    private let unpacker = FrameIO.Unpacker()
    private var onEvent: ((SyncConnectionEvent) -> Void)?
    private let lock = NSLock()

    public init(connection: NWConnection, remoteLabel: String = "peer") {
        self.connection = connection
        self.remoteLabel = remoteLabel
    }

    public func start(onEvent: @escaping (SyncConnectionEvent) -> Void) {
        lock.lock()
        self.onEvent = onEvent
        lock.unlock()

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.emit(.connected)
                self.receiveLoop()
            case .failed(let error):
                self.emit(.disconnected(error.localizedDescription))
            case .cancelled:
                self.emit(.disconnected(nil))
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    public func cancel() {
        connection.cancel()
    }

    public func sendControl(_ payload: ControlPayload) {
        do {
            let data = try MessageCodec.encodeControl(payload)
            sendFrame(data)
        } catch {
            emit(.disconnected("encode control failed: \(error)"))
        }
    }

    /// Sends a single audio frame and waits until Network.framework has processed it.
    /// Keeping only one frame in flight lets a subsequent control message (such as
    /// stop playback) reach the peer promptly instead of waiting behind a full track.
    public func sendAudio(header: AudioChunkHeader, pcm: Data) async {
        do {
            let data = try MessageCodec.encodeAudioFrame(header: header, pcm: pcm)
            await sendFrameAndWait(data)
        } catch {
            emit(.disconnected("encode audio failed: \(error)"))
        }
    }

    private func sendFrame(_ payload: Data) {
        let framed = FrameIO.pack(payload)
        connection.send(content: framed, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.emit(.disconnected(error.localizedDescription))
            }
        })
    }

    private func sendFrameAndWait(_ payload: Data) async {
        let framed = FrameIO.pack(payload)
        await withCheckedContinuation { continuation in
            connection.send(content: framed, completion: .contentProcessed { [weak self] error in
                if let error {
                    self?.emit(.disconnected(error.localizedDescription))
                }
                continuation.resume()
            })
        }
    }

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] content, _, isComplete, error in
            guard let self else { return }
            if let error {
                self.emit(.disconnected(error.localizedDescription))
                return
            }
            if let content {
                for frame in self.unpacker.append(content) {
                    self.handleFrame(frame)
                }
            }
            if isComplete {
                self.emit(.disconnected(nil))
                return
            }
            self.receiveLoop()
        }
    }

    private func handleFrame(_ frame: Data) {
        guard let first = frame.first else { return }
        if first == MessageType.audioChunk.rawValue {
            do {
                let (header, pcm) = try MessageCodec.decodeAudioFrame(frame)
                emit(.audio(header, pcm))
            } catch {
                emit(.disconnected("bad audio frame"))
            }
            return
        }
        do {
            let payload = try MessageCodec.decodeControl(frame)
            emit(.control(payload))
        } catch {
            emit(.disconnected("bad control frame"))
        }
    }

    private func emit(_ event: SyncConnectionEvent) {
        lock.lock()
        let handler = onEvent
        lock.unlock()
        handler?(event)
    }
}

public extension SyncConnection {
    static func connect(to endpoint: NWEndpoint) -> SyncConnection {
        let connection = NWConnection(to: endpoint, using: .tcp)
        return SyncConnection(connection: connection, remoteLabel: String(describing: endpoint))
    }
}
