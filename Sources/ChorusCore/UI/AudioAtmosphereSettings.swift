import Combine
import Foundation
import SwiftUI

/// Shared Host / Speaker preference for music-reactive background motion.
@MainActor
public final class AudioAtmosphereSettings: ObservableObject {
    private static let blobsKey = "chorus.audio.ambientBlobs"

    /// Soft background blobs pulse with the mix (“音乐律动”).
    @Published public var musicPulseEnabled: Bool {
        didSet { UserDefaults.standard.set(musicPulseEnabled, forKey: Self.blobsKey) }
    }

    public init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.blobsKey) == nil {
            musicPulseEnabled = true
        } else {
            musicPulseEnabled = defaults.bool(forKey: Self.blobsKey)
        }
    }
}

public struct AudioAtmosphereMenu: View {
    @ObservedObject private var settings: AudioAtmosphereSettings

    public init(settings: AudioAtmosphereSettings) {
        self.settings = settings
    }

    public var body: some View {
        Menu {
            Toggle(isOn: $settings.musicPulseEnabled) {
                Label(L10n.text("audio.effect.pulse"), systemImage: "waveform.circle.fill")
            }
        } label: {
            Label(L10n.text("action.audio.settings"), systemImage: "slider.horizontal.3")
        }
    }
}
