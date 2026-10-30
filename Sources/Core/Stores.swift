import Foundation

extension Notification.Name {
    static let addonsChanged = Notification.Name("lumen.addonsChanged")
    static let libraryChanged = Notification.Name("lumen.libraryChanged")
}

// MARK: - Addons

final class AddonStore {
    static let shared = AddonStore()

    /// Official Stremio addons for metadata and subtitles. No stream sources are bundled;
    /// users install the stream addons they want.
    static let defaultAddonURLs = [
        "https://v3-cinemeta.strem.io/manifest.json",
        "https://opensubtitles-v3.strem.io/manifest.json",
    ]

    private(set) var addons: [Addon] = []
    private let storageKey = "lumen.addons.v1"
    private let seededKey = "lumen.addonsSeeded.v1"

    private init() { load() }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let arr = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [[String: Any]] else { return }
        addons = arr.compactMap { d in
            guard let url = d["transportUrl"] as? String,
                  let raw = d["manifest"] as? [String: Any],
                  let m = Manifest(json: raw) else { return nil }
            return Addon(transportUrl: url, manifest: m)
        }
    }

    private func save() {
        let arr: [[String: Any]] = addons.map { ["transportUrl": $0.transportUrl, "manifest": $0.manifest.raw] }
        if let data = try? JSONSerialization.data(withJSONObject: arr, options: []) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        NotificationCenter.default.post(name: .addonsChanged, object: nil)
    }

    func add(_ addon: Addon) {
        if let i = addons.firstIndex(where: { $0.manifest.id == addon.manifest.id }) {
            addons[i] = addon
        } else {
            addons.append(addon)
        }
        save()
    }

    func remove(at index: Int) {
        guard addons.indices.contains(index) else { return }
        addons.remove(at: index)
        save()
    }

    func move(from: Int, to: Int) {
        guard addons.indices.contains(from), addons.indices.contains(to) else { return }
        let a = addons.remove(at: from)
        addons.insert(a, at: to)
        save()
    }

    func addons(supporting resource: String, type: String, id: String?) -> [Addon] {
        addons.filter { $0.manifest.supports(resource, type: type, id: id) }
    }

    func seedDefaultsIfNeeded(completion: @escaping () -> Void) {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { completion(); return }
        installDefaults { ok in
            if ok { UserDefaults.standard.set(true, forKey: self.seededKey) }
            completion()
        }
    }

    /// Installs any default addon that's missing. Calls back with true if all were fetched.
    func installDefaults(completion: @escaping (Bool) -> Void) {
        let urls = AddonStore.defaultAddonURLs
        var fetched: [Int: Addon] = [:]
        let group = DispatchGroup()
        for (i, url) in urls.enumerated() {
            group.enter()
            StremioAPI.shared.fetchAddon(url) { result in
                if case .success(let a) = result { fetched[i] = a }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            var changed = false
            for i in fetched.keys.sorted() {
                guard let a = fetched[i] else { continue }
                if !self.addons.contains(where: { $0.manifest.id == a.manifest.id }) {
                    self.addons.insert(a, at: min(i, self.addons.count))
                    changed = true
                }
            }
            if changed { self.save() }
            completion(fetched.count == urls.count)
        }
    }
}

// MARK: - Library & progress

struct LibraryItem: Codable {
    let ref: MediaRef
    let addedAt: Date
}

struct VideoProgress: Codable {
    let position: Double
    let duration: Double
    var fraction: Double { duration > 0 ? min(1, position / duration) : 0 }
}

struct WatchState: Codable {
    let ref: MediaRef
    let videoId: String
    let videoLabel: String?
    let position: Double
    let duration: Double
    let updatedAt: Date
    var progress: Double { duration > 0 ? min(1, position / duration) : 0 }
}

private struct LibraryData: Codable {
    var items: [LibraryItem] = []
    var watching: [String: WatchState] = [:]   // keyed by meta id
    var progress: [String: VideoProgress] = [:] // keyed by video id
    var watched: Set<String> = []               // video ids
}

final class LibraryStore {
    static let shared = LibraryStore()

    private var data: LibraryData
    private let storageKey = "lumen.library.v1"

    private init() {
        if let raw = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(LibraryData.self, from: raw) {
            data = decoded
        } else {
            data = LibraryData()
        }
    }

    private func save() {
        if let raw = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(raw, forKey: storageKey)
        }
        NotificationCenter.default.post(name: .libraryChanged, object: nil)
    }

    // Library

    var items: [LibraryItem] { data.items.sorted { $0.addedAt > $1.addedAt } }

    func contains(_ id: String) -> Bool { data.items.contains { $0.ref.id == id } }

    func toggle(_ ref: MediaRef) {
        if let i = data.items.firstIndex(where: { $0.ref.id == ref.id }) {
            data.items.remove(at: i)
        } else {
            data.items.append(LibraryItem(ref: ref, addedAt: Date()))
        }
        save()
    }

    func removeFromLibrary(_ id: String) {
        data.items.removeAll { $0.ref.id == id }
        save()
    }

    // Progress

    func continueWatching() -> [WatchState] {
        data.watching.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    func watchState(for metaId: String) -> WatchState? { data.watching[metaId] }

    func progress(for videoId: String) -> VideoProgress? { data.progress[videoId] }

    func position(for videoId: String) -> Double { data.progress[videoId]?.position ?? 0 }

    func isWatched(_ videoId: String) -> Bool { data.watched.contains(videoId) }

    func updateProgress(ref: MediaRef, videoId: String, label: String?, position: Double, duration: Double) {
        if duration > 0 && position / duration >= 0.92 {
            data.progress[videoId] = nil
            data.watched.insert(videoId)
            if data.watching[ref.id]?.videoId == videoId { data.watching[ref.id] = nil }
        } else if position >= 15 {
            data.progress[videoId] = VideoProgress(position: position, duration: duration)
            data.watching[ref.id] = WatchState(ref: ref, videoId: videoId, videoLabel: label,
                                               position: position, duration: duration, updatedAt: Date())
        } else {
            return
        }
        save()
    }

    func removeFromContinue(_ metaId: String) {
        data.watching[metaId] = nil
        save()
    }
}
