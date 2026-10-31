import Foundation
import Security

extension Notification.Name {
    static let settingsChanged = Notification.Name("lumen.settingsChanged")
    static let accountsChanged = Notification.Name("lumen.accountsChanged")
    static let downloadsChanged = Notification.Name("lumen.downloadsChanged")
}

final class AppSettings {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    enum PlayerChoice: String, CaseIterable {
        case lumen, system, vlcApp, infuse, nplayer, outplayer

        var title: String {
            switch self {
            case .lumen: return "Lumen (VLC engine)"
            case .system: return "Lumen (iOS player)"
            case .vlcApp: return "VLC app"
            case .infuse: return "Infuse"
            case .nplayer: return "nPlayer"
            case .outplayer: return "Outplayer"
            }
        }

        var external: ExternalPlayer? {
            switch self {
            case .lumen, .system: return nil
            case .vlcApp: return .vlc
            case .infuse: return .infuse
            case .nplayer: return .nplayer
            case .outplayer: return .outplayer
            }
        }
    }

    private func bool(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    private func set(_ value: Any?, _ key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }

    var player: PlayerChoice {
        get { PlayerChoice(rawValue: defaults.string(forKey: "set.player") ?? "") ?? .lumen }
        set { set(newValue.rawValue, "set.player") }
    }

    var autoplayNext: Bool {
        get { bool("set.autoplayNext", true) }
        set { set(newValue, "set.autoplayNext") }
    }

    var autoPlayBest: Bool {
        get { bool("set.autoPlayBest", false) }
        set { set(newValue, "set.autoPlayBest") }
    }

    /// Preferred vertical resolution; 0 means "highest available".
    var preferredQuality: Int {
        get { defaults.integer(forKey: "set.quality") }
        set { set(newValue, "set.quality") }
    }

    var rememberAddon: Bool {
        get { bool("set.rememberAddon", true) }
        set { set(newValue, "set.rememberAddon") }
    }

    var preferredAddonId: String? {
        get { defaults.string(forKey: "set.preferredAddon") }
        set { defaults.set(newValue, forKey: "set.preferredAddon") }
    }

    enum CompatMode: String, CaseIterable {
        case auto, on, off

        var title: String {
            switch self {
            case .auto: return "Automatic"
            case .on: return "On"
            case .off: return "Off"
            }
        }
    }

    /// Prefer streams old hardware can decode smoothly (H.264, 1080p or lower).
    var compatMode: CompatMode {
        get { CompatMode(rawValue: defaults.string(forKey: "set.compat") ?? "") ?? .auto }
        set { set(newValue.rawValue, "set.compat") }
    }

    var compatActive: Bool {
        switch compatMode {
        case .on: return true
        case .off: return false
        case .auto: return !DeviceCaps.hevcHardwareDecode
        }
    }

    /// In compatibility mode, hide HEVC/AV1/10-bit/HDR streams entirely.
    var hideHeavyStreams: Bool {
        get { bool("set.hideHeavy", false) }
        set { set(newValue, "set.hideHeavy") }
    }

    /// Quality cap actually used for ranking (compatibility mode caps "Highest" at 1080p).
    var effectiveQuality: Int {
        let q = preferredQuality
        if compatActive && (q == 0 || q > 1080) { return 1080 }
        return q
    }

    var gesturesEnabled: Bool {
        get { bool("set.gestures", true) }
        set { set(newValue, "set.gestures") }
    }

    /// Seconds jumped by the skip buttons and double-tap.
    var skipInterval: Int {
        get { defaults.object(forKey: "set.skipInterval") == nil ? 10 : defaults.integer(forKey: "set.skipInterval") }
        set { set(newValue, "set.skipInterval") }
    }

    var skipSegments: Bool {
        get { bool("set.skipSegments", true) }
        set { set(newValue, "set.skipSegments") }
    }

    var autoSkipSegments: Bool {
        get { bool("set.autoSkip", false) }
        set { set(newValue, "set.autoSkip") }
    }

    var hideTorrents: Bool {
        get { bool("set.hideTorrents", true) }
        set { set(newValue, "set.hideTorrents") }
    }

    /// Two-letter code; empty string means subtitles off by default.
    var subtitleLanguage: String {
        get {
            if let v = defaults.string(forKey: "set.subLang") { return v }
            return String((Locale.preferredLanguages.first ?? "en").prefix(2)).lowercased()
        }
        set { set(newValue, "set.subLang") }
    }

    var subtitleScale: Double {
        get { defaults.object(forKey: "set.subScale") == nil ? 1.0 : defaults.double(forKey: "set.subScale") }
        set { set(newValue, "set.subScale") }
    }

    /// Keep playing (audio) when the screen locks or you leave the app.
    var backgroundPlayback: Bool {
        get { bool("set.bgPlay", true) }
        set { set(newValue, "set.bgPlay") }
    }

    var subtitleColorIndex: Int {
        get { defaults.integer(forKey: "set.subColor") }
        set { set(newValue, "set.subColor") }
    }

    /// 0 = none, 1 = normal, 2 = thick
    var subtitleOutline: Int {
        get { defaults.object(forKey: "set.subOutline") == nil ? 1 : defaults.integer(forKey: "set.subOutline") }
        set { set(newValue, "set.subOutline") }
    }

    /// 0 = low, 1 = normal, 2 = raised
    var subtitlePosition: Int {
        get { defaults.object(forKey: "set.subPosition") == nil ? 1 : defaults.integer(forKey: "set.subPosition") }
        set { set(newValue, "set.subPosition") }
    }

    /// Subtitle timing fixes remembered per show/movie id.
    func subtitleDelay(for mediaId: String) -> Double {
        (defaults.dictionary(forKey: "lumen.subDelays.v1")?[mediaId] as? NSNumber)?.doubleValue ?? 0
    }

    func setSubtitleDelay(_ delay: Double, for mediaId: String) {
        var d = defaults.dictionary(forKey: "lumen.subDelays.v1") ?? [:]
        d[mediaId] = abs(delay) < 0.01 ? nil : delay
        defaults.set(d, forKey: "lumen.subDelays.v1")
    }

    static let subtitleColorChoices: [(Int, String)] = [(0, "White"), (1, "Yellow"), (2, "Cyan"), (3, "Green"), (4, "Pink")]
    static let subtitleOutlineChoices: [(Int, String)] = [(0, "None"), (1, "Normal"), (2, "Thick")]
    static let subtitlePositionChoices: [(Int, String)] = [(0, "Low"), (1, "Normal"), (2, "Raised")]

    var subtitleBackground: Bool {
        get { bool("set.subBackground", false) }
        set { set(newValue, "set.subBackground") }
    }

    /// Stable per-install identifier used by sync services.
    var installationId: String {
        if let id = defaults.string(forKey: "set.installId") { return id }
        let id = UUID().uuidString.lowercased()
        defaults.set(id, forKey: "set.installId")
        return id
    }

    static let skipIntervalChoices: [(Int, String)] = [(5, "5 seconds"), (10, "10 seconds"), (15, "15 seconds"), (30, "30 seconds")]

    static let qualityChoices: [(Int, String)] = [(0, "Highest"), (2160, "4K"), (1080, "1080p"), (720, "720p"), (480, "480p")]

    static let subtitleScaleChoices: [(Double, String)] = [(0.8, "Small"), (1.0, "Medium"), (1.25, "Large"), (1.5, "Extra Large")]

    static let subtitleLanguages: [String] = [
        "en", "es", "fr", "de", "it", "pt", "nl", "sv", "no", "da", "fi", "pl", "ru", "uk", "cs", "sk", "hu",
        "ro", "bg", "el", "tr", "ar", "he", "fa", "hi", "zh", "ja", "ko", "vi", "th", "id", "ms", "hr", "sr",
    ]
}

// MARK: - Keychain

enum Keychain {
    private static let service = "com.codeymoore.lumen"

