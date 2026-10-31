import Foundation

/// Exports and restores addons, profiles, libraries, Home layouts and settings.
/// Account sign-ins and downloaded files are never included.
enum Backup {
    private static let includedPrefixes = ["lumen.", "set.", "profiles."]
    private static let excludedKeys: Set<String> = ["lumen.downloads.v1", "set.installId"]
    private static let excludedPrefixes = ["kc.fallback.", "trakt.", "nuvio.", "stremio."]

    private static func isIncluded(_ key: String) -> Bool {
        guard includedPrefixes.contains(where: { key.hasPrefix($0) }) else { return false }
        if excludedKeys.contains(key) { return false }
        return !excludedPrefixes.contains { key.hasPrefix($0) }
    }

    /// Writes a backup into Documents/Backups (visible in the Files app) and returns its URL.
    static func export() throws -> URL {
        var values: [String: Any] = [:]
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() where isIncluded(key) {
            values[key] = value
        }
        let payload: [String: Any] = [
            "app": "Lumen",
            "format": 1,
            "created": Date(),
            "version": (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "",
            "values": values,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HHmm"
        let url = dir.appendingPathComponent("Lumen Backup \(f.string(from: Date())).plist")
        try data.write(to: url, options: .atomic)
        return url
    }

    struct Summary {
        let addons: Int
        let profiles: Int
    }

    /// Replaces current data with the backup's, then reloads everything.
    static func restore(from url: URL) throws -> Summary {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard let payload = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              (payload["app"] as? String) == "Lumen",
              let values = payload["values"] as? [String: Any] else {
            throw HTTPError(message: "This file isn't a Lumen backup.")
        }

        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where isIncluded(key) {
            defaults.removeObject(forKey: key)
        }
        for (key, value) in values where isIncluded(key) {
            defaults.set(value, forKey: key)
        }

        ProfileStore.shared.reload()
        AddonStore.shared.reload()
        LibraryStore.shared.reload()
        let nc = NotificationCenter.default
        nc.post(name: .profileChanged, object: nil)
        nc.post(name: .homeLayoutChanged, object: nil)
        nc.post(name: .settingsChanged, object: nil)
        return Summary(addons: AddonStore.shared.addons.count, profiles: ProfileStore.shared.profiles.count)
    }
}
