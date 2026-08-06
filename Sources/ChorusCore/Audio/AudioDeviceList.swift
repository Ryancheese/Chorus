#if os(macOS)
import CoreAudio
import Foundation

public struct AudioDevice: Identifiable, Hashable {
    public let id: AudioDeviceID
    public let name: String
    public let inputChannels: Int
    public let outputChannels: Int

    public var isBlackHole: Bool {
        name.localizedCaseInsensitiveContains("BlackHole")
    }
}

public enum AudioDeviceList {
    public static func allDevices() -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ) == noErr else {
            return []
        }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &ids
        ) == noErr else {
            return []
        }

        return ids.map { id in
            AudioDevice(
                id: id,
                name: deviceName(id) ?? "未知设备",
                inputChannels: channelCount(id, scope: kAudioDevicePropertyScopeInput),
                outputChannels: channelCount(id, scope: kAudioDevicePropertyScopeOutput)
            )
        }
    }

    public static func blackHoleInput() -> AudioDevice? {
        allDevices().first { $0.isBlackHole && $0.inputChannels > 0 }
    }

    public static func builtInOutput() -> AudioDevice? {
        let outputs = allDevices().filter { !$0.isBlackHole && $0.outputChannels > 0 }
        return outputs.first {
            $0.name.localizedCaseInsensitiveContains("MacBook")
                || $0.name.localizedCaseInsensitiveContains("Built-in")
        } ?? outputs.first
    }

    public static func defaultOutputID() -> AudioDeviceID? {
        defaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    public static func defaultInputID() -> AudioDeviceID? {
        defaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    public static func setDefaultOutput(_ id: AudioDeviceID) throws {
        try setDefaultDevice(id, selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    public static func setDefaultInput(_ id: AudioDeviceID) throws {
        try setDefaultDevice(id, selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    private static func defaultDeviceID(selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var id: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &id
        ) == noErr else {
            return nil
        }
        return id
    }

    private static func setDefaultDevice(
        _ id: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) throws {
        var value = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            size,
            &value
        )
        guard status == noErr else {
            throw NSError(
                domain: "Chorus.AudioDevice",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "无法切换系统音频设备"]
            )
        }
    }

    private static func deviceName(_ id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr else {
            return nil
        }
        return name as String
    }

    private static func channelCount(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else {
            return 0
        }

        let rawBuffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBuffer.deallocate() }
        let bufferList = rawBuffer.assumingMemoryBound(to: AudioBufferList.self)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, bufferList) == noErr else {
            return 0
        }
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
#endif
