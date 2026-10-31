import Foundation

/// Trakt sync using the device-code sign-in flow. Requires the user's own Trakt API app
/// (client ID and secret), since Trakt keys can't be shared publicly.
final class TraktAccount {
    static let shared = TraktAccount()
    private let api = "https://api.trakt.tv"
    private let defaults = UserDefaults.standard

    private init() {}

    struct DeviceCode {
        let deviceCode: String
        let userCode: String
        let verificationURL: String
        let expiresIn: Int
        let interval: Int
    }

    /// Lets the UI cancel an in-progress sign-in.
    final class PollHandle {
        fileprivate(set) var cancelled = false
        func cancel() { cancelled = true }
    }

    var clientId: String {
        get { defaults.string(forKey: "trakt.clientId") ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "trakt.clientId") }
    }

    var clientSecret: String {
        get { Keychain.get("trakt.clientSecret") ?? "" }
        set { Keychain.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), for: "trakt.clientSecret") }
    }

    var hasApp: Bool { !clientId.isEmpty && !clientSecret.isEmpty }
    var isSignedIn: Bool { Keychain.get("trakt.access") != nil }
    var username: String? { defaults.string(forKey: "trakt.username") }

    private var accessToken: String? { Keychain.get("trakt.access") }
    private var refreshToken: String? { Keychain.get("trakt.refresh") }
    private var expiresAt: Double { defaults.double(forKey: "trakt.expiresAt") }

    private func baseHeaders() -> [String: String] {
        ["trakt-api-version": "2", "trakt-api-key": clientId]
    }

    private func storeTokens(_ d: [String: Any]) {
        Keychain.set(d["access_token"] as? String, for: "trakt.access")
        if let r = d["refresh_token"] as? String { Keychain.set(r, for: "trakt.refresh") }
        let created = (d["created_at"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970
        let expires = (d["expires_in"] as? NSNumber)?.doubleValue ?? 86400 * 7
        defaults.set(created + expires, forKey: "trakt.expiresAt")
    }

    func signOut() {
        Keychain.set(nil, for: "trakt.access")
        Keychain.set(nil, for: "trakt.refresh")
        defaults.removeObject(forKey: "trakt.username")
        NotificationCenter.default.post(name: .accountsChanged, object: nil)
    }

    // MARK: Device sign-in

    func startDeviceAuth(completion: @escaping (Result<DeviceCode, Error>) -> Void) {
        guard hasApp, let url = URL(string: "\(api)/oauth/device/code") else {
            completion(.failure(HTTPError(message: "Add your Trakt app's Client ID and Secret first.")))
            return
        }
        HTTP.request(url, method: "POST", headers: baseHeaders(), json: ["client_id": clientId]) { result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let r):
                guard r.ok, let d = r.dict,
                      let device = d["device_code"] as? String, let user = d["user_code"] as? String else {
                    completion(.failure(HTTPError(message: r.status == 403 || r.status == 401
                        ? "Trakt rejected the Client ID. Check it in your Trakt app settings."
                        : r.errorMessage)))
                    return
                }
                completion(.success(DeviceCode(
                    deviceCode: device, userCode: user,
                    verificationURL: (d["verification_url"] as? String) ?? "https://trakt.tv/activate",
                    expiresIn: JSON.int(d["expires_in"]) ?? 600,
                    interval: max(1, JSON.int(d["interval"]) ?? 5))))
            }
        }
    }

    /// Polls until the user approves the code, it expires, or the handle is cancelled.
    func poll(_ code: DeviceCode, handle: PollHandle, completion: @escaping (Result<Void, Error>) -> Void) {
        let deadline = Date().addingTimeInterval(TimeInterval(code.expiresIn))
        var interval = Double(code.interval)

        func attempt() {
            guard !handle.cancelled else { return }
            guard Date() < deadline else {
                completion(.failure(HTTPError(message: "The code expired. Try connecting again.")))
                return
            }
            guard let url = URL(string: "\(api)/oauth/device/token") else { return }
            let body: [String: Any] = ["code": code.deviceCode, "client_id": clientId, "client_secret": clientSecret]
            HTTP.request(url, method: "POST", headers: baseHeaders(), json: body) { [weak self] result in
                guard let self = self, !handle.cancelled else { return }
                switch result {
                case .failure:
                    DispatchQueue.main.asyncAfter(deadline: .now() + interval) { attempt() }
                case .success(let r):
                    switch r.status {
                    case 200:
                        if let d = r.dict { self.storeTokens(d) }
                        self.fetchUsername()
                        NotificationCenter.default.post(name: .accountsChanged, object: nil)
                        completion(.success(()))
                    case 400:
                        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { attempt() }
                    case 429:
                        interval += 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { attempt() }
                    case 410:
                        completion(.failure(HTTPError(message: "The code expired. Try connecting again.")))
                    case 418:
                        completion(.failure(HTTPError(message: "The request was denied on Trakt.")))
                    default:
                        completion(.failure(HTTPError(message: "Trakt sign-in failed (\(r.status)).")))
                    }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { attempt() }
    }

    private func fetchUsername() {
        authorized("/users/settings") { [weak self] result in
            if case .success(let r) = result,
               let user = JSON.dict(r.dict?["user"]), let name = JSON.string(user["username"]) {
                self?.defaults.set(name, forKey: "trakt.username")
                NotificationCenter.default.post(name: .accountsChanged, object: nil)
            }
        }
    }

    // MARK: Authorized requests

    private func refreshIfNeeded(_ completion: @escaping (Bool) -> Void) {
        guard isSignedIn else { completion(false); return }
        guard Date().timeIntervalSince1970 > expiresAt - 3600 else { completion(true); return }
        guard let refresh = refreshToken, let url = URL(string: "\(api)/oauth/token") else { completion(false); return }
        let body: [String: Any] = [
            "refresh_token": refresh, "client_id": clientId, "client_secret": clientSecret,
            "redirect_uri": "urn:ietf:wg:oauth:2.0:oob", "grant_type": "refresh_token",
        ]
        HTTP.request(url, method: "POST", headers: baseHeaders(), json: body) { [weak self] result in
            if case .success(let r) = result, r.ok, let d = r.dict {
                self?.storeTokens(d)
                completion(true)
            } else {
                completion(false)
            }
        }
    }

    private func authorized(_ path: String, method: String = "GET", json: Any? = nil,
                            completion: @escaping (Result<HTTPResponse, Error>) -> Void) {
        refreshIfNeeded { [weak self] ok in
            guard let self = self, ok, let token = self.accessToken, let url = URL(string: self.api + path) else {
                completion(.failure(HTTPError(message: "Not connected to Trakt.")))
                return
            }
            var headers = self.baseHeaders()
            headers["Authorization"] = "Bearer \(token)"
            HTTP.request(url, method: method, headers: headers, json: json, completion: completion)
        }
    }

    // MARK: Scrobbling

    func scrobble(_ event: PlaybackEvent, ref: MediaRef, videoId: String, progress: Double) {
        guard isSignedIn else { return }
        var body: [String: Any] = ["progress": min(100, max(0, progress))]
        if let se = AccountHelpers.seasonEpisode(from: videoId), ref.type != "movie" {
            let showId = String(videoId.split(separator: ":").first ?? "")
            guard showId.hasPrefix("tt") else { return }
            body["show"] = ["ids": ["imdb": showId]]
            body["episode"] = ["season": se.0, "number": se.1]
        } else {
            guard ref.id.hasPrefix("tt") else { return }
            body["movie"] = ["ids": ["imdb": ref.id]]
        }
        let action: String
        switch event {
        case .start: action = "start"
        case .pause: action = "pause"
        case .stop: action = "stop"
        }
        authorized("/scrobble/\(action)", method: "POST", json: body) { _ in }
    }

    // MARK: History

    /// Adds or removes watched history for a movie or a set of episodes.
    func setHistory(ref: MediaRef, videoIds: [String], watched: Bool) {
        guard isSignedIn else { return }
        var body: [String: Any] = [:]
        if ref.type == "movie" {
            guard ref.id.hasPrefix("tt") else { return }
            body["movies"] = [["ids": ["imdb": ref.id]]]
        } else {
            var seasons: [Int: [Int]] = [:]
            var showId: String?
            for v in videoIds {
                guard let se = AccountHelpers.seasonEpisode(from: v) else { continue }
                showId = showId ?? String(v.split(separator: ":").first ?? "")
                seasons[se.0, default: []].append(se.1)
            }
            guard let show = showId, show.hasPrefix("tt"), !seasons.isEmpty else { return }
            let seasonList: [[String: Any]] = seasons.keys.sorted().map { s in
                ["number": s, "episodes": (seasons[s] ?? []).sorted().map { ["number": $0] }]
            }
            body["shows"] = [["ids": ["imdb": show], "seasons": seasonList]]
        }
        authorized(watched ? "/sync/history" : "/sync/history/remove", method: "POST", json: body) { _ in }
    }

    // MARK: Import

    /// Imports in-progress movies and episodes into Continue Watching.
    func importPlayback(completion: @escaping (Result<Int, Error>) -> Void) {
        authorized("/sync/playback?limit=100") { result in
            switch result {
            case .failure(let e):
                completion(.failure(e))
            case .success(let r):
                guard r.ok, let list = r.json as? [Any] else {
                    completion(.failure(HTTPError(message: r.errorMessage)))
                    return
                }
                var entries: [ImportedProgress] = []
                for case let d as [String: Any] in list {
                    let progress = (d["progress"] as? NSNumber)?.doubleValue ?? 0
                    let date = AccountHelpers.parseISODate(d["paused_at"]) ?? Date.distantPast
                    if JSON.string(d["type"]) == "movie", let movie = JSON.dict(d["movie"]),
                       let imdb = JSON.string(JSON.dict(movie["ids"])?["imdb"]) {
                        let ref = MediaRef(id: imdb, type: "movie", name: JSON.string(movie["title"]) ?? "",
                                           poster: AccountHelpers.posterURL(forImdb: imdb))
                        entries.append(ImportedProgress(ref: ref, videoId: imdb, label: nil,
                                                        position: progress, duration: 100,
                                                        isFraction: true, updatedAt: date))
                    } else if let show = JSON.dict(d["show"]), let ep = JSON.dict(d["episode"]),
                              let imdb = JSON.string(JSON.dict(show["ids"])?["imdb"]),
                              let s = JSON.int(ep["season"]), let e = JSON.int(ep["number"]) {
                        let ref = MediaRef(id: imdb, type: "series", name: JSON.string(show["title"]) ?? "",
                                           poster: AccountHelpers.posterURL(forImdb: imdb))
                        let title = JSON.string(ep["title"])
                        let label = title.map { "S\(s)E\(e) · \($0)" } ?? "S\(s)E\(e)"
                        entries.append(ImportedProgress(ref: ref, videoId: "\(imdb):\(s):\(e)", label: label,
                                                        position: progress, duration: 100,
                                                        isFraction: true, updatedAt: date))
                    }
                }
                completion(.success(LibraryStore.shared.importProgress(entries)))
            }
        }
    }
}
