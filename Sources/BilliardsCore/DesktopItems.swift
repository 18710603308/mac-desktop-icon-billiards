import AppKit

public struct DesktopItem {
    public let name: String
    public let url: URL
    public let image: NSImage

    public var size: V2 {
        let s = image.size
        return V2(max(1, Double(s.width)), max(1, Double(s.height)))
    }
}

/// The real desktop population: `~/Desktop` plus the volumes Finder shows on the
/// desktop. Icons come from the workspace, so files keep their own artwork.
public enum DesktopItems {
    public static func load(demo: Bool) -> [DesktopItem] {
        demo ? demoItems() : realItems()
    }

    private static func realItems() -> [DesktopItem] {
        var urls: [URL] = []
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        if let desktop,
           let contents = try? FileManager.default.contentsOfDirectory(
               at: desktop, includingPropertiesForKeys: nil,
               options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            urls += contents
        }
        urls += desktopVolumes()
        return urls
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { item(for: $0) }
    }

    private static func desktopVolumes() -> [URL] {
        let finder = UserDefaults(suiteName: "com.apple.finder")
        let showHard = finder?.object(forKey: "ShowHardDrivesOnDesktop") as? Bool ?? false
        let showExternal = finder?.object(forKey: "ShowExternalDrivesOnDesktop") as? Bool ?? true
        let volumes = (try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Volumes"), includingPropertiesForKeys: [.volumeIsInternalKey],
            options: [.skipsHiddenFiles])) ?? []
        return volumes.filter { url in
            if url.resolvingSymlinksInPath().path == "/" { return false }
            let internalDisk = (try? url.resourceValues(forKeys: [.volumeIsInternalKey]))?
                .volumeIsInternal ?? false
            return internalDisk ? showHard : showExternal
        }
    }

    private static func demoItems() -> [DesktopItem] {
        let apps = (try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Applications"), includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []
        return apps
            .filter { $0.pathExtension == "app" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .prefix(21)
            .map { item(for: $0) }
    }

    private static func item(for url: URL) -> DesktopItem {
        DesktopItem(name: url.deletingPathExtension().lastPathComponent,
                    url: url,
                    image: NSWorkspace.shared.icon(forFile: url.path))
    }
}