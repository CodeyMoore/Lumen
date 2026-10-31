import UIKit
import MobileCoreServices

final class SettingsViewController: SettingsTableController, UIDocumentPickerDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Settings"
        NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .accountsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .addonsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .downloadsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .profileChanged, object: nil)
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

        let compatFooter: String
        if DeviceCaps.hevcHardwareDecode {
            compatFooter = "This device can play HEVC in hardware, so Automatic leaves compatibility mode off."
        } else {
            compatFooter = "This device can't decode HEVC, AV1 or 10-bit video in hardware, so Automatic prefers H.264 streams at 1080p or lower."
        }
        let profiles = ProfileStore.shared
        var playerRows: [Row] = [
                .toggle("Gestures", s.gesturesEnabled) { s.gesturesEnabled = $0 },
                .value("Skip buttons jump", AppSettings.skipIntervalChoices.first { $0.0 == s.skipInterval }?.1 ?? "\(s.skipInterval) seconds") { [weak self] src in
                    self?.choose("Skip Amount", AppSettings.skipIntervalChoices, current: { $0 == s.skipInterval }, from: src) {
                        s.skipInterval = $0
                    }
                },
                .toggle("Skip intro, recap & credits button", s.skipSegments) { [weak self] on in
                    s.skipSegments = on
                    self?.rebuild()
                },
            ]
        if s.skipSegments {
            playerRows.append(.toggle("Skip them automatically", s.autoSkipSegments) { s.autoSkipSegments = $0 })
        }


        return [
            Section(title: "Profiles", footer: nil, rows: [
                .value("Profiles", profiles.profiles.count > 1 ? "\(profiles.current.name) · \(profiles.profiles.count) profiles" : profiles.current.name) { [weak self] _ in
                    self?.navigationController?.pushViewController(ProfilesViewController(), animated: true)
                },
            ]),
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
                .value("Home Screen", "Reorder & hide rows") { [weak self] _ in
                    self?.navigationController?.pushViewController(CustomizeHomeViewController(), animated: true)
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
            Section(title: "Compatibility", footer: compatFooter, rows: [
                .value("Compatibility mode", s.compatMode.title + (s.compatMode == .auto ? (s.compatActive ? " (on)" : " (off)") : "")) { [weak self] src in
                    self?.choose("Compatibility Mode", AppSettings.CompatMode.allCases.map { ($0, $0.title) },
                                 current: { $0 == s.compatMode }, from: src) { s.compatMode = $0 }
                },
                .toggle("Hide HEVC, AV1, 10-bit & HDR streams", s.hideHeavyStreams) { s.hideHeavyStreams = $0 },
            ]),
            Section(title: "Player", footer: "Gestures: double-tap the sides to skip, swipe up or down on the left for brightness and on the right for volume, swipe sideways to seek, pinch to fill. Intro, recap and credits times come from IntroDB and AniSkip.", rows: playerRows),
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
            Section(title: "Backup", footer: "Backs up addons, profiles, libraries, watched marks, Home layouts and settings. Account sign-ins and downloads aren't included. Backups are saved in Files → On My iPhone/iPad → Lumen → Backups.", rows: [
                .action("Back Up Now", destructive: false) { [weak self] src in self?.backUp(from: src) },
                .action("Restore from Backup…", destructive: false) { [weak self] _ in self?.pickBackup() },
            ]),
            Section(title: "About", footer: nil, rows: [
                .info("Version", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String),
            ]),
        ]
    }

    // MARK: Backup

    private func backUp(from source: UIView) {
        do {
            let url = try Backup.export()
            let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let pop = share.popoverPresentationController {
                pop.sourceView = source
                pop.sourceRect = source.bounds
            }
            present(share, animated: true)
        } catch {
            showAlert("Backup failed", error.localizedDescription)
        }
    }

    private func pickBackup() {
        let picker = UIDocumentPickerViewController(documentTypes: [kUTTypePropertyList as String, kUTTypeXML as String, kUTTypeData as String],
                                                    in: .import)
        picker.delegate = self
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let confirm = UIAlertController(title: "Restore this backup?",
                                        message: "Your current addons, profiles, libraries and settings will be replaced.",
                                        preferredStyle: .alert)
        confirm.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        confirm.addAction(UIAlertAction(title: "Restore", style: .destructive) { [weak self] _ in
            do {
                let summary = try Backup.restore(from: url)
                self?.rebuild()
                self?.showAlert("Restored", "\(summary.addons) addons and \(summary.profiles) profile\(summary.profiles == 1 ? "" : "s") restored.")
            } catch {
                self?.showAlert("Couldn't restore", error.localizedDescription)
            }
        })
        present(confirm, animated: true)
    }
}
