import Foundation

enum AccountHelpers {
    /// Poster for an IMDb id from Stremio's public image service.
    static func posterURL(forImdb id: String) -> String? {
        id.hasPrefix("tt") ? "https://images.metahub.space/poster/medium/\(id)/img" : nil
    }

    /// "tt123:1:2" -> (1, 2)
    static func seasonEpisode(from videoId: String) -> (Int, Int)? {
        let parts = videoId.split(separator: ":")
        guard parts.count >= 3, let s = Int(parts[parts.count - 2]), let e = Int(parts[parts.count - 1]) else { return nil }
        return (s, e)
    }

    static func episodeLabel(_ videoId: String) -> String? {
        seasonEpisode(from: videoId).map { "S\($0.0)E\($0.1)" }
    }

    static func parseISODate(_ v: Any?) -> Date? { JSON.date(v) }
}

/// Stremio account: sign in, then import the addon collection and library.
final class StremioAccount {
    static let shared = StremioAccount()
    private let base = "https://api.strem.io/api/"

    private init() {}

    var authKey: String? { Keychain.get("stremio.authKey") }
    var email: String? { UserDefaults.standard.string(forKey: "stremio.email") }
    var isSignedIn: Bool { authKey != nil }

    private func call(_ method: String, _ body: [String: Any],
                      completion: @escaping (Result<Any, Error>) -> Void) {
        guard let url = URL(string: base + method) else { return }
        HTTP.request(url, method: "POST", json: body) { result in
            switch result {
            case .failure(let e):
                completion(.failure(e))
            case .success(let r):
                if let err = r.dict?["error"] as? [String: Any] {
                    completion(.failure(HTTPError(message: (err["message"] as? String) ?? "Stremio returned an error.")))
                } else if let res = r.dict?["result"] {
                    completion(.success(res))
                } else {
                    completion(.failure(HTTPError(message: r.errorMessage)))
                }
            }
        }
    }

    func signIn(email: String, password: String, completion: @escaping (Error?) -> Void) {
        call("login", ["type": "Login", "email": email, "password": password, "facebook": false]) { result in
            switch result {
            case .success(let res):
                guard let key = (res as? [String: Any])?["authKey"] as? String else {
                    completion(HTTPError(message: "Stremio didn't return a session."))
                    return
                }
                Keychain.set(key, for: "stremio.authKey")
                UserDefaults.standard.set(email, forKey: "stremio.email")
                NotificationCenter.default.post(name: .accountsChanged, object: nil)
                completion(nil)
            case .failure(let e):
                completion(e)
            }
        }
    }

    func signOut() {
        if let key = authKey { call("logout", ["type": "Logout", "authKey": key]) { _ in } }
        Keychain.set(nil, for: "stremio.authKey")
        UserDefaults.standard.removeObject(forKey: "stremio.email")
        NotificationCenter.default.post(name: .accountsChanged, object: nil)
    }

    /// Installs every addon in the account's collection that isn't installed yet.
    func importAddons(completion: @escaping (Result<Int, Error>) -> Void) {
        guard let key = authKey else { completion(.failure(HTTPError(message: "Not signed in."))); return }
        call("addonCollectionGet", ["type": "AddonCollectionGet", "authKey": key, "update": true]) { result in
            switch result {
            case .failure(let e):
                completion(.failure(e))
            case .success(let res):
                let list = JSON.dicts((res as? [String: Any])?["addons"])
                let addons: [Addon] = list.compactMap { d in
                    guard let url = JSON.string(d["transportUrl"]),
                          let normalized = StremioAPI.normalizeManifestURL(url),
                          let m = JSON.dict(d["manifest"]).flatMap(Manifest.init(json:)) else { return nil }
                    return Addon(transportUrl: normalized, manifest: m)
                }
                completion(.success(AddonStore.shared.merge(addons)))
            }
        }
    }

    /// Imports saved titles and in-progress playback.
    func importLibrary(completion: @escaping (Result<Int, Error>) -> Void) {
        guard let key = authKey else { completion(.failure(HTTPError(message: "Not signed in."))); return }
        call("datastoreGet", ["authKey": key, "collection": "libraryItem", "ids": [], "all": true]) { result in
            switch result {
            case .failure(let e):
                completion(.failure(e))
            case .success(let res):
                var items: [LibraryItem] = []
                var progress: [ImportedProgress] = []
                for d in JSON.dicts(res) {
                    guard let id = JSON.string(d["_id"]), let type = JSON.string(d["type"]),
                          !JSON.bool(d["removed"]) || JSON.dict(d["state"]) != nil else { continue }
                    let ref = MediaRef(id: id, type: type, name: JSON.string(d["name"]) ?? "",
                                       poster: JSON.string(d["poster"]) ?? AccountHelpers.posterURL(forImdb: id))
                    if !JSON.bool(d["removed"]) && !JSON.bool(d["temp"]) {
                        let added = AccountHelpers.parseISODate(d["_ctime"]) ?? Date()
                        items.append(LibraryItem(ref: ref, addedAt: added))
                    }
                    if let state = JSON.dict(d["state"]) {
                        let offset = Double(JSON.int(state["timeOffset"]) ?? 0) / 1000
                        let duration = Double(JSON.int(state["duration"]) ?? 0) / 1000
                        guard offset > 0, duration > 0 else { continue }
                        let videoId = JSON.string(state["video_id"]) ?? id
                        progress.append(ImportedProgress(
                            ref: ref, videoId: videoId, label: AccountHelpers.episodeLabel(videoId),
                            position: offset, duration: duration, isFraction: false,
                            updatedAt: AccountHelpers.parseISODate(state["lastWatched"]) ?? Date.distantPast))
                    }
                }
                let a = LibraryStore.shared.importLibrary(items)
                let b = LibraryStore.shared.importProgress(progress)
                completion(.success(a + b))
            }
        }
    }
}
