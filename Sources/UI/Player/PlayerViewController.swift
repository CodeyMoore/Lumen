import UIKit
import AVKit
import AVFoundation

/// System player with resume, progress saving and an addon-subtitle overlay.
final class PlayerViewController: AVPlayerViewController, UIGestureRecognizerDelegate {
    private let ref: MediaRef
    private let videoId: String
    private let label: String?
    private let streamURL: URL
    private let headers: [String: String]

    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var lastSaved = Date.distantPast
    private var didResume = false

    private let subtitleLabel = UILabel()
    private let ccButton = UIButton(type: .custom)
    private var hideTimer: Timer?
    private var subtitleTracks: [SubtitleTrack] = []
    private var cues: [SubtitleCue] = []
    private var currentCueText: String?
    private var activeTrackId: String?
    private var subtitleDelay: Double = 0

    init(ref: MediaRef, videoId: String, label: String?, url: URL, headers: [String: String]) {
        self.ref = ref
        self.videoId = videoId
        self.label = label
        self.streamURL = url
        self.headers = headers
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let t = timeObserver { player?.removeTimeObserver(t) }
        hideTimer?.invalidate()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        allowsPictureInPicturePlayback = false
        setupPlayer()
        setupSubtitleOverlay()
        setupCCButton()
        loadSubtitleList()
    }

    // MARK: Playback

