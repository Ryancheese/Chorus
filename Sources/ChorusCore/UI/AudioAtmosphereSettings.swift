import Combine
import Foundation
import SwiftUI
#if os(iOS)
import AVFoundation
import CoreHaptics
#endif

/// Speaker audio-reactive atmosphere preferences (blobs / torch / Music-like haptics).
@MainActor
public final class AudioAtmosphereSettings: ObservableObject {
    private static let blobsKey = "chorus.audio.ambientBlobs"
    private static let torchKey = "chorus.audio.torchBeat"
    private static let hapticKey = "chorus.audio.hapticMusic"

    /// Soft background blobs pulse with the mix.
    @Published public var ambientBlobsEnabled: Bool {
        didSet { UserDefaults.standard.set(ambientBlobsEnabled, forKey: Self.blobsKey) }
    }

    /// Rear LED brightness follows the audio envelope (iPhone).
    @Published public var torchBeatEnabled: Bool {
        didSet {
            UserDefaults.standard.set(torchBeatEnabled, forKey: Self.torchKey)
            if !torchBeatEnabled {
                AudioReactiveEffects.shared.clearTorch()
            }
        }
    }

    /// Continuous Core Haptics pulse — closest public stand-in for Apple Music haptics.
    @Published public var hapticMusicEnabled: Bool {
        didSet {
            UserDefaults.standard.set(hapticMusicEnabled, forKey: Self.hapticKey)
            if !hapticMusicEnabled {
                AudioReactiveEffects.shared.clearHaptics()
            }
        }
    }

    public init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.blobsKey) == nil {
            ambientBlobsEnabled = true
        } else {
            ambientBlobsEnabled = defaults.bool(forKey: Self.blobsKey)
        }
        torchBeatEnabled = defaults.bool(forKey: Self.torchKey)
        hapticMusicEnabled = defaults.bool(forKey: Self.hapticKey)
    }
}

public struct AudioAtmosphereMenu: View {
    @ObservedObject private var settings: AudioAtmosphereSettings

    public init(settings: AudioAtmosphereSettings) {
        self.settings = settings
    }

    public var body: some View {
        Menu {
            Toggle(isOn: $settings.ambientBlobsEnabled) {
                Label(L10n.text("audio.effect.blobs"), systemImage: "circle.hexagongrid.fill")
            }
            #if os(iOS)
            Toggle(isOn: $settings.torchBeatEnabled) {
                Label(L10n.text("audio.effect.torch"), systemImage: "flashlight.on.fill")
            }
            Toggle(isOn: $settings.hapticMusicEnabled) {
                Label(L10n.text("audio.effect.haptic"), systemImage: "waveform.path")
            }
            #endif
        } label: {
            Label(L10n.text("action.audio.settings"), systemImage: "slider.horizontal.3")
        }
    }
}

/// Drives torch + Core Haptics from the smoothed PCM peak (Speaker iOS).
@MainActor
public final class AudioReactiveEffects {
    public static let shared = AudioReactiveEffects()

    #if os(iOS)
    private var hapticEngine: CHHapticEngine?
    private var hapticPlayer: CHHapticAdvancedPatternPlayer?
    private var hapticsReady = false
    private var lastTorchLevel: Float = 0
    private var lastHapticIntensity: Float = 0
    #endif

    private init() {}

    public func apply(level: Double, settings: AudioAtmosphereSettings, isPlaying: Bool) {
        #if os(iOS)
        let active = isPlaying ? min(1, max(0, level)) : 0
        if settings.torchBeatEnabled {
            setTorch(level: active)
        } else {
            setTorch(level: 0)
        }
        if settings.hapticMusicEnabled, isPlaying {
            updateHaptics(level: active)
        } else {
            stopHaptics()
        }
        #else
        _ = (level, settings, isPlaying)
        #endif
    }

    public func shutdown() {
        clearTorch()
        clearHaptics()
    }

    public func clearTorch() {
        #if os(iOS)
        setTorch(level: 0)
        #endif
    }

    public func clearHaptics() {
        #if os(iOS)
        stopHaptics()
        #endif
    }

    #if os(iOS)
    private func setTorch(level: Double) {
        let brightness = Float(min(1, max(0, level)))
        // Avoid spamming the torch driver on tiny changes.
        guard abs(brightness - lastTorchLevel) > 0.04 || (brightness == 0 && lastTorchLevel != 0) else {
            return
        }
        lastTorchLevel = brightness

        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch
        else {
            return
        }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if brightness < 0.05 {
                if device.torchMode != .off {
                    device.torchMode = .off
                }
            } else {
                try device.setTorchModeOn(level: max(0.1, brightness))
            }
        } catch {
            // Torch may be unavailable (thermal / in use) — ignore quietly.
        }
    }

    private func ensureHaptics() {
        guard !hapticsReady else { return }
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = true
            try engine.start()
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.2)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.25)
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [intensity, sharpness],
                relativeTime: 0,
                duration: 30
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            player.loopEnabled = true
            try player.start(atTime: 0)
            hapticEngine = engine
            hapticPlayer = player
            hapticsReady = true
            lastHapticIntensity = 0.2
        } catch {
            hapticsReady = false
        }
    }

    private func updateHaptics(level: Double) {
        ensureHaptics()
        guard let player = hapticPlayer else { return }
        let intensity = Float(min(1, max(0.05, level)))
        guard abs(intensity - lastHapticIntensity) > 0.03 else { return }
        lastHapticIntensity = intensity
        let sharpness = min(1, intensity * 0.65)
        do {
            try player.sendParameters(
                [
                    CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: intensity, relativeTime: 0),
                    CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: sharpness, relativeTime: 0)
                ],
                atTime: 0
            )
        } catch {
            // Engine may have reset; rebuild next frame.
            hapticsReady = false
            hapticPlayer = nil
            hapticEngine = nil
        }
    }

    private func stopHaptics() {
        if let player = hapticPlayer {
            try? player.stop(atTime: 0)
        }
        hapticPlayer = nil
        hapticEngine?.stop(completionHandler: { _ in })
        hapticEngine = nil
        hapticsReady = false
        lastHapticIntensity = 0
    }
    #endif
}
