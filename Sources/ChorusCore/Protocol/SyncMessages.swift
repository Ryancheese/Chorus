import Foundation

/// Bonjour service type used for LAN discovery.
public enum SyncBonjour {
    public static let type = "_chorus._tcp"
    public static let domain = "local."
    public static let controlPort: UInt16 = 17_482
}

/// Wire protocol version. Bump when message layout changes.
public enum SyncProtocol {
    public static let version: UInt16 = 1
    /// Playback buffer ahead of host time (seconds). A longer lead absorbs Wi‑Fi jitter.
    public static let defaultLeadTime: TimeInterval = 1.2
    /// PCM format: mono Float32 @ 44.1 kHz for demo simplicity.
    public static let sampleRate: Double = 44_100
    public static let channels: UInt16 = 1
    public static let bytesPerSample: Int = 4
}

public enum MessageType: UInt8, Codable, Sendable {
    case hello = 1
    case welcome = 2
    case clockPing = 3
    case clockPong = 4
    case prepareSession = 5
    case startPlayback = 6
    case stopPlayback = 7
    case audioChunk = 8
    case heartbeat = 9
    case goodbye = 10
    case audioChannelHello = 11
    case stopAcknowledged = 12
    case clockOffset = 13
}

public struct DeviceInfo: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var role: Role
    public var protocolVersion: UInt16
    /// Optional platform hint: ios / android / windows / macos.
    public var platform: String?
    /// Optional hardware model, e.g. "iPhone 15 Pro", "Pixel 8".
    public var model: String?

    public enum Role: String, Codable, Sendable {
        case host
        case speaker
    }

    public init(
        id: String,
        name: String,
        role: Role,
        protocolVersion: UInt16 = SyncProtocol.version,
        platform: String? = nil,
        model: String? = nil
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.protocolVersion = protocolVersion
        self.platform = platform
        self.model = model
    }

    /// Short platform chip for Host UI (iPhone / iPad / Android / MacBook…).
    public var platformLabel: String {
        switch platform?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "ios": return "iPhone"
        case "ipados": return "iPad"
        case "android": return "Android"
        case "windows": return "Windows"
        case "macos", "mac": return "MacBook"
        default: return role == .host ? "Host" : "Speaker"
        }
    }

    /// Name plus model when available, for telling identical iPhones apart.
    /// iOS 16+ often reports a generic name ("iPhone") without entitlement — prefer model then.
    public var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let genericNames: Set<String> = ["iphone", "ipad", "ipod", "android", "speaker", "macos", "macbook"]
        if genericNames.contains(trimmedName.lowercased()), !trimmedModel.isEmpty {
            return trimmedModel
        }
        guard !trimmedModel.isEmpty else { return trimmedName }
        if trimmedName.localizedCaseInsensitiveContains(trimmedModel) { return trimmedName }
        return "\(trimmedName) · \(trimmedModel)"
    }

    /// Secondary chip under the name — platform family only (not the model again).
    public var detailLabel: String { platformLabel }
}

public struct ClockPing: Codable, Sendable {
    public var pingID: UUID
    public var hostSendTime: TimeInterval

    public init(pingID: UUID = UUID(), hostSendTime: TimeInterval) {
        self.pingID = pingID
        self.hostSendTime = hostSendTime
    }
}

public struct ClockPong: Codable, Sendable {
    public var pingID: UUID
    public var hostSendTime: TimeInterval
    public var speakerReceiveTime: TimeInterval
    public var speakerSendTime: TimeInterval

    public init(pingID: UUID, hostSendTime: TimeInterval, speakerReceiveTime: TimeInterval, speakerSendTime: TimeInterval) {
        self.pingID = pingID
        self.hostSendTime = hostSendTime
        self.speakerReceiveTime = speakerReceiveTime
        self.speakerSendTime = speakerSendTime
    }
}

public struct PrepareSession: Codable, Sendable {
    public var sessionID: UUID
    public var sampleRate: Double
    public var channels: UInt16
    public var title: String

    public init(
        sessionID: UUID = UUID(),
        sampleRate: Double = SyncProtocol.sampleRate,
        channels: UInt16 = SyncProtocol.channels,
        title: String
    ) {
        self.sessionID = sessionID
        self.sampleRate = sampleRate
        self.channels = channels
        self.title = title
    }
}