    private func setupPlayer() {
        let options: [String: Any]? = headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": headers]
        let asset = AVURLAsset(url: streamURL, options: options)
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        self.player = player

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async { self?.statusChanged(item) }
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            self?.tick(time.seconds)
        }
        player.play()
    }

    private func statusChanged(_ item: AVPlayerItem) {
        switch item.status {
        case .readyToPlay:
            guard !didResume else { return }
            didResume = true
            let saved = LibraryStore.shared.position(for: videoId)
            let duration = item.duration.seconds
            if saved > 10 && (!duration.isFinite || saved < duration - 30) {
                player?.seek(to: CMTime(seconds: saved, preferredTimescale: 600))
            }
        case .failed:
            showPlaybackError(item.error)
        default:
            break
        }
    }

    private func showPlaybackError(_ error: Error?) {
        let reason = error?.localizedDescription ?? "Unknown error"
        let alert = UIAlertController(
            title: "Can't play this stream",
            message: "\(reason)\n\nThe iOS player doesn't support MKV files and some codecs. Try an external player.",
            preferredStyle: .alert)
        for p in [ExternalPlayer.vlc, ExternalPlayer.infuse] {
            alert.addAction(UIAlertAction(title: "Open in \(p.name)", style: .default) { [weak self] _ in
                guard let self = self else { return }
                let url = self.streamURL
                let presenter = self.presentingViewController
                self.dismiss(animated: true) { p.open(url, from: presenter) }
            })
        }
        alert.addAction(UIAlertAction(title: "Close", style: .cancel) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }

    private func tick(_ seconds: Double) {
        guard seconds.isFinite else { return }
        if !cues.isEmpty {
            let text = SubtitleParser.cue(at: seconds - subtitleDelay, in: cues)?.text
            if text != currentCueText {
                currentCueText = text
                setSubtitleText(text)
            }
        }
        if Date().timeIntervalSince(lastSaved) > 5 { saveProgress() }
    }

    private func saveProgress() {
        guard didResume, let item = player?.currentItem else { return }
        let position = item.currentTime().seconds
        let duration = item.duration.seconds
        guard position.isFinite, duration.isFinite, duration > 0 else { return }
        lastSaved = Date()
        LibraryStore.shared.updateProgress(ref: ref, videoId: videoId, label: label,
                                           position: position, duration: duration)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed {
            saveProgress()
            player?.pause()
        }
    }

    // MARK: Subtitle overlay

    private func setupSubtitleOverlay() {
        guard let overlay = contentOverlayView else { return }
        subtitleLabel.numberOfLines = 0
        subtitleLabel.textAlignment = .center
        subtitleLabel.isHidden = true
        subtitleLabel.layer.shadowColor = UIColor.black.cgColor
        subtitleLabel.layer.shadowOffset = CGSize(width: 0, height: 1)
        subtitleLabel.layer.shadowRadius = 3
        subtitleLabel.layer.shadowOpacity = 1
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(subtitleLabel)
        NSLayoutConstraint.activate([
            subtitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: overlay.leadingAnchor, constant: 24),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: overlay.trailingAnchor, constant: -24),
            subtitleLabel.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.bottomAnchor, constant: -28),
        ])
    }

    private func setSubtitleText(_ text: String?) {
        guard let text = text else {
            subtitleLabel.isHidden = true
            subtitleLabel.attributedText = nil
            return
        }
        let size = max(17, min(30, view.bounds.width * 0.032))
        subtitleLabel.attributedText = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: UIColor.white,
            .strokeColor: UIColor.black,
            .strokeWidth: -3.0,
        ])
        subtitleLabel.isHidden = false
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.bringSubviewToFront(ccButton)
    }

    // MARK: CC button & menu

    private func setupCCButton() {
        ccButton.setTitle("CC", for: .normal)
        ccButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        ccButton.setTitleColor(.white, for: .normal)
        ccButton.backgroundColor = UIColor(white: 0, alpha: 0.55)
        ccButton.layer.cornerRadius = 8
        ccButton.contentEdgeInsets = UIEdgeInsets(top: 7, left: 14, bottom: 7, right: 14)
        ccButton.isHidden = true
        ccButton.alpha = 0
        ccButton.addTarget(self, action: #selector(ccTapped), for: .touchUpInside)
        ccButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(ccButton)
        NSLayoutConstraint.activate([
            ccButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 64),
            ccButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(viewTapped))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        view.addGestureRecognizer(tap)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    @objc private func viewTapped() {
        guard !subtitleTracks.isEmpty else { return }
        showCCButton()
    }

    private func showCCButton() {
        ccButton.isHidden = false
        UIView.animate(withDuration: 0.2) { self.ccButton.alpha = 1 }
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            UIView.animate(withDuration: 0.3) { self?.ccButton.alpha = 0 }
        }
    }

    private func loadSubtitleList() {
        let addons = AddonStore.shared.addons(supporting: "subtitles", type: ref.type, id: videoId)
        guard !addons.isEmpty else { return }
        var collected: [SubtitleTrack] = []
        let group = DispatchGroup()
        for addon in addons {
            group.enter()
            StremioAPI.shared.subtitles(addon: addon, type: ref.type, id: videoId) { result in
                if case .success(let tracks) = result { collected += tracks }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self = self, !collected.isEmpty else { return }
            self.subtitleTracks = SubtitleParser.sortedByPreference(collected)
            self.showCCButton()
        }
    }

    @objc private func ccTapped() {
        showCCButton()
        let message = activeTrackId != nil && subtitleDelay != 0 ? String(format: "Delay: %+.1fs", subtitleDelay) : nil
        let sheet = UIAlertController(title: "Subtitles", message: message, preferredStyle: .actionSheet)

        sheet.addAction(UIAlertAction(title: activeTrackId == nil ? "✓ Off" : "Off", style: .default) { [weak self] _ in
            self?.selectTrack(nil)
        })

        var counts: [String: Int] = [:]
        for track in subtitleTracks.prefix(40) {
            let name = SubtitleParser.languageName(track.lang)
            counts[name, default: 0] += 1
            let title = "\(track.id == activeTrackId ? "✓ " : "")\(name) \(counts[name] ?? 1)"
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.selectTrack(track)
            })
        }

        if activeTrackId != nil {
            sheet.addAction(UIAlertAction(title: "Show Earlier (−0.5s)", style: .default) { [weak self] _ in
                self?.subtitleDelay -= 0.5
            })
            sheet.addAction(UIAlertAction(title: "Show Later (+0.5s)", style: .default) { [weak self] _ in
                self?.subtitleDelay += 0.5
            })
        }

        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = ccButton
            pop.sourceRect = ccButton.bounds
        }
        present(sheet, animated: true)
    }

    private func selectTrack(_ track: SubtitleTrack?) {
        cues = []
        currentCueText = nil
        setSubtitleText(nil)
        guard let track = track else { activeTrackId = nil; return }
        activeTrackId = track.id
        guard let url = StreamItem.makeURL(track.url) else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let parsed = data.flatMap(SubtitleParser.decode).map(SubtitleParser.parse) ?? []
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.activeTrackId == track.id else { return }
                self.cues = parsed
                if parsed.isEmpty {
                    self.showAlert("Couldn't read subtitles", "This subtitle file couldn't be loaded. Try another one.")
                }
            }
        }.resume()
    }
}
