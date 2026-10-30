import Foundation

enum APIError: LocalizedError {
    case badURL
    case badStatus(Int)
    case invalidJSON
    case invalidManifest

    var errorDescription: String? {
        switch self {
        case .badURL: return "That isn't a valid URL."
        case .badStatus(let code): return "The server responded with error \(code)."
        case .invalidJSON: return "The server didn't return valid data."
        case .invalidManifest: return "That URL isn't a Stremio addon manifest."
        }
    }
}

/// Minimal client for the Stremio addon protocol:
/// {base}/{resource}/{type}/{id}[/{extra}].json
final class StremioAPI {
    static let shared = StremioAPI()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 40
        session = URLSession(configuration: config)
    }

    // MARK: URL helpers

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func encode(_ s: String, keepColon: Bool = false) -> String {
        var allowed = unreserved
        if keepColon { allowed.insert(charactersIn: ":") }
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    /// Accepts "https://x/manifest.json", "stremio://x/manifest.json", or a bare base URL.
    static func normalizeManifestURL(_ input: String) -> String? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if s.lowercased().hasPrefix("stremio://") {
            s = "https://" + String(s.dropFirst("stremio://".count))
        } else if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "https://" + s
        }
        if !s.hasSuffix("manifest.json") {
            while s.hasSuffix("/") { s.removeLast() }
            s += "/manifest.json"
        }
        return URL(string: s) != nil ? s : nil
    }

    func resourceURL(_ addon: Addon, resource: String, type: String, id: String,
                     extra: [(String, String)] = []) -> URL? {
        var path = "\(addon.baseURL)/\(resource)/\(StremioAPI.encode(type))/\(StremioAPI.encode(id, keepColon: true))"
        if !extra.isEmpty {
            path += "/" + extra.map { "\(StremioAPI.encode($0.0))=\(StremioAPI.encode($0.1))" }.joined(separator: "&")
        }
        return URL(string: path + ".json")
    }

    // MARK: Requests (completions are always called on the main queue)

    func getJSON(_ url: URL, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        session.dataTask(with: request) { data, response, error in
            let result: Result<[String: Any], Error>
            if let error = error {
                result = .failure(error)
            } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                result = .failure(APIError.badStatus(http.statusCode))
            } else if let data = data,
                      let obj = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] {
                result = .success(obj)
            } else {
                result = .failure(APIError.invalidJSON)
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    func fetchAddon(_ manifestURL: String, completion: @escaping (Result<Addon, Error>) -> Void) {
        guard let normalized = StremioAPI.normalizeManifestURL(manifestURL),
              let url = URL(string: normalized) else {
            completion(.failure(APIError.badURL)); return
        }
        getJSON(url) { result in
            switch result {
            case .success(let json):
                if let m = Manifest(json: json) {
                    completion(.success(Addon(transportUrl: normalized, manifest: m)))
                } else {
                    completion(.failure(APIError.invalidManifest))
                }
            case .failure(let e):
                completion(.failure(e))
            }
        }
    }

    func catalog(addon: Addon, catalog: CatalogDescriptor, extra: [(String, String)] = [],
                 completion: @escaping (Result<[MetaItem], Error>) -> Void) {
        guard let url = resourceURL(addon, resource: "catalog", type: catalog.type, id: catalog.id, extra: extra) else {
            completion(.failure(APIError.badURL)); return
        }
        getJSON(url) { result in
            completion(result.map { json in
                JSON.dicts(json["metas"]).compactMap { MetaItem(json: $0, fallbackType: catalog.type) }
            })
        }
    }

    func meta(addon: Addon, type: String, id: String, completion: @escaping (Result<MetaItem, Error>) -> Void) {
        guard let url = resourceURL(addon, resource: "meta", type: type, id: id) else {
            completion(.failure(APIError.badURL)); return
        }
        getJSON(url) { result in
            switch result {
            case .success(let json):
                if let d = JSON.dict(json["meta"]), let m = MetaItem(json: d, fallbackType: type) {
                    completion(.success(m))
                } else {
                    completion(.failure(APIError.invalidJSON))
                }
            case .failure(let e):
                completion(.failure(e))
            }
        }
    }

    func streams(addon: Addon, type: String, id: String, completion: @escaping (Result<[StreamItem], Error>) -> Void) {
        guard let url = resourceURL(addon, resource: "stream", type: type, id: id) else {
            completion(.failure(APIError.badURL)); return
        }
        getJSON(url) { result in
            completion(result.map { JSON.dicts($0["streams"]).compactMap(StreamItem.init(json:)) })
        }
    }

    func subtitles(addon: Addon, type: String, id: String, completion: @escaping (Result<[SubtitleTrack], Error>) -> Void) {
        guard let url = resourceURL(addon, resource: "subtitles", type: type, id: id) else {
            completion(.failure(APIError.badURL)); return
        }
        getJSON(url) { result in
            completion(result.map { JSON.dicts($0["subtitles"]).compactMap(SubtitleTrack.init(json:)) })
        }
    }
}
