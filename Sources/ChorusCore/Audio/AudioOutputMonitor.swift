import Foundation
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

/// Watches media output volume so Speaker can warn when playback would be inaudible.
@MainActor
public final class AudioOutputMonitor: ObservableObject {
    public static let lowVolumeThreshold: Float = 0.08

    @Published public private(set) var outputVolume: Float = 1
    @Published public private(set) var isVolumeLow = false
    /// User-facing tip, or nil when output looks fine.
    @Published public private(set) var warningText: String?

    private var volumeObservation: NSKeyValueObservation?

    public init() {}

    public func start() {
        stop()
        #if canImport(UIKit)
        let session = AVAudioSession.sharedInstance()
        outputVolume = session.outputVolume
        refreshFlags()
        volumeObservation = session.observe(\.outputVolume, options: [.initial, .new]) { [weak self] session, _ in
            let value = session.outputVolume
            Task { @MainActor in
                self?.outputVolume = value
                self?.refreshFlags()
            }
        }
        #endif
    }

    public func stop() {
        volumeObservation?.invalidate()
        volumeObservation = nil
    }

    public func refresh() {
        #if canImport(UIKit)
        outputVolume = AVAudioSession.sharedInstance().outputVolume
        #endif
        refreshFlags()
    }

    private func refreshFlags() {
        #if canImport(UIKit)
        isVolumeLow = outputVolume < Self.lowVolumeThreshold
        if isVolumeLow {
            // `.playback` ignores the Ring/Silent switch; media volume still applies.
            warningText = L10n.text("audio.warn.volume.low")
        } else {
            warningText = nil
        }
        #else
        isVolumeLow = false
        warningText = nil
        #endif
    }
}
