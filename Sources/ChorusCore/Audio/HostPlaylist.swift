import Foundation
import UniformTypeIdentifiers

/// One row in the Host local-music playlist.
public struct PlaylistItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    /// Security-scoped bookmark for a file on disk; nil for in-memory demo tracks.
    public var bookmark: Data?
    public var inlineTrack: DecodedTrack?

    public init(
        id: UUID = UUID(),
        title: String,
        bookmark: Data? = nil,
        inlineTrack: DecodedTrack? = nil
    ) {
        self.id = id
        self.title = title
        self.bookmark = bookmark
        self.inlineTrack = inlineTrack
    }

    public static func == (lhs: PlaylistItem, rhs: PlaylistItem) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
public final class HostPlaylist: ObservableObject {
    @Published public private(set) var items: [PlaylistItem] = []
    @Published public private(set) var currentIndex: Int?
    @Published public var autoAdvance = true
    @Published public private(set) var isLoading = false
    @Published public private(set) var loadMessage: String?

    private var folderAccessURL: URL?

    public init() {}

    public var currentItem: PlaylistItem? {
        guard let currentIndex, items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    public var hasPrevious: Bool {
        guard let currentIndex else { return !items.isEmpty }
        return currentIndex > 0
    }

    public var hasNext: Bool {
        guard let currentIndex else { return !items.isEmpty }
        return currentIndex + 1 < items.count
    }

    public func clear() {
        stopFolderAccess()
        items = []
        currentIndex = nil
        loadMessage = nil
    }

    public func remove(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: index)
        if let currentIndex {
            if index < currentIndex {
                self.currentIndex = currentIndex - 1
            } else if index == currentIndex {
                self.currentIndex = items.isEmpty ? nil : min(index, items.count - 1)
            }
        }
    }

    public func select(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        currentIndex = index
    }

    public func select(index: Int) {
        guard items.indices.contains(index) else { return }
        currentIndex = index
    }

    public func moveToPrevious() -> PlaylistItem? {
        guard !items.isEmpty else { return nil }
        if let currentIndex, currentIndex > 0 {
            self.currentIndex = currentIndex - 1
        } else {
            currentIndex = 0
        }
        return currentItem
    }

    public func moveToNext() -> PlaylistItem? {
        guard !items.isEmpty else { return nil }
        if let currentIndex, currentIndex + 1 < items.count {
            self.currentIndex = currentIndex + 1
        } else if currentIndex == nil {
            currentIndex = 0
        } else {
            return nil
        }
        return currentItem
    }

    public func appendDemoTone() {
        let track = DemoTone.makeTrack()
        let item = PlaylistItem(title: track.title, inlineTrack: track)
        items.append(item)
        if currentIndex == nil {
            currentIndex = items.count - 1
        }
    }

    public func importAudioURLs(_ urls: [URL]) {
        var added = 0
        for url in urls {
            guard Self.isSupportedAudio(url) else { continue }
            do {
                let bookmark = try Self.makeBookmark(for: url)
                let title = url.deletingPathExtension().lastPathComponent
                items.append(PlaylistItem(title: title, bookmark: bookmark))
                added += 1
            } catch {
                continue
            }
        }
        if currentIndex == nil, !items.isEmpty {
            currentIndex = 0
        }
        loadMessage = added > 0
            ? L10n.format("playlist.added.files", added)
            : L10n.text("playlist.added.none")
    }

    public func importFolder(_ folderURL: URL) {
        stopFolderAccess()
        let accessing = folderURL.startAccessingSecurityScopedResource()
        if accessing {
            folderAccessURL = folderURL
        }
        isLoading = true
        loadMessage = L10n.text("playlist.loading.folder")

        let urls = AudioFileLoader.audioURLs(in: folderURL)
        var added = 0
        for url in urls {
            do {
                let bookmark = try Self.makeBookmark(for: url)
                let title = url.deletingPathExtension().lastPathComponent
                items.append(PlaylistItem(title: title, bookmark: bookmark))
                added += 1
            } catch {
                continue
            }
        }
        if currentIndex == nil, !items.isEmpty {
            currentIndex = 0
        }
        isLoading = false
        loadMessage = L10n.format("playlist.added.folder", folderURL.lastPathComponent, added)
    }

    /// Resolve PCM for the current (or given) item. Caller should play immediately.
    public func loadTrack(for item: PlaylistItem? = nil) throws -> DecodedTrack {
        let target = item ?? currentItem
        guard let target else {
            throw PlaylistError.empty
        }
        if let inline = target.inlineTrack {
            return inline
        }
        guard let bookmark = target.bookmark else {
            throw PlaylistError.missingFile
        }
        let url = try Self.resolveBookmark(bookmark)
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try AudioFileLoader.load(url: url)
    }

    private func stopFolderAccess() {
        folderAccessURL?.stopAccessingSecurityScopedResource()
        folderAccessURL = nil
    }

    public static func isSupportedAudio(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return AudioFileLoader.supportedExtensions.contains(ext)
    }

    /// `.withSecurityScope` exists only on macOS (Host). ChorusCore also builds for iOS.
    private static func makeBookmark(for url: URL) throws -> Data {
        #if os(macOS)
        return try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        return try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif
    }

    private static func resolveBookmark(_ data: Data) throws -> URL {
        var stale = false
        #if os(macOS)
        return try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        #else
        return try URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        #endif
    }

    public enum PlaylistError: Error {
        case empty
        case missingFile
    }
}

public extension AudioFileLoader {
    static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "aiff", "aif", "caf", "flac", "mp4", "alac"
    ]

    /// Non-recursive listing of supported audio files in a directory.
    static func audioURLs(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard
            let entries = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }
        return entries
            .filter { url in
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                    return false
                }
                return supportedExtensions.contains(url.pathExtension.lowercased())
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
