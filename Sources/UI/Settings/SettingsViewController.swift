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
        // 0 = don't skip, 1 = show a Skip button, 2 = skip automatically
        let skipModes: [(Int, String)] = [(0, "Don't skip"), (1, "Show Skip button"), (2, "Skip automatically")]
        let currentSkipMode = !s.skipSegments ? 0 : (s.autoSkipSegments ? 2 : 1)
        let playerRows: [Row] = [
                .toggle("Keep playing in the background", s.backgroundPlayback) { s.backgroundPlayback = $0 },
                .toggle("Gestures", s.gesturesEnabled) { s.gesturesEnabled = $0 },
                .value("Rewind & forward by", AppSettings.skipIntervalChoices.first { $0.0 == s.skipInterval }?.1 ?? "\(s.skipInterval) seconds") { [weak self] src in
                    self?.choose("Rewind & Forward By", AppSettings.skipIntervalChoices, current: { $0 == s.skipInterval }, from: src) {
                        s.skipInterval = $0
                    }
                },
                .value("Intros, recaps & credits", skipModes.first { $0.0 == currentSkipMode }?.1) { [weak self] src in
                    self?.choose("Intros, Recaps & Credits", skipModes, current: { $0 == currentSkipMode }, from: src) { mode in
                        s.skipSegments = mode != 0
                        s.autoSkipSegments = mode == 2
                    }
                },
            ]


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
            Section(title: "Player", footer: "Keep playing in the background: sound continues when the screen locks or you switch apps, with controls on the lock screen. On devices that support it, the iOS player also offers Picture in Picture.\n\nGestures: double-tap the left or right side to jump back or forward, swipe up or down on the left for brightness and on the right for volume, swipe sideways to seek, and pinch to fill the screen.\n\nIntros, recaps & credits: \"Show Skip button\" puts a Skip button on screen while an intro, recap or end credits play. \"Skip automatically\" jumps past them for you. This only works for shows whose timings are in the IntroDB and AniSkip databases.", rows: playerRows),
            Section(title: "Subtitles", footer: "Subtitles in your preferred language turn on automatically when an addon provides them. If you adjust subtitle timing in the player, Lumen remembers it for that show or movie. These styles apply to addon subtitles; subtitles built into a video file use the player's own style.", rows: [
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
                .value("Colour", AppSettings.subtitleColorChoices.first { $0.0 == s.subtitleColorIndex }?.1) { [weak self] src in
                    self?.choose("Subtitle Colour", AppSettings.subtitleColorChoices, current: { $0 == s.subtitleColorIndex }, from: src) {
                        s.subtitleColorIndex = $0
                    }
                },
                .value("Outline", AppSettings.subtitleOutlineChoices.first { $0.0 == s.subtitleOutline }?.1) { [weak self] src in
                    self?.choose("Subtitle Outline", AppSettings.subtitleOutlineChoices, current: { $0 == s.subtitleOutline }, from: src) {
                        s.subtitleOutline = $0
                    }
                },
                .value("Position", AppSettings.subtitlePositionChoices.first { $0.0 == s.subtitlePosition }?.1) { [weak self] src in
                    self?.choose("Subtitle Position", AppSettings.subtitlePositionChoices, current: { $0 == s.subtitlePosition }, from: src) {
                        s.subtitlePosition = $0
                    }
                },
                .toggle("Background box", s.subtitleBackground) { s.subtitleBackground = $0 },
            ]),
            Section(title: "Backup", footer: "Backs up addons, profiles, libraries, watched marks, Home layouts and settings. Account sign-ins and downloads aren't included. Backups are saved in Files → On My iPhone/iPad → Lumen → Backups.", rows: [
                .action("Back Up Now", destructive: false) { [weak self] src in self?.backUp(from: src) },
                .action("Restore from Backup…", destructive: false) { [weak self] _ in self?.pickBackup() },
            ]),
            Section(title: "About", footer: nil, rows: [
                .info("Version", {
                    let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
                    let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
                    return "\(v) (build \(b))"
                }()),
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
