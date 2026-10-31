import Foundation

extension Notification.Name {
    static let profileChanged = Notification.Name("lumen.profileChanged")
    static let homeLayoutChanged = Notification.Name("lumen.homeLayoutChanged")
}

struct UserProfile: Codable, Equatable {
    let id: String
    var name: String
    var colorIndex: Int
    /// Whether this profile's watching and library changes sync to connected accounts.
    var syncAccounts: Bool

    var initial: String { String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }
}

/// Profiles each have their own library, progress, watched marks and home layout.
/// Addons, settings and accounts are shared.
final class ProfileStore {
    static let shared = ProfileStore()
    static let defaultId = "default"

    private let storageKey = "lumen.profiles.v1"
    private let currentKey = "lumen.currentProfile.v1"
    private(set) var profiles: [UserProfile] = []
    private(set) var currentId = ProfileStore.defaultId

    private init() { reload() }

    func reload() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([UserProfile].self, from: data), !saved.isEmpty {
            profiles = saved
        } else {
            profiles = [UserProfile(id: ProfileStore.defaultId, name: "Me", colorIndex: 0, syncAccounts: true)]
        }
        let saved = UserDefaults.standard.string(forKey: currentKey) ?? ProfileStore.defaultId
        currentId = profiles.contains { $0.id == saved } ? saved : profiles[0].id
    }

    var current: UserProfile { profiles.first { $0.id == currentId } ?? profiles[0] }

    var askOnLaunch: Bool {
        get { UserDefaults.standard.object(forKey: "profiles.askOnLaunch") == nil
            ? true : UserDefaults.standard.bool(forKey: "profiles.askOnLaunch") }
        set { UserDefaults.standard.set(newValue, forKey: "profiles.askOnLaunch") }
    }

    /// Storage key for per-profile data. The first profile keeps the original key so
    /// data from before profiles existed carries over.
    func key(_ base: String, for id: String? = nil) -> String {
        let pid = id ?? currentId
        return pid == ProfileStore.defaultId ? base : "\(base).\(pid)"
    }

    static let perProfileKeys = ["lumen.library.v1", "lumen.homeLayout.v1"]

    private func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    @discardableResult
    func add(name: String, colorIndex: Int) -> UserProfile {
        let p = UserProfile(id: UUID().uuidString.lowercased(), name: name, colorIndex: colorIndex, syncAccounts: false)
        profiles.append(p)
        save()
        NotificationCenter.default.post(name: .profileChanged, object: nil)
        return p
    }

    func update(_ profile: UserProfile) {
        guard let i = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[i] = profile
        save()
        NotificationCenter.default.post(name: .profileChanged, object: nil)
    }

    func delete(_ id: String) {
        guard profiles.count > 1, let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        for base in ProfileStore.perProfileKeys {
            UserDefaults.standard.removeObject(forKey: key(base, for: id))
        }
        profiles.remove(at: i)
        save()
        if currentId == id {
            switchTo(profiles[0].id)
        } else {
            NotificationCenter.default.post(name: .profileChanged, object: nil)
        }
    }

    func switchTo(_ id: String) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        currentId = id
        UserDefaults.standard.set(id, forKey: currentKey)
        LibraryStore.shared.reload()
        NotificationCenter.default.post(name: .profileChanged, object: nil)
        NotificationCenter.default.post(name: .homeLayoutChanged, object: nil)
        AccountSync.pullProgress()
    }
}

// MARK: - Home layout

/// Per-profile order and visibility of Home rows.
final class HomeLayout {
    static let shared = HomeLayout()
    private struct Stored: Codable {
        var order: [String] = []
        var hidden: [String] = []
    }

    private init() {}

    private var storageKey: String { ProfileStore.shared.key("lumen.homeLayout.v1") }

    private var stored: Stored {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let s = try? JSONDecoder().decode(Stored.self, from: data) else { return Stored() }
        return s
    }

    var hidden: Set<String> { Set(stored.hidden) }

    /// Sorts rows by the saved order (new rows keep their natural position at the end).
    func ordered<T>(_ rows: [T], key: (T) -> String) -> [T] {
        let order = stored.order
        let rank = Dictionary(order.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { a, _ in a })
        return rows.enumerated().sorted { a, b in
            let ra = rank[key(a.element)] ?? (order.count + a.offset)
            let rb = rank[key(b.element)] ?? (order.count + b.offset)
            return ra < rb
        }.map { $0.element }
    }

    func save(order: [String], hidden: Set<String>) {
        let s = Stored(order: order, hidden: Array(hidden).sorted())
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        NotificationCenter.default.post(name: .homeLayoutChanged, object: nil)
    }

    func reset() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        NotificationCenter.default.post(name: .homeLayoutChanged, object: nil)
    }
}

// MARK: - Episodes

enum Episodes {
    /// Episodes in watch order: regular seasons first, specials last.
    static func ordered(_ videos: [Video]) -> [Video] {
        videos.sorted { a, b in
            let sa = a.season ?? 0, sb = b.season ?? 0
            if (sa == 0) != (sb == 0) { return sb == 0 }
            if sa != sb { return sa < sb }
            if (a.episode ?? 0) != (b.episode ?? 0) { return (a.episode ?? 0) < (b.episode ?? 0) }
            return (a.released ?? .distantPast) < (b.released ?? .distantPast)
        }
    }

    /// The episode after `videoId`, not crossing from regular seasons into specials.
    static func next(after videoId: String, in videos: [Video]) -> Video? {
        let list = ordered(videos)
        guard let i = list.firstIndex(where: { $0.id == videoId }) else { return nil }
        let currentSeason = list[i].season ?? 0
        guard let candidate = list.dropFirst(i + 1).first else { return nil }
        if currentSeason > 0 && (candidate.season ?? 0) == 0 { return nil }
        if let released = candidate.released, released > Date() { return nil }
        return candidate
    }
}