public struct StartPlayback: Codable, Sendable {
    public var sessionID: UUID
    /// Host monotonic time when sample 0 should play.
    public var hostPlayAt: TimeInterval
    public var leadTime: TimeInterval

    public init(sessionID: UUID, hostPlayAt: TimeInterval, leadTime: TimeInterval = SyncProtocol.defaultLeadTime) {
        self.sessionID = sessionID
        self.hostPlayAt = hostPlayAt
        self.leadTime = leadTime
    }
}

public struct AudioChunkHeader: Codable, Sendable {
    public var sessionID: UUID
    public var sequence: UInt64
    public var sampleIndex: UInt64
    public var sampleCount: UInt32
    /// Host time when this chunk's first sample should play.
    public var hostPlayAt: TimeInterval

    public init(sessionID: UUID, sequence: UInt64, sampleIndex: UInt64, sampleCount: UInt32, hostPlayAt: TimeInterval) {
        self.sessionID = sessionID
        self.sequence = sequence
        self.sampleIndex = sampleIndex
        self.sampleCount = sampleCount
        self.hostPlayAt = hostPlayAt
    }
}

public enum ControlPayload: Codable, Sendable {
    case hello(DeviceInfo)
    case welcome(DeviceInfo)
    case clockPing(ClockPing)
    case clockPong(ClockPong)
    case prepareSession(PrepareSession)
    case startPlayback(StartPlayback)
    case stopPlayback(sessionID: UUID)
    case audioChannelHello(deviceID: String)
    case stopAcknowledged(sessionID: UUID)
    case clockOffset(seconds: TimeInterval)
    case heartbeat(deviceID: String)
    case goodbye(deviceID: String)

    private enum CodingKeys: String, CodingKey {
        case type, payload
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .hello(let info):
            try container.encode(MessageType.hello, forKey: .type)
            try container.encode(info, forKey: .payload)
        case .welcome(let info):
            try container.encode(MessageType.welcome, forKey: .type)
            try container.encode(info, forKey: .payload)
        case .clockPing(let ping):
            try container.encode(MessageType.clockPing, forKey: .type)
            try container.encode(ping, forKey: .payload)
        case .clockPong(let pong):
            try container.encode(MessageType.clockPong, forKey: .type)
            try container.encode(pong, forKey: .payload)
        case .prepareSession(let session):
            try container.encode(MessageType.prepareSession, forKey: .type)
            try container.encode(session, forKey: .payload)
        case .startPlayback(let start):
            try container.encode(MessageType.startPlayback, forKey: .type)
            try container.encode(start, forKey: .payload)
        case .stopPlayback(let sessionID):
            try container.encode(MessageType.stopPlayback, forKey: .type)
            try container.encode(["sessionID": sessionID.uuidString], forKey: .payload)
        case .audioChannelHello(let deviceID):
            try container.encode(MessageType.audioChannelHello, forKey: .type)
            try container.encode(["deviceID": deviceID], forKey: .payload)
        case .stopAcknowledged(let sessionID):
            try container.encode(MessageType.stopAcknowledged, forKey: .type)
            try container.encode(["sessionID": sessionID.uuidString], forKey: .payload)
        case .clockOffset(let seconds):
            try container.encode(MessageType.clockOffset, forKey: .type)
            try container.encode(seconds, forKey: .payload)
        case .heartbeat(let deviceID):
            try container.encode(MessageType.heartbeat, forKey: .type)
            try container.encode(["deviceID": deviceID], forKey: .payload)
        case .goodbye(let deviceID):
            try container.encode(MessageType.goodbye, forKey: .type)
            try container.encode(["deviceID": deviceID], forKey: .payload)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(MessageType.self, forKey: .type)
        switch type {
        case .hello:
            self = .hello(try container.decode(DeviceInfo.self, forKey: .payload))
        case .welcome:
            self = .welcome(try container.decode(DeviceInfo.self, forKey: .payload))
        case .clockPing:
            self = .clockPing(try container.decode(ClockPing.self, forKey: .payload))
        case .clockPong:
            self = .clockPong(try container.decode(ClockPong.self, forKey: .payload))
        case .prepareSession:
            self = .prepareSession(try container.decode(PrepareSession.self, forKey: .payload))
        case .startPlayback:
            self = .startPlayback(try container.decode(StartPlayback.self, forKey: .payload))
        case .stopPlayback:
            let dict = try container.decode([String: String].self, forKey: .payload)
            guard let raw = dict["sessionID"], let id = UUID(uuidString: raw) else {
                throw DecodingError.dataCorruptedError(forKey: .payload, in: container, debugDescription: "Missing sessionID")
            }
            self = .stopPlayback(sessionID: id)
        case .audioChannelHello:
            let dict = try container.decode([String: String].self, forKey: .payload)
            self = .audioChannelHello(deviceID: dict["deviceID"] ?? "")
        case .stopAcknowledged:
            let dict = try container.decode([String: String].self, forKey: .payload)
            guard let raw = dict["sessionID"], let id = UUID(uuidString: raw) else {
                throw DecodingError.dataCorruptedError(forKey: .payload, in: container, debugDescription: "Missing sessionID")
            }
            self = .stopAcknowledged(sessionID: id)
        case .clockOffset:
            self = .clockOffset(seconds: try container.decode(TimeInterval.self, forKey: .payload))
        case .heartbeat:
            let dict = try container.decode([String: String].self, forKey: .payload)
            self = .heartbeat(deviceID: dict["deviceID"] ?? "")
        case .goodbye:
            let dict = try container.decode([String: String].self, forKey: .payload)
            self = .goodbye(deviceID: dict["deviceID"] ?? "")
        case .audioChunk:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "audioChunk is binary, not JSON")
        }
    }
}

