import UIKit

final class SettingsViewController: SettingsTableController {
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Settings"
        NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .accountsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .addonsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .downloadsChanged, object: nil)
    }

    @objc private func changed() { rebuild() }

    override func buildSections() -> [Section] {
        let s = AppSettings.shared
        let qualityName = AppSettings.qualityChoices.first { $0.0 == s.preferredQuality }?.1 ?? "Highest"
        let scaleName = AppSettings.subtitleScaleChoices.first { abs($0.0 - s.subtitleScale) < 0.01 }?.1 ?? "Medium"
        let langName = s.subtitleLanguage.isEmpty ? "Off" : SubtitleParser.languageName(s.subtitleLanguage)

        let accounts = [
            StremioAccount.shared.isSignedIn ? "Stremio" : nil,
            TraktAccount.shared.isSignedIn ? "Trakt" : nil,
            NuvioAccount.shared.isSignedIn ? "Nuvio" : nil,
        ].compactMap { $0 }

        let downloads = DownloadManager.shared.records
        let active = downloads.filter { $0.state == .downloading }.count

        return [
            Section(title: "Accounts", footer: nil, rows: [
                .value("Stremio, Trakt & Nuvio", accounts.isEmpty ? "Not connected" : accounts.joined(separator: ", ")) { [weak self] _ in
                    self?.navigationController?.pushViewController(AccountsViewController(), animated: true)
                },
            ]),
            Section(title: "Content", footer: nil, rows: [
                .value("Addons", "\(AddonStore.shared.addons.count) installed") { [weak self] _ in
                    self?.navigationController?.pushViewController(AddonsViewController(), animated: true)
                },
                .value("Downloads", active > 0 ? "\(active) in progress" : "\(downloads.count)") { [weak self] _ in
                    self?.navigationController?.pushViewController(DownloadsViewController(), animated: true)
                },
            ]),
            Section(title: "Playback", footer: "The VLC engine plays almost every format, including MKV. The iOS player supports AirPlay but not MKV.", rows: [
                .value("Player", s.player.title) { [weak self] src in
                    self?.choose("Player", AppSettings.PlayerChoice.allCases.map { ($0, $0.title) },
                                 current: { $0 == s.player }, from: src) { s.player = $0 }
                },
                .toggle("Auto-play next episode", s.autoplayNext) { s.autoplayNext = $0 },
                .toggle("Play best stream automatically", s.autoPlayBest) { s.autoPlayBest = $0 },
                .value("Preferred quality", qualityName) { [weak self] src in
                    self?.choose("Preferred Quality", AppSettings.qualityChoices,
                                 current: { $0 == s.preferredQuality }, from: src) { s.preferredQuality = $0 }
                },
                .toggle("Prefer last-used addon", s.rememberAddon) { s.rememberAddon = $0 },
                .toggle("Hide torrent-only streams", s.hideTorrents) { s.hideTorrents = $0 },
            ]),
            Section(title: "Subtitles", footer: "Subtitles in your preferred language turn on automatically when an addon provides them.", rows: [
                .value("Preferred language", langName) { [weak self] src in
                    var options: [(String, String)] = [("", "Off")]
                    options += AppSettings.subtitleLanguages.map { ($0, SubtitleParser.languageName($0)) }
                    self?.choose("Subtitle Language", options, current: { $0 == s.subtitleLanguage }, from: src) {
                        s.subtitleLanguage = $0
                    }
                },
                .value("Size", scaleName) { [weak self] src in
                    self?.choose("Subtitle Size", AppSettings.subtitleScaleChoices,
                                 current: { abs($0 - s.subtitleScale) < 0.01 }, from: src) { s.subtitleScale = $0 }
                },
                .toggle("Background box", s.subtitleBackground) { s.subtitleBackground = $0 },
            ]),
            Section(title: "About", footer: nil, rows: [
                .info("Version", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String),
            ]),
        ]
    }
}
