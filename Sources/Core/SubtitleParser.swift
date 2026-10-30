import Foundation

struct SubtitleCue {
    let start: Double
    let end: Double
    let text: String
}

/// Parses SRT and WebVTT into cues, and helps pick languages.
enum SubtitleParser {
    static func decode(_ data: Data) -> String? {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(data: data, encoding: .isoLatin1)
    }

    static func parse(_ text: String) -> [SubtitleCue] {
        let normalized = text
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var cues: [SubtitleCue] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if line.contains("-->") {
                let parts = line.components(separatedBy: "-->")
                let endToken = parts.count > 1
                    ? (parts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? "")
                    : ""
                if let start = time(parts[0]), let end = time(endToken) {
                    var textLines: [String] = []
                    i += 1
                    while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                        textLines.append(lines[i])
                        i += 1
                    }
                    let cleaned = clean(textLines.joined(separator: "\n"))
                    if !cleaned.isEmpty { cues.append(SubtitleCue(start: start, end: end, text: cleaned)) }
                    continue
                }
            }
            i += 1
        }
        return cues.sorted { $0.start < $1.start }
    }

    static func time(_ raw: String) -> Double? {
        let s = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let comps = s.split(separator: ":").map(String.init)
        guard comps.count >= 2 else { return nil }
        var total = 0.0
        for c in comps {
            guard let v = Double(c) else { return nil }
            total = total * 60 + v
        }
        return total
    }

    private static func clean(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: "\\{[^}]*\\}", with: "", options: .regularExpression)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Binary search for the cue showing at time t.
    static func cue(at t: Double, in cues: [SubtitleCue]) -> SubtitleCue? {
        var lo = 0, hi = cues.count - 1, idx = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if cues[mid].start <= t { idx = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        guard idx >= 0 else { return nil }
        var j = idx
        while j >= 0 && j > idx - 5 {
            if t <= cues[j].end { return cues[j] }
            j -= 1
        }
        return nil
    }

    // MARK: Languages

    private static let threeToTwo: [String: String] = [
        "eng": "en", "spa": "es", "fre": "fr", "fra": "fr", "ger": "de", "deu": "de", "ita": "it",
        "por": "pt", "pob": "pt", "dut": "nl", "nld": "nl", "swe": "sv", "nor": "no", "dan": "da",
        "fin": "fi", "pol": "pl", "rus": "ru", "ukr": "uk", "cze": "cs", "ces": "cs", "slo": "sk",
        "slk": "sk", "hun": "hu", "rum": "ro", "ron": "ro", "bul": "bg", "gre": "el", "ell": "el",
        "tur": "tr", "ara": "ar", "heb": "he", "per": "fa", "fas": "fa", "hin": "hi", "chi": "zh",
        "zho": "zh", "jpn": "ja", "kor": "ko", "vie": "vi", "tha": "th", "ind": "id", "may": "ms",
        "msa": "ms", "hrv": "hr", "srp": "sr", "slv": "sl", "est": "et", "lav": "lv", "lit": "lt",
        "ice": "is", "isl": "is", "cat": "ca", "baq": "eu", "eus": "eu", "glg": "gl", "tgl": "tl",
    ]

    static func twoLetter(_ code: String) -> String {
        let c = code.lowercased()
        if c.count == 2 { return c }
        return threeToTwo[c] ?? c
    }

    static func languageName(_ code: String) -> String {
        if code.lowercased() == "pob" { return "Portuguese (Brazil)" }
        let two = twoLetter(code)
        return Locale.current.localizedString(forLanguageCode: two)?.capitalized ?? code
    }

    static func sortedByPreference(_ tracks: [SubtitleTrack]) -> [SubtitleTrack] {
        let preferred = Locale.preferredLanguages.map { lang -> String in
            String(lang.prefix { $0 != "-" && $0 != "_" }).lowercased()
        }
        func rank(_ t: SubtitleTrack) -> Int {
            preferred.firstIndex(of: twoLetter(t.lang)) ?? 99
        }
        return tracks.enumerated()
            .sorted { a, b in
                let ra = rank(a.element), rb = rank(b.element)
                return ra != rb ? ra < rb : a.offset < b.offset
            }
            .map { $0.element }
    }
}