    static func set(_ value: String?, for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        guard let value = value, let data = value.data(using: .utf8) else {
            UserDefaults.standard.removeObject(forKey: fallbackKey(key))
            return
        }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if SecItemAdd(add as CFDictionary, nil) == errSecSuccess {
            UserDefaults.standard.removeObject(forKey: fallbackKey(key))
        } else {
            // Fake-signed installs on some jailbroken devices can't use the keychain.
            UserDefaults.standard.set(value, forKey: fallbackKey(key))
        }
    }

    private static func fallbackKey(_ key: String) -> String { "kc.fallback.\(key)" }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return UserDefaults.standard.string(forKey: fallbackKey(key))
        }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Generic HTTP

struct HTTPError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct HTTPResponse {
    let status: Int
    let json: Any?
    var ok: Bool { (200..<300).contains(status) }
    var dict: [String: Any]? { json as? [String: Any] }

    /// Best-effort error message from common API error shapes.
    var errorMessage: String {
        if let d = dict {
            for key in ["error_description", "msg", "message", "error"] {
                if let s = d[key] as? String, !s.isEmpty { return s }
                if let inner = d[key] as? [String: Any], let s = inner["message"] as? String { return s }
            }
        }
        return "Request failed (\(status))."
    }
}

enum HTTP {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        return URLSession(configuration: config)
    }()

    /// Completion runs on the main queue. Fails only on network errors; check `status` for HTTP errors.
    static func request(_ url: URL, method: String = "GET", headers: [String: String] = [:], json: Any? = nil,
                        completion: @escaping (Result<HTTPResponse, Error>) -> Void) {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if let body = json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        }
        session.dataTask(with: req) { data, response, error in
            let result: Result<HTTPResponse, Error>
            if let error = error {
                result = .failure(error)
            } else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                var parsed: Any?
                if let data = data, !data.isEmpty {
                    parsed = try? JSONSerialization.jsonObject(with: data, options: [.allowFragments])
                }
                result = .success(HTTPResponse(status: status, json: parsed))
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }
}
