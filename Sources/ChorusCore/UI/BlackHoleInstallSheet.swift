import AppKit
import SwiftUI

#if os(macOS)
/// Prompt when unified system-audio streaming needs BlackHole 2ch.
public struct BlackHoleInstallSheet: View {
    public static let downloadURL = URL(string: "https://existential.audio/downloads/BlackHole2ch-0.7.1.pkg")!
    public static let websiteURL = URL(string: "https://existential.audio/blackhole/")!

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var isDownloading = false
    @State private var progress: Double = 0
    @State private var errorText: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "waveform.badge.exclamationmark")
                    .font(.system(size: 40, weight: .medium, design: .rounded))
                    .foregroundStyle(GlassTheme.accent)

                Text(L10n.text("blackhole.sheet.title"))
                    .font(.system(.title2, design: .rounded).weight(.bold))

                Text(L10n.text("blackhole.sheet.body"))
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(L10n.text("blackhole.sheet.hint"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)

                if isDownloading {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: progress, total: 1)
                            .tint(GlassTheme.accent)
                        Text(L10n.text("blackhole.sheet.downloading"))
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorText {
                    Text(errorText)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.red.opacity(0.85))
                }

                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    Button(L10n.text("action.close")) {
                        dismiss()
                    }
                    .buttonStyle(GlassSecondaryButtonStyle())
                    .disabled(isDownloading)

                    Button {
                        Task { await downloadAndInstall() }
                    } label: {
                        if isDownloading {
                            ProgressView()
                                .controlSize(.small)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(L10n.text("blackhole.sheet.install"))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(GlassPrimaryButtonStyle(enabled: !isDownloading))
                    .disabled(isDownloading)
                }

                Button(L10n.text("blackhole.sheet.website")) {
                    openURL(Self.websiteURL)
                }
                .buttonStyle(.plain)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(GlassTheme.accent)
                .frame(maxWidth: .infinity)
                .disabled(isDownloading)
            }
            .padding(24)
            .frame(minWidth: 420, idealWidth: 460, minHeight: 380, idealHeight: 420)
            .navigationTitle(L10n.text("blackhole.sheet.nav"))
        }
    }

    @MainActor
    private func downloadAndInstall() async {
        errorText = nil
        isDownloading = true
        progress = 0
        defer { isDownloading = false }

        do {
            let fileURL = try await BlackHoleInstaller.downloadPackage(
                from: Self.downloadURL
            ) { fraction in
                Task { @MainActor in
                    progress = fraction
                }
            }
            progress = 1
            NSWorkspace.shared.open(fileURL)
            dismiss()
        } catch {
            errorText = L10n.format("blackhole.sheet.error", error.localizedDescription)
        }
    }
}

/// Downloads the BlackHole installer pkg into a temp folder.
enum BlackHoleInstaller {
    static func downloadPackage(
        from remoteURL: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        onProgress(0.05)
        let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        onProgress(0.85)

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChorusBlackHole", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let filename = remoteURL.lastPathComponent.isEmpty
            ? "BlackHole2ch.pkg"
            : remoteURL.lastPathComponent
        let destination = folder.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        onProgress(1)
        return destination
    }
}
#endif
