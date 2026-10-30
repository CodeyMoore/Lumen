import Foundation

// MARK: - Lenient JSON helpers
// Stremio addons are written by many people; fields are often the "wrong" type
// (numbers as strings, ratings as numbers, etc.), so we parse by hand.

enum JSON {
    static func string(_ v: Any?) -> String? {
        if let s = v as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }

    static func int(_ v: Any?) -> Int? {
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    static func bool(_ v: Any?) -> Bool {
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        if let s = v as? String { return s == "true" || s == "1" }
        return false
    }

    static func dict(_ v: Any?) -> [String: Any]? { v as? [String: Any] }

    static func dicts(_ v: Any?) -> [[String: Any]] {
        ((v as? [Any]) ?? []).compactMap { $0 as? [String: Any] }
    }

    static func strings(_ v: Any?) -> [String] {
        ((v as? [Any]) ?? []).compactMap { string($0) }
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(_ v: Any?) -> Date? {
        guard let s = string(v) else { return nil }
        return isoFractional.date(from: s) ?? iso.date(from: s)
    }
}

enum TypeNames {
    static func plural(_ type: String) -> String {
        switch type {
        case "movie": return "Movies"
        case "series": return "Series"
        case "channel": return "Channels"
        case "tv": return "TV"
        case "anime": return "Anime"
        default: return type.capitalized
        }
    }
}

// MARK: - Manifest

struct ResourceDescriptor {
    let name: String
    let types: [String]?
    let idPrefixes: [String]?
}

struct ExtraDescriptor {
    let name: String
    let isRequired: Bool
    let options: [String]
}

struct CatalogDescriptor {
    let type: String
    let id: String
    let name: String
    let extras: [ExtraDescriptor]

    var requiresExtra: Bool { extras.contains { $0.isRequired } }
    var supportsSearch: Bool { extras.contains { $0.name == "search" } }
    var supportsSkip: Bool { extras.contains { $0.name == "skip" } }

    /// Extras with a fixed list of choices (genre, year…) shown as filters in Discover.
    var filterExtras: [ExtraDescriptor] {
        extras.filter { !$0.options.isEmpty && $0.name != "skip" && $0.name != "search" }
    }

    /// Browsable in Discover: every required extra can be satisfied by picking an option.
    var isBrowsable: Bool {
        !extras.contains { $0.isRequired && ($0.options.isEmpty || $0.name == "search") }
    }

    var displayTitle: String {
        let plural = TypeNames.plural(type)
        let lower = name.lowercased()
        if lower.contains(plural.lowercased()) || lower.contains(type.lowercased()) { return name }
        return "\(name) · \(plural)"
    }
}

struct Manifest {
    let raw: [String: Any]
    let id: String
    let name: String
    let version: String
    let description: String?
    let types: [String]
    let idPrefixes: [String]?
    let resources: [ResourceDescriptor]
    let catalogs: [CatalogDescriptor]

    init?(json: [String: Any]) {
        guard let id = JSON.string(json["id"]), let name = JSON.string(json["name"]) else { return nil }
        raw = json
        self.id = id
        self.name = name
        version = JSON.string(json["version"]) ?? ""
        description = JSON.string(json["description"])
        types = JSON.strings(json["types"])
        idPrefixes = json["idPrefixes"] == nil ? nil : JSON.strings(json["idPrefixes"])

        var res: [ResourceDescriptor] = []
        for r in (json["resources"] as? [Any]) ?? [] {
            if let s = r as? String {
                res.append(ResourceDescriptor(name: s, types: nil, idPrefixes: nil))
            } else if let d = r as? [String: Any], let n = JSON.string(d["name"]) {
                res.append(ResourceDescriptor(
                    name: n,
                    types: d["types"] == nil ? nil : JSON.strings(d["types"]),
                    idPrefixes: d["idPrefixes"] == nil ? nil : JSON.strings(d["idPrefixes"])))
            }
        }
        resources = res

        var cats: [CatalogDescriptor] = []
        for c in JSON.dicts(json["catalogs"]) {
            guard let type = JSON.string(c["type"]), let cid = JSON.string(c["id"]) else { continue }
            var extras = JSON.dicts(c["extra"]).compactMap { e -> ExtraDescriptor? in
                guard let n = JSON.string(e["name"]) else { return nil }
                return ExtraDescriptor(name: n, isRequired: JSON.bool(e["isRequired"]),
                                       options: JSON.strings(e["options"]))
            }
            // Legacy manifest format
            let required = JSON.strings(c["extraRequired"])
            for s in JSON.strings(c["extraSupported"]) where !extras.contains(where: { $0.name == s }) {
                extras.append(ExtraDescriptor(name: s, isRequired: required.contains(s), options: []))
            }
            cats.append(CatalogDescriptor(type: type, id: cid, name: JSON.string(c["name"]) ?? cid, extras: extras))
        }
        catalogs = cats
    }

    func hasResource(_ name: String) -> Bool {
        resources.contains { $0.name == name }
    }

    func supports(_ resource: String, type: String, id: String?) -> Bool {
        guard let r = resources.first(where: { $0.name == resource }) else { return false }
        let allowedTypes = r.types ?? types
        if !allowedTypes.isEmpty && !allowedTypes.contains(type) { return false }
        if let id = id, let prefixes = r.idPrefixes ?? idPrefixes, !prefixes.isEmpty {
            return prefixes.contains { id.hasPrefix($0) }
        }
        return true
    }

    var capabilitySummary: String {
        let names: [(String, String)] = [("catalog", "Catalogs"), ("meta", "Details"),
                                         ("stream", "Streams"), ("subtitles", "Subtitles")]
        let has = names.filter { hasResource($0.0) }.map { $0.1 }
        return has.isEmpty ? "No supported resources" : has.joined(separator: " · ")
    }
}

struct Addon {
    let transportUrl: String
    let manifest: Manifest

    var baseURL: String {
        var s = transportUrl
        if s.hasSuffix("/manifest.json") { s.removeLast("/manifest.json".count) }
        return s
    }
}

// MARK: - Content

struct MediaRef: Codable, Equatable {
    let id: String
    let type: String
    let name: String
    let poster: String?
}

struct Video {
    let id: String
    let title: String
    let season: Int?
    let episode: Int?
    let released: Date?
    let thumbnail: String?
    let overview: String?

    init?(json: [String: Any]) {
        guard let id = JSON.string(json["id"]) else { return nil }
        self.id = id
        title = JSON.string(json["title"]) ?? JSON.string(json["name"]) ?? ""
        season = JSON.int(json["season"])
        episode = JSON.int(json["episode"]) ?? JSON.int(json["number"])
        released = JSON.date(json["released"]) ?? JSON.date(json["firstAired"])
        thumbnail = JSON.string(json["thumbnail"])
        overview = JSON.string(json["overview"]) ?? JSON.string(json["description"])
    }

    var shortLabel: String {
        if let s = season, let e = episode { return "S\(s)E\(e)" }
        return title.isEmpty ? "Episode" : title
    }

    var longLabel: String {
        if let s = season, let e = episode {
            return title.isEmpty ? "S\(s)E\(e)" : "S\(s)E\(e) · \(title)"
        }
        return title.isEmpty ? "Episode" : title
    }
}

struct MetaItem {
    let id: String
    let type: String
    let name: String
    let poster: String?
    let background: String?
    let description: String?
    let releaseInfo: String?
    let imdbRating: String?
    let runtime: String?
    let genres: [String]
    let videos: [Video]
    let defaultVideoId: String?

    init?(json: [String: Any], fallbackType: String? = nil) {
        guard let id = JSON.string(json["id"]),
              let type = JSON.string(json["type"]) ?? fallbackType else { return nil }
        self.id = id
        self.type = type
        name = JSON.string(json["name"]) ?? ""
        poster = JSON.string(json["poster"])
        background = JSON.string(json["background"])
        description = JSON.string(json["description"])
        releaseInfo = JSON.string(json["releaseInfo"]) ?? JSON.string(json["year"])
        imdbRating = JSON.string(json["imdbRating"])
        runtime = JSON.string(json["runtime"])
        var g = JSON.strings(json["genres"])
        if g.isEmpty {
            g = JSON.dicts(json["links"])
                .filter { JSON.string($0["category"]) == "Genres" }
                .compactMap { JSON.string($0["name"]) }
        }
        genres = g
        videos = JSON.dicts(json["videos"]).compactMap(Video.init(json:))
        defaultVideoId = JSON.string(JSON.dict(json["behaviorHints"])?["defaultVideoId"])
    }

    var ref: MediaRef { MediaRef(id: id, type: type, name: name, poster: poster) }
}

struct StreamItem {
    enum Kind {
        case direct(URL)
        case youtube(String)
        case external(URL)
        case torrent(String)
        case unsupported
    }

    let name: String?
    let title: String?
    let url: String?
    let ytId: String?
    let infoHash: String?
    let externalUrl: String?
    let headers: [String: String]
    let bingeGroup: String?
    let filename: String?
    /// Vertical resolution parsed from the stream's labels (2160, 1080…); 0 if unknown.
    let quality: Int
    let sizeBytes: Int64?

    init?(json: [String: Any]) {
        name = JSON.string(json["name"])
        title = JSON.string(json["title"]) ?? JSON.string(json["description"])
        url = JSON.string(json["url"])
        ytId = JSON.string(json["ytId"])
        infoHash = JSON.string(json["infoHash"])
        externalUrl = JSON.string(json["externalUrl"])
        let hints = JSON.dict(json["behaviorHints"])
        let proxy = JSON.dict(hints?["proxyHeaders"])
        var h: [String: String] = [:]
        for (k, v) in JSON.dict(proxy?["request"]) ?? [:] {
            if let s = JSON.string(v) { h[k] = s }
        }
        headers = h
        bingeGroup = JSON.string(hints?["bingeGroup"])
        filename = JSON.string(hints?["filename"])
        if url == nil && ytId == nil && infoHash == nil && externalUrl == nil { return nil }
        let text = [name, title, filename].compactMap { $0 }.joined(separator: " ")
        quality = StreamItem.parseQuality(text)
        if let v = hints?["videoSize"] as? NSNumber, v.int64Value > 0 {
            sizeBytes = v.int64Value
        } else {
            sizeBytes = StreamItem.parseSize(text)
        }
    }

    var isDirect: Bool {
        if case .direct = kind { return true }
        return false
    }

    var qualityLabel: String? {
        switch quality {
        case 2160: return "4K"
        case 0: return nil
        default: return "\(quality)p"
        }
    }

    var sizeLabel: String? {
        guard let b = sizeBytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }

    static func parseQuality(_ text: String) -> Int {
        let t = text.lowercased()
        if t.contains("2160") || t.contains("4k") || t.contains("uhd") { return 2160 }
        if t.contains("1440") { return 1440 }
        if t.contains("1080") || t.contains("fhd") { return 1080 }
        if t.contains("720") { return 720 }
        if t.contains("576") || t.contains("480") { return 480 }
        if t.contains("360") { return 360 }
        return 0
    }

    private static let sizeRegex = try? NSRegularExpression(
        pattern: "(\\d+(?:[.,]\\d+)?)\\s*(tb|gb|gib|mb|mib)\\b", options: [.caseInsensitive])

    static func parseSize(_ text: String) -> Int64? {
        guard let re = sizeRegex else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 3 else { return nil }
        let number = Double(ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: ".")) ?? 0
        let unit = ns.substring(with: m.range(at: 2)).lowercased()
        let multiplier: Double
        switch unit {
        case "tb": multiplier = 1_000_000_000_000
        case "gb", "gib": multiplier = 1_000_000_000
        default: multiplier = 1_000_000
        }
        let bytes = number * multiplier
        return bytes > 0 ? Int64(bytes) : nil
    }

    var kind: Kind {
        if let u = url, let parsed = StreamItem.makeURL(u) { return .direct(parsed) }
        if let y = ytId { return .youtube(y) }
        if let e = externalUrl, let parsed = StreamItem.makeURL(e) { return .external(parsed) }
        if let h = infoHash { return .torrent(h) }
        return .unsupported
    }

    var displayName: String {
        (name ?? "Stream").replacingOccurrences(of: "\n", with: " ")
    }

    static func makeURL(_ s: String) -> URL? {
        if let u = URL(string: s) { return u }
        if let enc = s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) { return URL(string: enc) }
        return nil
    }
}

struct SubtitleTrack {
    let id: String
    let url: String
    let lang: String

    init?(json: [String: Any]) {
        guard let url = JSON.string(json["url"]) else { return nil }
        self.url = url
        id = JSON.string(json["id"]) ?? url
        lang = JSON.string(json["lang"]) ?? "und"
    }
}
