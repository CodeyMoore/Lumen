import Foundation

struct RankedStream {
    let stream: StreamItem
    let addon: Addon
    let order: Int
}

enum StreamSort: Int, CaseIterable {
    case quality, size, addon

    var title: String {
        switch self {
        case .quality: return "Quality"
        case .size: return "Size"
        case .addon: return "Addon"
        }
    }
}

enum QualityFilter: Int, CaseIterable {
    case all, uhd, fhd, hd, sd

    var title: String {
        switch self {
        case .all: return "All"
        case .uhd: return "4K"
        case .fhd: return "1080p"
        case .hd: return "720p"
        case .sd: return "SD"
        }
    }

    func matches(_ quality: Int) -> Bool {
        switch self {
        case .all: return true
        case .uhd: return quality >= 2160
        case .fhd: return quality >= 1080 && quality < 2160
        case .hd: return quality >= 720 && quality < 1080
        case .sd: return quality > 0 && quality < 720
        }
    }
}

enum StreamRanker {
    /// Higher is better. Prefers the user's chosen quality, never above it unless nothing else exists.
    static func qualityScore(_ q: Int) -> Int {
        let preferred = AppSettings.shared.preferredQuality
        guard q > 0 else { return 0 }
        guard preferred > 0 else { return q }
        if q == preferred { return 10_000 }
        if q < preferred { return q }
        return 1 // above preferred: still usable, but last among known qualities
    }

    private static func isPreferredAddon(_ r: RankedStream) -> Bool {
        AppSettings.shared.rememberAddon && r.addon.manifest.id == AppSettings.shared.preferredAddonId
    }

    static func sorted(_ items: [RankedStream], by sort: StreamSort) -> [RankedStream] {
        items.sorted { a, b in
            switch sort {
            case .quality:
                let qa = qualityScore(a.stream.quality), qb = qualityScore(b.stream.quality)
                if qa != qb { return qa > qb }
            case .size:
                let sa = a.stream.sizeBytes ?? -1, sb = b.stream.sizeBytes ?? -1
                if sa != sb { return sa > sb }
            case .addon:
                let pa = isPreferredAddon(a), pb = isPreferredAddon(b)
                if pa != pb { return pa }
            }
            // Playable streams before torrents, then preferred addon, then original order.
            if a.stream.isDirect != b.stream.isDirect { return a.stream.isDirect }
            let pa = isPreferredAddon(a), pb = isPreferredAddon(b)
            if pa != pb { return pa }
            return a.order < b.order
        }
    }

    /// Best directly playable stream, optionally restricted to a binge group or addon.
    static func best(_ items: [RankedStream], bingeGroup: String? = nil, addonId: String? = nil) -> RankedStream? {
        var pool = items.filter { $0.stream.isDirect }
        if let g = bingeGroup {
            let same = pool.filter { $0.stream.bingeGroup == g }
            if !same.isEmpty { return sorted(same, by: .quality).first }
        }
        if let a = addonId {
            let same = pool.filter { $0.addon.manifest.id == a }
            if !same.isEmpty { pool = same }
        }
        return sorted(pool, by: .quality).first
    }
}

/// Fetches streams from every addon that can provide them.
enum StreamFetcher {
    static func addons(type: String, videoId: String) -> [Addon] {
        AddonStore.shared.addons(supporting: "stream", type: type, id: videoId)
    }

    /// Calls `partial` as each addon answers, then `done` once all have.
    static func fetch(type: String, videoId: String,
                      partial: ((Int, Result<[StreamItem], Error>) -> Void)? = nil,
                      done: @escaping ([RankedStream]) -> Void) {
        let addons = self.addons(type: type, videoId: videoId)
        var collected: [Int: [StreamItem]] = [:]
        let group = DispatchGroup()
        for (i, addon) in addons.enumerated() {
            group.enter()
            StremioAPI.shared.streams(addon: addon, type: type, id: videoId) { result in
                if case .success(let s) = result { collected[i] = s }
                partial?(i, result)
                group.leave()
            }
        }
        group.notify(queue: .main) {
            var out: [RankedStream] = []
            var order = 0
            for (i, addon) in addons.enumerated() {
                for s in collected[i] ?? [] {
                    out.append(RankedStream(stream: s, addon: addon, order: order))
                    order += 1
                }
            }
            done(out)
        }
    }
}