public enum MessageCodec {
    public static let json = JSONEncoder()
    public static let jsonDecoder = JSONDecoder()

    public static func encodeControl(_ payload: ControlPayload) throws -> Data {
        try json.encode(payload)
    }

    public static func decodeControl(_ data: Data) throws -> ControlPayload {
        try jsonDecoder.decode(ControlPayload.self, from: data)
    }

    /// Binary audio frame: [1 byte type][4 byte headerLen][header JSON][pcm bytes]
    public static func encodeAudioFrame(header: AudioChunkHeader, pcm: Data) throws -> Data {
        let headerData = try json.encode(header)
        var out = Data()
        out.append(MessageType.audioChunk.rawValue)
        var headerLen = UInt32(headerData.count).bigEndian
        withUnsafeBytes(of: &headerLen) { out.append(contentsOf: $0) }
        out.append(headerData)
        out.append(pcm)
        return out
    }

    public static func decodeAudioFrame(_ data: Data) throws -> (AudioChunkHeader, Data) {
        guard data.count >= 5, data[0] == MessageType.audioChunk.rawValue else {
            throw CodecError.invalidFrame
        }
        let headerLen = Int(data.subdata(in: 1..<5).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
        let headerEnd = 5 + headerLen
        guard data.count >= headerEnd else { throw CodecError.invalidFrame }
        let header = try jsonDecoder.decode(AudioChunkHeader.self, from: data.subdata(in: 5..<headerEnd))
        let pcm = data.subdata(in: headerEnd..<data.count)
        return (header, pcm)
    }

    public enum CodecError: Error {
        case invalidFrame
    }
}

/// Length-prefixed TCP framing for control + audio multiplexed on one connection.
public enum FrameIO {
    public static func pack(_ payload: Data) -> Data {
        var len = UInt32(payload.count).bigEndian
        var out = Data()
        withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
        out.append(payload)
        return out
    }

    public final class Unpacker: @unchecked Sendable {
        private var buffer = Data()
        private let lock = NSLock()

        public init() {}

        public func append(_ data: Data) -> [Data] {
            lock.lock()
            defer { lock.unlock() }
            buffer.append(data)
            var frames: [Data] = []
            while buffer.count >= 4 {
                let length = Int(buffer.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
                guard buffer.count >= 4 + length else { break }
                let frame = buffer.subdata(in: 4..<(4 + length))
                buffer.removeSubrange(0..<(4 + length))
                frames.append(frame)
            }
            return frames
        }
    }
}
