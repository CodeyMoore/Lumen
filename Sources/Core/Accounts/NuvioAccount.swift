import Foundation

/// Nuvio account sync. Nuvio servers are Supabase backends; a server publishes its address and
/// public app key at https://<server>/.well-known/nuvio, which is how Nuvio itself connects to
/// self-hosted servers.
final class NuvioAccount {
    static let shared = NuvioAccount()
    private let defaults = UserDefaults.standard

    private init() {}

    struct Server: Codable {
        let backendUrl: String
        let publishableKey: String
        let label: String
    }

    struct Profile {
        let index: Int
        let name: String
    }

    var server: Server? {
        get {
            guard let data = defaults.data(forKey: "nuvio.server") else { return nil }
            return try? JSONDecoder().decode(Server.self, from: data)
        }
        set {
            defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "nuvio.server")
            NotificationCenter.default.post(name: .accountsChanged, object: nil)
        }
    }

    var email: String? { defaults.string(forKey: "nuvio.email") }
    var profileIndex: Int { max(1, defaults.integer(forKey: "nuvio.profile")) }
    var profileName: String? { defaults.string(forKey: "nuvio.profileName") }
    var isSignedIn: Bool { server != nil && Keychain.get("nuvio.access") != nil }

    private var accessToken: String? { Keychain.get("nuvio.access") }
    private var refreshToken: String? { Keychain.get("nuvio.refresh") }
    private var expiresAt: Double { defaults.double(forKey: "nuvio.expiresAt") }

    // MARK: Server discovery

    func discover(_ input: String, completion: @escaping (Result<Server, Error>) -> Void) {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { completion(.failure(HTTPError(message: "Enter a server address."))); return }
        if !s.contains("://") { s = "https://" + s }
        guard let parsed = URL(string: s), let host = parsed.host else {
            completion(.failure(HTTPError(message: "That isn't a valid address.")))
            return
        }
        let port = parsed.port.map { ":\($0)" } ?? ""
        var path = parsed.path
        if path.hasSuffix("/.well-known/nuvio") { path.removeLast("/.well-known/nuvio".count) }
        while path.hasSuffix("/") { path.removeLast() }
        guard let url = URL(string: "\(parsed.scheme ?? "https")://\(host)\(port)\(path)/.well-known/nuvio") else { return }

        HTTP.request(url) { result in
            switch result {
            case .failure:
                completion(.failure(HTTPError(message: "Couldn't reach that server.")))
            case .success(let r):
                guard r.ok, let d = r.dict,
                      (d["service"] as? String)?.lowercased() == "nuvio",
                      let backend = JSON.string(d["backend_url"]),
                      let key = JSON.string(d["publishable_key"]) else {
                    completion(.failure(HTTPError(message:
                        "This server doesn't publish Nuvio sign-in details. Official Nuvio accounts can't be used from other apps; this works with self-hosted Nuvio servers.")))
                    return
                }
                let caps = JSON.dict(d["capabilities"])
                if caps != nil && !JSON.bool(caps?["email_password_auth"]) {
                    completion(.failure(HTTPError(message: "This server doesn't allow email sign-in.")))
                    return
                }
                var b = backend
                while b.hasSuffix("/") { b.removeLast() }
                completion(.success(Server(backendUrl: b, publishableKey: key, label: host)))
            }
        }
    }

    // MARK: Auth

    private func storeSession(_ d: [String: Any]) {
        Keychain.set(d["access_token"] as? String, for: "nuvio.access")
        if let r = d["refresh_token"] as? String { Keychain.set(r, for: "nuvio.refresh") }
        let expires = (d["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        defaults.set(Date().timeIntervalSince1970 + expires, forKey: "nuvio.expiresAt")
    }

    func signIn(server: Server, email: String, password: String, completion: @escaping (Error?) -> Void) {
        guard let url = URL(string: "\(server.backendUrl)/auth/v1/token?grant_type=password") else { return }
        HTTP.request(url, method: "POST", headers: ["apikey": server.publishableKey],
                     json: ["email": email, "password": password]) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let e):
                completion(e)
            case .success(let r):
                guard r.ok, let d = r.dict, d["access_token"] != nil else {
                    completion(HTTPError(message: r.status == 400 ? "Wrong email or password." : r.errorMessage))
                    return
                }
                self.storeSession(d)
                self.defaults.set(email, forKey: "nuvio.email")
                self.server = server
                completion(nil)
            }
        }
    }

    func signOut() {
        Keychain.set(nil, for: "nuvio.access")
        Keychain.set(nil, for: "nuvio.refresh")
        for k in ["nuvio.email", "nuvio.profile", "nuvio.profileName", "nuvio.expiresAt"] { defaults.removeObject(forKey: k) }
        server = nil
    }

    func selectProfile(_ p: Profile) {
        defaults.set(p.index, forKey: "nuvio.profile")
        defaults.set(p.name, forKey: "nuvio.profileName")
        NotificationCenter.default.post(name: .accountsChanged, object: nil)
    }

    private func refreshIfNeeded(_ completion: @escaping (Bool) -> Void) {
        guard let server = server, accessToken != nil else { completion(false); return }
        guard Date().timeIntervalSince1970 > expiresAt - 120 else { completion(true); return }
        guard let refresh = refreshToken,
              let url = URL(string: "\(server.backendUrl)/auth/v1/token?grant_type=refresh_token") else {
            completion(false); return
        }
        HTTP.request(url, method: "POST", headers: ["apikey": server.publishableKey],
                     json: ["refresh_token": refresh]) { [weak self] result in
            if case .success(let r) = result, r.ok, let d = r.dict {
                self?.storeSession(d)
                completion(true)
            } else {
                completion(false)
            }
        }
    }

    private func authorized(_ path: String, method: String = "GET", json: Any? = nil,
                            completion: @escaping (Result<HTTPResponse, Error>) -> Void) {
        refreshIfNeeded { [weak self] ok in
            guard let self = self, ok, let server = self.server, let token = self.accessToken,
                  let url = URL(string: server.backendUrl + path) else {
                completion(.failure(HTTPError(message: "Your Nuvio session expired. Sign in again.")))
                return
            }
            let headers = ["apikey": server.publishableKey, "Authorization": "Bearer \(token)"]
            HTTP.request(url, method: method, headers: headers, json: json) { result in
                if case .success(let r) = result, !r.ok {
                    completion(.failure(HTTPError(message: r.errorMessage)))
                } else {
                    completion(result)
                }
            }
        }
    }

    private func rpc(_ name: String, _ params: [String: Any], completion: @escaping (Result<Any?, Error>) -> Void) {
        authorized("/rest/v1/rpc/\(name)", method: "POST", json: params) { result in
            completion(result.map { $0.json })
        }
    }

    // MARK: Profiles

    func fetchProfiles(completion: @escaping (Result<[Profile], Error>) -> Void) {
        rpc("sync_pull_profiles", [:]) { result in
            completion(result.map { (json: Any?) -> [Profile] in
                JSON.dicts(json).compactMap { (d: [String: Any]) -> Profile? in
                    guard let i = JSON.int(d["profile_index"]) else { return nil }
                    return Profile(index: i, name: JSON.string(d["name"]) ?? "Profile \(i)")
                }.sorted { $0.index < $1.index }
            })
        }
    }

    // MARK: Import

    func importAddons(completion: @escaping (Result<Int, Error>) -> Void) {
        let path = "/rest/v1/addons?select=url,name,enabled,sort_order&profile_id=eq.\(profileIndex)&order=sort_order.asc"
        authorized(path) { result in
            switch result {
            case .failure(let e):
                completion(.failure(e))
            case .success(let r):
                let urls = JSON.dicts(r.json)
                    .filter { $0["enabled"] == nil || JSON.bool($0["enabled"]) }
                    .compactMap { JSON.string($0["url"]) }
                guard !urls.isEmpty else { completion(.success(0)); return }
                var fetched: [Int: Addon] = [:]
                let group = DispatchGroup()
                for (i, u) in urls.enumerated() {
                    group.enter()
                    StremioAPI.shared.fetchAddon(u) { res in
                        if case .success(let a) = res { fetched[i] = a }
                        group.leave()
                    }
                }
                group.notify(queue: .main) {
                    let ordered = fetched.keys.sorted().compactMap { fetched[$0] }
                    completion(.success(AddonStore.shared.merge(ordered)))
                }
            }
        }
    }

    func importLibrary(completion: @escaping (Result<Int, Error>) -> Void) {
        rpc("sync_pull_library", ["p_profile_id": profileIndex, "p_limit": 1000, "p_offset": 0]) { result in
            switch result {
            case .failure(let e):
                completion(.failure(e))
            case .success(let json):
                let items: [LibraryItem] = JSON.dicts(json).compactMap { d in
                    guard let id = JSON.string(d["content_id"]), let type = JSON.string(d["content_type"]) else { return nil }
                    let added = (d["added_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) } ?? Date()
                    let ref = MediaRef(id: id, type: type, name: JSON.string(d["name"]) ?? "",
                                       poster: JSON.string(d["poster"]) ?? AccountHelpers.posterURL(forImdb: id))
                    return LibraryItem(ref: ref, addedAt: added)
                }
                completion(.success(LibraryStore.shared.importLibrary(items)))
            }
        }
    }

    func importProgress(completion: @escaping (Result<Int, Error>) -> Void) {
        rpc("sync_pull_watch_progress", ["p_profile_id": profileIndex]) { result in
            switch result {
            case .failure(let e):
                completion(.failure(e))
            case .success(let json):
                let entries: [ImportedProgress] = JSON.dicts(json).compactMap { d in
                    guard let id = JSON.string(d["content_id"]), let type = JSON.string(d["content_type"]) else { return nil }
                    let videoId = JSON.string(d["video_id"]) ?? id
                    let pos = ((d["position"] as? NSNumber)?.doubleValue ?? 0) / 1000
                    let dur = ((d["duration"] as? NSNumber)?.doubleValue ?? 0) / 1000
                    let watched = ((d["last_watched"] as? NSNumber)?.doubleValue ?? 0) / 1000
                    var label: String?
                    if let s = JSON.int(d["season"]), let e = JSON.int(d["episode"]) { label = "S\(s)E\(e)" }
                    let ref = MediaRef(id: id, type: type, name: "", poster: AccountHelpers.posterURL(forImdb: id))
                    return ImportedProgress(ref: ref, videoId: videoId, label: label, position: pos, duration: dur,
                                            isFraction: false, updatedAt: Date(timeIntervalSince1970: watched))
                }
                completion(.success(LibraryStore.shared.importProgress(entries)))
            }
        }
    }

    // MARK: Push

    private func progressKey(_ contentId: String, _ videoId: String) -> (String, Int?, Int?) {
        if let se = AccountHelpers.seasonEpisode(from: videoId), videoId != contentId {
            return ("\(contentId)_s\(se.0)e\(se.1)", se.0, se.1)
        }
        return (contentId, nil, nil)
    }

    func pushProgress(ref: MediaRef, videoId: String, position: Double, duration: Double) {
        guard isSignedIn, duration > 0 else { return }
        let (key, season, episode) = progressKey(ref.id, videoId)
        var entry: [String: Any] = [
            "content_id": ref.id, "content_type": ref.type, "video_id": videoId,
            "position": Int64(position * 1000), "duration": Int64(duration * 1000),
            "last_watched": Int64(Date().timeIntervalSince1970 * 1000), "progress_key": key,
        ]
        if let s = season { entry["season"] = s }
        if let e = episode { entry["episode"] = e }
        rpc("sync_push_watch_progress", ["p_profile_id": profileIndex, "p_entries": [entry],
                                         "p_origin_client_id": AppSettings.shared.installationId]) { _ in }
    }

    func pushLibrary(_ ref: MediaRef, added: Bool) {
        guard isSignedIn else { return }
        if added {
            var item: [String: Any] = [
                "content_id": ref.id, "content_type": ref.type, "name": ref.name, "poster_shape": "POSTER",
                "added_at": Int64(Date().timeIntervalSince1970 * 1000),
            ]
            if let p = ref.poster { item["poster"] = p }
            rpc("sync_push_library_items", ["p_profile_id": profileIndex, "p_items": [item],
                                            "p_origin_client_id": AppSettings.shared.installationId]) { _ in }
        } else {
            rpc("sync_delete_library_items", ["p_profile_id": profileIndex,
                                              "p_keys": [["content_id": ref.id, "content_type": ref.type]],
                                              "p_origin_client_id": AppSettings.shared.installationId]) { _ in }
        }
    }
}

// MARK: - Coordinator

enum PlaybackEvent {
    case start, pause, stop
}

/// Routes local events to whichever accounts are signed in.
enum AccountSync {
    /// Only profiles that opted in send activity to connected accounts.
    static var enabled: Bool { ProfileStore.shared.current.syncAccounts }

    static func libraryChanged(_ ref: MediaRef, added: Bool) {
        guard enabled else { return }
        NuvioAccount.shared.pushLibrary(ref, added: added)
    }

    static func watched(_ ref: MediaRef, videoIds: [String], watched: Bool) {
        guard enabled else { return }
        TraktAccount.shared.setHistory(ref: ref, videoIds: videoIds, watched: watched)
    }

    static func playback(_ event: PlaybackEvent, ref: MediaRef, videoId: String, position: Double, duration: Double) {
        guard enabled else { return }
        let progress = duration > 0 ? position / duration * 100 : 0
        TraktAccount.shared.scrobble(event, ref: ref, videoId: videoId, progress: progress)
        if event != .start {
            NuvioAccount.shared.pushProgress(ref: ref, videoId: videoId, position: position, duration: duration)
        }
    }

    /// Quietly pulls progress from connected services (on launch and pull-to-refresh).
    static func pullProgress(completion: (() -> Void)? = nil) {
        guard enabled else { completion?(); return }
        let group = DispatchGroup()
        if TraktAccount.shared.isSignedIn {
            group.enter()
            TraktAccount.shared.importPlayback { _ in group.leave() }
        }
        if NuvioAccount.shared.isSignedIn {
            group.enter()
            NuvioAccount.shared.importProgress { _ in group.leave() }
        }
        group.notify(queue: .main) {
            fillMissingTitles()
            completion?()
        }
    }

    /// Imported progress sometimes lacks a title; look it up from the installed metadata addons.
    static func fillMissingTitles() {
        let missing = LibraryStore.shared.continueWatching().map { $0.ref }.filter { $0.name.isEmpty }
        for ref in missing.prefix(30) {
            guard let addon = AddonStore.shared.addons(supporting: "meta", type: ref.type, id: ref.id).first else { continue }
            StremioAPI.shared.meta(addon: addon, type: ref.type, id: ref.id) { result in
                if case .success(let m) = result {
                    LibraryStore.shared.updateDetails(MediaRef(id: ref.id, type: ref.type, name: m.name,
                                                               poster: m.poster ?? ref.poster))
                }
            }
        }
    }
}
