import Foundation

struct SkipSegment {
    enum Kind {
        case intro, recap, outro

        var buttonTitle: String {
            switch self {
            case .intro: return "Skip Intro"
            case .recap: return "Skip Recap"
            case .outro: return "Skip Credits"
            }
        }

        var doneMessage: String {
            switch self {
            case .intro: return "Skipped intro"
            case .recap: return "Skipped recap"
            case .outro: return "Skipped credits"
            }
        }
    }

    let kind: Kind
    let start: Double
    let end: Double
}

/// Community intro/recap/credits times: IntroDB for IMDb episodes, AniSkip for anime (Kitsu ids).
enum SkipSegmentService {
    private static var cache: [String: [SkipSegment]] = [:]

    /// Completion runs on the main queue; an empty list means nothing is known.
    static func fetch(videoId: String, completion: @escaping ([SkipSegment]) -> Void) {
        if let cached = cache[videoId] { completion(cached); return }
        let done: ([SkipSegment]) -> Void = { segments in
            cache[videoId] = segments
            completion(segments)
        }
        let parts = videoId.split(separator: ":").map(String.init)
        if parts.count == 3, parts[0].hasPrefix("tt"), let s = Int(parts[1]), let e = Int(parts[2]) {
            introDB(imdb: parts[0], season: s, episode: e, completion: done)
        } else if parts.count >= 3, parts[0] == "kitsu", let ep = Int(parts[parts.count - 1]) {
            aniSkip(kitsuId: parts[1], episode: ep, completion: done)
        } else if parts.count == 2, parts[0] == "kitsu" {
            aniSkip(kitsuId: parts[1], episode: 1, completion: done)
        } else {
            completion([])
        }
    }

    private static func seconds(_ d: [String: Any]?, _ secKey: String, _ msKey: String) -> Double? {
        guard let d = d else { return nil }
        if let s = d[secKey] as? NSNumber { return s.doubleValue }
        if let ms = d[msKey] as? NSNumber { return ms.doubleValue / 1000 }
        return nil
    }

    private static func introDB(imdb: String, season: Int, episode: Int, completion: @escaping ([SkipSegment]) -> Void) {
        guard let url = URL(string: "https://api.introdb.app/segments?imdb_id=\(imdb)&season=\(season)&episode=\(episode)") else {
            completion([]); return
        }
        HTTP.request(url) { result in
            guard case .success(let r) = result, r.ok, let d = r.dict else { completion([]); return }
            var out: [SkipSegment] = []
            let kinds: [(String, SkipSegment.Kind)] = [("recap", .recap), ("intro", .intro), ("outro", .outro)]
            for (key, kind) in kinds {
                let seg = JSON.dict(d[key])
                if let start = seconds(seg, "start_sec", "start_ms"), let end = seconds(seg, "end_sec", "end_ms"),
                   start >= 0, end > start + 3 {
                    out.append(SkipSegment(kind: kind, start: start, end: end))
                }
            }
            completion(out.sorted { $0.start < $1.start })
        }
    }

    private static func aniSkip(kitsuId: String, episode: Int, completion: @escaping ([SkipSegment]) -> Void) {
        guard let mapURL = URL(string: "https://arm.haglund.dev/api/v2/ids?source=kitsu&id=\(kitsuId)") else {
            completion([]); return
        }
        HTTP.request(mapURL) { result in
            guard case .success(let r) = result, r.ok,
                  let mal = JSON.int(r.dict?["myanimelist"]),
                  let url = URL(string: "https://api.aniskip.com/v2/skip-times/\(mal)/\(episode)?types=op&types=ed&types=recap&types=mixed-op&types=mixed-ed&episodeLength=0") else {
                completion([]); return
            }
            HTTP.request(url) { result in
                guard case .success(let r) = result, r.ok else { completion([]); return }
                var out: [SkipSegment] = []
                for item in JSON.dicts(r.dict?["results"]) {
                    guard let interval = JSON.dict(item["interval"]),
                          let start = (interval["startTime"] as? NSNumber)?.doubleValue,
                          let end = (interval["endTime"] as? NSNumber)?.doubleValue, end > start + 3 else { continue }
                    let kind: SkipSegment.Kind
                    switch JSON.string(item["skipType"]) ?? "" {
                    case "op", "mixed-op": kind = .intro
                    case "ed", "mixed-ed": kind = .outro
                    case "recap": kind = .recap
                    default: continue
                    }
                    out.append(SkipSegment(kind: kind, start: start, end: end))
                }
                completion(out.sorted { $0.start < $1.start })
            }
        }
    }
}
