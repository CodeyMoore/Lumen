import UIKit
import MediaPlayer
import AVFoundation

/// What's being played, with enough context to find the next episode.
struct PlaybackContext {
    var ref: MediaRef
    var videoId: String
    var label: String?
    var meta: MetaItem?
    var addonId: String?
    var bingeGroup: String?
}

/// Full-screen player with custom controls on top of either engine.
final class PlayerViewController: UIViewController, UIGestureRecognizerDelegate {
    enum EngineKind {
        case vlc, avPlayer
    }

    private var context: PlaybackContext
    private var url: URL
    private var headers: [String: String]
    private var engine: PlayerEngine
    private var engineKind: EngineKind

    // Controls
    private let controls = PassthroughView()
    private let touchSurface = UIView()
    private let topShade = GradientView()
    private let bottomShade = GradientView()
    private let closeButton = UIButton(type: .custom)
    private let titleLabel = UILabel()
    private let tracksButton = UIButton(type: .custom)
    private let fillButton = UIButton(type: .custom)
    private let speedButton = UIButton(type: .custom)
    private let playButton = UIButton(type: .custom)
    private let backButton = UIButton(type: .custom)
    private let forwardButton = UIButton(type: .custom)
    private let slider = UISlider()
    private let timeLabel = UILabel()
    private let remainingLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .whiteLarge)
    private let subtitleLabel = UILabel()
    private let toast = UILabel()

    // Up Next
    private let upNextCard = UIView()
    private let upNextTitle = UILabel()
    private let upNextButton = UIButton(type: .custom)
    private let upNextCancel = UIButton(type: .custom)

    private var tickTimer: Timer?
    private var hideTimer: Timer?
    private var isScrubbing = false
    private var showingPause = false
    private var wasPlaying = false
    private var lastSaved = Date.distantPast
    private var closed = false
    private var failureShown = false
    private var pendingFractionResume: Double?

    private var addonSubtitles: [SubtitleTrack] = []
    private var cues: [SubtitleCue] = []
    private var currentCueText: String?
    private var activeAddonSubtitle: String?
    private var subtitleDelay: Double = 0
    private var userPickedSubtitle = false

    // Gestures
    private let hud = UILabel()
    private var hudTimer: Timer?
    private let volumeView = MPVolumeView(frame: CGRect(x: -100, y: -100, width: 10, height: 10))
    private enum PanMode { case none, brightness, volume, seek }
    private var panMode = PanMode.none
    private var panStartValue: Float = 0
    private var panStartTime: Double = 0
    private var panTargetTime: Double = 0

    // Skip intro / recap / credits
    private let skipButton = UIButton(type: .custom)
    private var segments: [SkipSegment] = []
    private var autoSkipped: Set<Double> = []
    private var activeSegment: SkipSegment?

    private var nextVideo: Video?
    private var upNextCancelled = false
    private var upNextCountdown = 0
    private var upNextTimer: Timer?
    private var loadingNext = false

    init(context: PlaybackContext, url: URL, headers: [String: String], engine kind: EngineKind) {
        self.context = context
        self.url = url
        self.headers = headers
        self.engineKind = kind
        self.engine = kind == .vlc ? VLCEngine() : AVEngine()
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        tickTimer?.invalidate()
        hideTimer?.invalidate()
        upNextTimer?.invalidate()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .landscapeRight }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var prefersStatusBarHidden: Bool { true }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        installEngineView()
        buildSubtitleLabel()
        buildControls()
        buildUpNext()
        buildToast()

        let tap = UITapGestureRecognizer(target: self, action: #selector(viewTapped(_:)))
        tap.delegate = self
        tap.cancelsTouchesInView = false
        // A dedicated layer above the video catches "show/hide controls" taps, so nothing the
        // video engine adds can intercept them.
        touchSurface.backgroundColor = .clear
        touchSurface.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(touchSurface, aboveSubview: engine.view)
        NSLayoutConstraint.activate([
            touchSurface.topAnchor.constraint(equalTo: view.topAnchor),
            touchSurface.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            touchSurface.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            touchSurface.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        touchSurface.addGestureRecognizer(tap)
        if AppSettings.shared.gesturesEnabled { installGestures(singleTap: tap) }
        buildSkipButton()
        buildHUD()

        startCurrent()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        showControls()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
        if isBeingDismissed { finishSession() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if engine.fill { engine.fill = true } // recompute crop for the new size
    }

    private func installEngineView() {
        let v = engine.view
        v.translatesAutoresizingMaskIntoConstraints = false
        // The video layer never needs touches; VLC adds its own recognizers to it otherwise.
        v.isUserInteractionEnabled = false
        view.insertSubview(v, at: 0)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: view.topAnchor),
            v.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            v.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func startCurrent() {
        failureShown = false
        upNextCancelled = false
        hideUpNext()
        titleLabel.text = context.label.map { "\(context.ref.name) · \($0)" } ?? context.ref.name

        var startAt: Double = 0
        pendingFractionResume = nil
        if let p = LibraryStore.shared.progress(for: context.videoId) {
            if p.isFraction == true {
                pendingFractionResume = p.fraction
            } else if p.position > 10 {
                startAt = p.position
            }
        }
        engine.load(url: url, headers: headers, startAt: startAt)
        wasPlaying = false

        cues = []
        currentCueText = nil
        activeAddonSubtitle = nil
        userPickedSubtitle = false
        setSubtitleText(nil)
        loadAddonSubtitles()
        computeNextVideo()
        loadSkipSegments()
    }

    // MARK: Tick

    private func tick() {
        guard !closed else { return }
        let state = engine.state
        if case .failed(let message) = state {
            spinner.stopAnimating()
            handleFailure(message)
            return
        }

        var loading = engine.isBuffering
        if case .loading = state { loading = true }
        if loading { spinner.startAnimating() } else { spinner.stopAnimating() }

        var playing = false
        if case .playing = state { playing = true }
        if playing != showingPause {
            showingPause = playing
            playButton.setImage(playing ? Icons.bigPause : Icons.bigPlay, for: .normal)
        }

        // Keep the video layer underneath the controls even if the engine reshuffles views.
        if view.subviews.first !== engine.view { view.sendSubviewToBack(engine.view) }

        let t = engine.currentTime
        let d = engine.duration
        if let f = pendingFractionResume, d > 0 {
            pendingFractionResume = nil
            if f < 0.95 { engine.seek(to: f * d) }
        }
        if !isScrubbing {
            slider.value = d > 0 ? Float(t / d) : 0
            updateTimeLabels(t, d)
        }

        if playing != wasPlaying {
            AccountSync.playback(playing ? .start : .pause, ref: context.ref, videoId: context.videoId,
                                 position: t, duration: d)
            wasPlaying = playing
        }

        updateSubtitle(at: t)
        updateSkipSegment(at: t, playing: playing)

        if d > 0, Date().timeIntervalSince(lastSaved) > 10 { saveProgress() }

        if AppSettings.shared.autoplayNext, nextVideo != nil, !upNextCancelled, !loadingNext,
           d > 120, d - t <= 20, t > 0, upNextCard.isHidden {
            showUpNext()
        }

        if case .ended = state { handleEnded() }
    }

    private func updateTimeLabels(_ t: Double, _ d: Double) {
        timeLabel.text = PlayerViewController.format(t)
        remainingLabel.text = d > 0 ? "-" + PlayerViewController.format(max(0, d - t)) : "--:--"
    }

    static func format(_ seconds: Double) -> String {
        let s = Int(max(0, seconds))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    private func saveProgress() {
        let d = engine.duration
        guard d > 0 else { return }
        lastSaved = Date()
        LibraryStore.shared.updateProgress(ref: context.ref, videoId: context.videoId, label: context.label,
                                           position: engine.currentTime, duration: d, next: nextVideo)
    }

    private func finishSession() {
        guard !closed else { return }
        closed = true
        tickTimer?.invalidate()
        upNextTimer?.invalidate()
        saveProgress()
        AccountSync.playback(.stop, ref: context.ref, videoId: context.videoId,
                             position: engine.currentTime, duration: engine.duration)
        engine.stop()
    }

    @objc private func closeTapped() {
        finishSession()
        dismiss(animated: true)
    }

    private func handleEnded() {
        guard !loadingNext else { return }
        let d = engine.duration
        if d > 0 {
            LibraryStore.shared.updateProgress(ref: context.ref, videoId: context.videoId, label: context.label,
                                               position: d, duration: d, next: nextVideo)
        }
        AccountSync.playback(.stop, ref: context.ref, videoId: context.videoId, position: d, duration: d)
        if AppSettings.shared.autoplayNext, nextVideo != nil, !upNextCancelled {
            playNext()
        } else {
            closeTapped()
        }
    }

    private func handleFailure(_ message: String) {
        guard !failureShown else { return }
        failureShown = true
        let alert = UIAlertController(title: "Can't play this stream", message: message, preferredStyle: .alert)
        if engineKind == .avPlayer {
            alert.addAction(UIAlertAction(title: "Try the VLC Engine", style: .default) { [weak self] _ in
                self?.switchEngine(to: .vlc)
            })
        }
        for p in [ExternalPlayer.vlc, ExternalPlayer.infuse] {
            alert.addAction(UIAlertAction(title: "Open in \(p.name)", style: .default) { [weak self] _ in
                guard let self = self else { return }
                let url = self.url
                let presenter = self.presentingViewController
                self.finishSession()
                self.dismiss(animated: true) { p.open(url, from: presenter) }
            })
        }
        alert.addAction(UIAlertAction(title: "Close", style: .cancel) { [weak self] _ in self?.closeTapped() })
        present(alert, animated: true)
    }

    private func switchEngine(to kind: EngineKind) {
        engine.stop()
        engine.view.removeFromSuperview()
        engineKind = kind
        engine = kind == .vlc ? VLCEngine() : AVEngine()
        installEngineView()
        startCurrent()
    }

    // MARK: Controls UI

    private func styleTextButton(_ b: UIButton, _ title: String) {
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        b.setTitleColor(.white, for: .normal)
        b.setTitleColor(UIColor(white: 1, alpha: 0.5), for: .highlighted)
        b.contentEdgeInsets = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
    }

    private func buildControls() {
        controls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controls)
        topShade.colors = [UIColor(white: 0, alpha: 0.75), UIColor(white: 0, alpha: 0)]
        topShade.isUserInteractionEnabled = false
        bottomShade.isUserInteractionEnabled = false
        bottomShade.colors = [UIColor(white: 0, alpha: 0), UIColor(white: 0, alpha: 0.8)]

        closeButton.setImage(Icons.close, for: .normal)
        closeButton.tintColor = .white
        closeButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)

        styleTextButton(speedButton, "1×")
        speedButton.addTarget(self, action: #selector(speedTapped), for: .touchUpInside)
        styleTextButton(fillButton, "Fill")
        fillButton.addTarget(self, action: #selector(fillTapped), for: .touchUpInside)
        styleTextButton(tracksButton, "Audio & Subs")
        tracksButton.addTarget(self, action: #selector(tracksTapped), for: .touchUpInside)

        playButton.tintColor = .white
        playButton.setImage(Icons.bigPlay, for: .normal)
        playButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
        styleTextButton(backButton, "−\(AppSettings.shared.skipInterval)s")
        backButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        styleTextButton(forwardButton, "+\(AppSettings.shared.skipInterval)s")
        forwardButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        forwardButton.addTarget(self, action: #selector(forwardTapped), for: .touchUpInside)

        slider.minimumTrackTintColor = Theme.accent
        slider.maximumTrackTintColor = UIColor(white: 1, alpha: 0.3)
        slider.addTarget(self, action: #selector(scrubStart), for: .touchDown)
        slider.addTarget(self, action: #selector(scrubMove), for: .valueChanged)
        slider.addTarget(self, action: #selector(scrubEnd), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        for l in [timeLabel, remainingLabel] {
            l.textColor = .white
            l.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            l.text = "0:00"
        }

        let rightStack = UIStackView(arrangedSubviews: [speedButton, fillButton, tracksButton])
        rightStack.spacing = 2
        let centerStack = UIStackView(arrangedSubviews: [backButton, playButton, forwardButton])
        centerStack.spacing = 36
        centerStack.alignment = .center

        for v in [topShade, bottomShade, closeButton, titleLabel, rightStack, centerStack,
                  timeLabel, slider, remainingLabel] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            controls.addSubview(v)
        }
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        spinner.isUserInteractionEnabled = false
        view.addSubview(spinner)

        let safe = view.safeAreaLayoutGuide
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            controls.topAnchor.constraint(equalTo: view.topAnchor),
            controls.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            controls.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            topShade.topAnchor.constraint(equalTo: controls.topAnchor),
            topShade.leadingAnchor.constraint(equalTo: controls.leadingAnchor),
            topShade.trailingAnchor.constraint(equalTo: controls.trailingAnchor),
            topShade.bottomAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 30),

            bottomShade.bottomAnchor.constraint(equalTo: controls.bottomAnchor),
            bottomShade.leadingAnchor.constraint(equalTo: controls.leadingAnchor),
            bottomShade.trailingAnchor.constraint(equalTo: controls.trailingAnchor),
            bottomShade.topAnchor.constraint(equalTo: slider.topAnchor, constant: -40),

            closeButton.topAnchor.constraint(equalTo: safe.topAnchor, constant: 6),
            closeButton.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 8),

            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -8),

            rightStack.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            rightStack.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -8),

            centerStack.centerXAnchor.constraint(equalTo: controls.centerXAnchor),
            centerStack.centerYAnchor.constraint(equalTo: controls.centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 64),
            playButton.heightAnchor.constraint(equalToConstant: 64),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            timeLabel.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
            timeLabel.centerYAnchor.constraint(equalTo: slider.centerYAnchor),
            timeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 48),
            remainingLabel.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            remainingLabel.centerYAnchor.constraint(equalTo: slider.centerYAnchor),
            remainingLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 52),
            slider.leadingAnchor.constraint(equalTo: timeLabel.trailingAnchor, constant: 10),
            slider.trailingAnchor.constraint(equalTo: remainingLabel.leadingAnchor, constant: -10),
            slider.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -12),
        ])
        remainingLabel.textAlignment = .right
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Let buttons and the slider handle their own touches.
        var v: UIView? = touch.view
        while let current = v {
            if current is UIControl { return false }
            if current === upNextCard { return false }
            v = current.superview
        }
        return true
    }

    @objc private func viewTapped(_ gr: UITapGestureRecognizer) {
        if controls.alpha > 0.5 { hideControls() } else { showControls() }
    }

    private func showControls() {
        UIView.animate(withDuration: 0.2) { self.controls.alpha = 1 }
        scheduleHide()
    }

    private func hideControls() {
        hideTimer?.invalidate()
        UIView.animate(withDuration: 0.25) { self.controls.alpha = 0 }
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            guard let self = self, !self.isScrubbing else { return }
            if case .playing = self.engine.state { self.hideControls() }
        }
    }

    @objc private func playPauseTapped() {
        if case .playing = engine.state { engine.pause() } else { engine.play() }
        scheduleHide()
    }

    @objc private func backTapped() {
        engine.seek(to: max(0, engine.currentTime - Double(AppSettings.shared.skipInterval)))
        scheduleHide()
    }

    @objc private func forwardTapped() {
        let d = engine.duration
        let target = engine.currentTime + Double(AppSettings.shared.skipInterval)
        engine.seek(to: d > 0 ? min(d - 1, target) : target)
        scheduleHide()
    }

    @objc private func scrubStart() {
        isScrubbing = true
        hideTimer?.invalidate()
    }

    @objc private func scrubMove() {
        let d = engine.duration
        updateTimeLabels(Double(slider.value) * d, d)
    }

    @objc private func scrubEnd() {
        let d = engine.duration
        if d > 0 { engine.seek(to: Double(slider.value) * d) }
        isScrubbing = false
        scheduleHide()
    }

    @objc private func fillTapped() {
        engine.fill.toggle()
        fillButton.setTitle(engine.fill ? "Fit" : "Fill", for: .normal)
        scheduleHide()
    }

    @objc private func speedTapped() {
        let sheet = UIAlertController(title: "Playback Speed", message: nil, preferredStyle: .actionSheet)
        for r: Float in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0] {
            let label = r == 1 ? "Normal" : String(format: "%g×", r)
            sheet.addAction(UIAlertAction(title: (engine.rate == r ? "✓ " : "") + label, style: .default) { [weak self] _ in
                self?.engine.rate = r
                self?.speedButton.setTitle(String(format: "%g×", r), for: .normal)
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentSheet(sheet, from: speedButton)
    }

    // MARK: Tracks

    @objc private func tracksTapped() {
        hideTimer?.invalidate()
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let audio = engine.audioTracks()
        if audio.count > 1 {
            sheet.addAction(UIAlertAction(title: "Audio Track…", style: .default) { [weak self] _ in self?.showAudioMenu() })
        }
        sheet.addAction(UIAlertAction(title: "Subtitles…", style: .default) { [weak self] _ in self?.showSubtitleMenu() })
        if activeAddonSubtitle != nil {
            let delay = subtitleDelay == 0 ? "" : String(format: " (now %+.1fs)", subtitleDelay)
            sheet.addAction(UIAlertAction(title: "Subtitle Timing\(delay)…", style: .default) { [weak self] _ in
                self?.showDelayMenu()
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentSheet(sheet, from: tracksButton)
    }

    private func showAudioMenu() {
        let sheet = UIAlertController(title: "Audio", message: nil, preferredStyle: .actionSheet)
        let current = engine.currentAudioTrack
        for t in engine.audioTracks() {
            sheet.addAction(UIAlertAction(title: (t.id == current ? "✓ " : "") + t.name, style: .default) { [weak self] _ in
                self?.engine.selectAudioTrack(t.id)
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentSheet(sheet, from: tracksButton)
    }

    private func showSubtitleMenu() {
        let sheet = UIAlertController(title: "Subtitles", message: nil, preferredStyle: .actionSheet)
        let embedded = engine.embeddedSubtitles()
        let currentEmbedded = engine.currentEmbeddedSubtitle
        let off = activeAddonSubtitle == nil && !embedded.contains { $0.id == currentEmbedded }
        sheet.addAction(UIAlertAction(title: (off ? "✓ " : "") + "Off", style: .default) { [weak self] _ in
            self?.userPickedSubtitle = true
            self?.engine.selectEmbeddedSubtitle(-1)
            self?.selectAddonSubtitle(nil)
        })
        for t in embedded {
            let selected = activeAddonSubtitle == nil && t.id == currentEmbedded
            sheet.addAction(UIAlertAction(title: (selected ? "✓ " : "") + "\(t.name) (in video)", style: .default) { [weak self] _ in
                self?.userPickedSubtitle = true
                self?.selectAddonSubtitle(nil)
                self?.engine.selectEmbeddedSubtitle(t.id)
            })
        }
        var counts: [String: Int] = [:]
        for track in addonSubtitles.prefix(30) {
            let name = SubtitleParser.languageName(track.lang)
            counts[name, default: 0] += 1
            let title = "\(track.id == activeAddonSubtitle ? "✓ " : "")\(name) \(counts[name] ?? 1)"
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.userPickedSubtitle = true
                self?.engine.selectEmbeddedSubtitle(-1)
                self?.selectAddonSubtitle(track)
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentSheet(sheet, from: tracksButton)
    }

    private func showDelayMenu() {
        let sheet = UIAlertController(title: "Subtitle Timing",
                                      message: String(format: "Current offset: %+.1fs", subtitleDelay),
                                      preferredStyle: .actionSheet)
        for step in [-1.0, -0.5, 0.5, 1.0] {
            let title = step < 0 ? String(format: "Show Earlier (%.1fs)", step) : String(format: "Show Later (+%.1fs)", step)
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.subtitleDelay += step
                self?.showToast(String(format: "Subtitles %+.1fs", self?.subtitleDelay ?? 0))
            })
        }
        sheet.addAction(UIAlertAction(title: "Reset", style: .default) { [weak self] _ in self?.subtitleDelay = 0 })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentSheet(sheet, from: tracksButton)
    }

    // MARK: Subtitles

    private func buildSubtitleLabel() {
        subtitleLabel.numberOfLines = 0
        subtitleLabel.textAlignment = .center
        subtitleLabel.isHidden = true
        subtitleLabel.layer.shadowColor = UIColor.black.cgColor
        subtitleLabel.layer.shadowOffset = CGSize(width: 0, height: 1)
        subtitleLabel.layer.shadowRadius = 3
        subtitleLabel.layer.shadowOpacity = 1
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subtitleLabel)
        NSLayoutConstraint.activate([
            subtitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -56),
        ])
    }

    private func setSubtitleText(_ text: String?) {
        guard let text = text else {
            subtitleLabel.isHidden = true
            subtitleLabel.attributedText = nil
            return
        }
        let settings = AppSettings.shared
        let size = max(16, min(34, min(view.bounds.width, view.bounds.height * 1.7) * 0.034)) * CGFloat(settings.subtitleScale)
        var attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: UIColor.white,
        ]
        if settings.subtitleBackground {
            attrs[.backgroundColor] = UIColor(white: 0, alpha: 0.6)
        } else {
            attrs[.strokeColor] = UIColor.black
            attrs[.strokeWidth] = -3.0
        }
        subtitleLabel.attributedText = NSAttributedString(string: text, attributes: attrs)
        subtitleLabel.isHidden = false
    }

    private func updateSubtitle(at t: Double) {
        guard !cues.isEmpty else { return }
        let text = SubtitleParser.cue(at: t - subtitleDelay, in: cues)?.text
        if text != currentCueText {
            currentCueText = text
            setSubtitleText(text)
        }
    }

    private func loadAddonSubtitles() {
        addonSubtitles = []
        let videoId = context.videoId
        let addons = AddonStore.shared.addons(supporting: "subtitles", type: context.ref.type, id: videoId)
        guard !addons.isEmpty else { return }
        var collected: [SubtitleTrack] = []
        let group = DispatchGroup()
        for addon in addons {
            group.enter()
            StremioAPI.shared.subtitles(addon: addon, type: context.ref.type, id: videoId) { result in
                if case .success(let tracks) = result { collected += tracks }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self = self, self.context.videoId == videoId else { return }
            self.addonSubtitles = SubtitleParser.sortedByPreference(collected)
            self.autoSelectSubtitle()
        }
    }

    private func autoSelectSubtitle() {
        let lang = AppSettings.shared.subtitleLanguage
        guard !lang.isEmpty, !userPickedSubtitle, activeAddonSubtitle == nil else { return }
        if let track = addonSubtitles.first(where: { SubtitleParser.twoLetter($0.lang) == lang }) {
            selectAddonSubtitle(track)
        }
    }

    private func selectAddonSubtitle(_ track: SubtitleTrack?) {
        cues = []
        currentCueText = nil
        setSubtitleText(nil)
        guard let track = track else { activeAddonSubtitle = nil; return }
        activeAddonSubtitle = track.id
        guard let url = StreamItem.makeURL(track.url) else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let parsed = data.flatMap(SubtitleParser.decode).map(SubtitleParser.parse) ?? []
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.activeAddonSubtitle == track.id else { return }
                self.cues = parsed
                if parsed.isEmpty && self.userPickedSubtitle {
                    self.showToast("Couldn't read those subtitles")
                }
            }
        }.resume()
    }

    // MARK: Up Next

    private func computeNextVideo() {
        nextVideo = context.meta.flatMap { Episodes.next(after: context.videoId, in: $0.videos) }
    }

    private func buildUpNext() {
        upNextCard.backgroundColor = UIColor(white: 0.08, alpha: 0.92)
        upNextCard.layer.cornerRadius = 12
        upNextCard.isHidden = true
        upNextTitle.textColor = .white
        upNextTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        upNextTitle.numberOfLines = 2

        upNextButton.backgroundColor = Theme.accent
        upNextButton.layer.cornerRadius = 8
        upNextButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        upNextButton.setTitleColor(.white, for: .normal)
        upNextButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        upNextButton.addTarget(self, action: #selector(upNextNow), for: .touchUpInside)

        upNextCancel.setTitle("Cancel", for: .normal)
        upNextCancel.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        upNextCancel.setTitleColor(UIColor(white: 1, alpha: 0.75), for: .normal)
        upNextCancel.contentEdgeInsets = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        upNextCancel.addTarget(self, action: #selector(upNextCancelTapped), for: .touchUpInside)

        let buttons = UIStackView(arrangedSubviews: [upNextCancel, upNextButton])
        buttons.spacing = 8
        let stack = UIStackView(arrangedSubviews: [upNextTitle, buttons])
        stack.axis = .vertical
        stack.spacing = 10
        stack.alignment = .trailing
        stack.translatesAutoresizingMaskIntoConstraints = false
        upNextCard.addSubview(stack)
        upNextCard.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(upNextCard)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: upNextCard.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: upNextCard.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: upNextCard.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: upNextCard.trailingAnchor, constant: -12),
            upNextCard.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            upNextCard.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -64),
            upNextCard.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
        ])
    }

    private func showUpNext() {
        guard let next = nextVideo else { return }
        upNextTitle.text = "Up Next\n\(next.longLabel)"
        upNextCountdown = 15
        upNextButton.setTitle("Play Now", for: .normal)
        upNextCard.isHidden = false
        upNextCard.alpha = 0
        UIView.animate(withDuration: 0.25) { self.upNextCard.alpha = 1 }
        upNextTimer?.invalidate()
        upNextTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.upNextCountdown -= 1
            self.upNextButton.setTitle("Play in \(max(0, self.upNextCountdown))", for: .normal)
            if self.upNextCountdown <= 0 {
                self.upNextTimer?.invalidate()
                self.playNext()
            }
        }
    }

    private func hideUpNext() {
        upNextTimer?.invalidate()
        upNextCard.isHidden = true
    }

    @objc private func upNextNow() { playNext() }

    @objc private func upNextCancelTapped() {
        upNextCancelled = true
        hideUpNext()
    }

    private func playNext() {
        guard let next = nextVideo, !loadingNext else { return }
        loadingNext = true
        hideUpNext()
        let d = engine.duration
        if d > 0 {
            LibraryStore.shared.updateProgress(ref: context.ref, videoId: context.videoId, label: context.label,
                                               position: d, duration: d, next: nextVideo)
        }
        AccountSync.playback(.stop, ref: context.ref, videoId: context.videoId, position: d, duration: d)
        engine.pause()
        spinner.startAnimating()
        showToast("Finding a stream for \(next.shortLabel)…")

        StreamFetcher.fetch(type: context.ref.type, videoId: next.id) { [weak self] streams in
            guard let self = self, !self.closed else { return }
            self.loadingNext = false
            guard let pick = StreamRanker.best(streams, bingeGroup: self.context.bingeGroup, addonId: self.context.addonId),
                  case .direct(let url) = pick.stream.kind else {
                self.spinner.stopAnimating()
                self.upNextCancelled = true
                let alert = UIAlertController(title: "No playable stream",
                                              message: "Couldn't find a stream for \(next.longLabel).",
                                              preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Close Player", style: .default) { [weak self] _ in self?.closeTapped() })
                alert.addAction(UIAlertAction(title: "Stay", style: .cancel))
                self.present(alert, animated: true)
                return
            }
            self.context.videoId = next.id
            self.context.label = next.longLabel
            self.context.addonId = pick.addon.manifest.id
            self.context.bingeGroup = pick.stream.bingeGroup ?? self.context.bingeGroup
            self.url = url
            self.headers = pick.stream.headers
            self.lastSaved = Date.distantPast
            self.startCurrent()
            self.showControls()
        }
    }

    // MARK: Gestures

    private func installGestures(singleTap: UITapGestureRecognizer) {
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        touchSurface.addGestureRecognizer(doubleTap)
        singleTap.require(toFail: doubleTap)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        touchSurface.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        pinch.delegate = self
        touchSurface.addGestureRecognizer(pinch)

        // An on-screen (but invisible) volume view lets swipes change the system volume
        // without iOS showing its own volume overlay.
        volumeView.alpha = 0.01
        volumeView.isUserInteractionEnabled = false
        view.addSubview(volumeView)
    }

    private var volumeSlider: UISlider? {
        volumeView.subviews.compactMap { $0 as? UISlider }.first
    }

    @objc private func doubleTapped(_ gr: UITapGestureRecognizer) {
        let x = gr.location(in: view).x
        let w = view.bounds.width
        let step = Double(AppSettings.shared.skipInterval)
        if x < w / 3 {
            engine.seek(to: max(0, engine.currentTime - step))
            showHUD("−\(Int(step))s")
        } else if x > w * 2 / 3 {
            let d = engine.duration
            let target = engine.currentTime + step
            engine.seek(to: d > 0 ? min(d - 1, target) : target)
            showHUD("+\(Int(step))s")
        } else {
            playPauseTapped()
        }
    }

    @objc private func panned(_ gr: UIPanGestureRecognizer) {
        let size = view.bounds.size
        switch gr.state {
        case .began:
            let v = gr.velocity(in: view)
            let start = gr.location(in: view)
            if abs(v.x) > abs(v.y) {
                guard engine.duration > 0 else { panMode = .none; return }
                panMode = .seek
                panStartTime = engine.currentTime
                panTargetTime = panStartTime
                hideTimer?.invalidate()
            } else if start.x < size.width / 2 {
                panMode = .brightness
                panStartValue = Float(UIScreen.main.brightness)
            } else {
                panMode = .volume
                panStartValue = AVAudioSession.sharedInstance().outputVolume
            }
        case .changed:
            let t = gr.translation(in: view)
            switch panMode {
            case .brightness:
                let value = min(1, max(0, panStartValue - Float(t.y / (size.height * 0.8))))
                UIScreen.main.brightness = CGFloat(value)
                showHUD("Brightness \(Int(value * 100))%")
            case .volume:
                let value = min(1, max(0, panStartValue - Float(t.y / (size.height * 0.8))))
                volumeSlider?.setValue(value, animated: false)
                volumeSlider?.sendActions(for: .valueChanged)
                showHUD("Volume \(Int(value * 100))%")
            case .seek:
                let d = engine.duration
                // One screen width ≈ 2 minutes (or the whole video if shorter).
                let span = min(d, 120)
                panTargetTime = min(max(0, panStartTime + Double(t.x / size.width) * span), max(0, d - 1))
                let delta = panTargetTime - panStartTime
                let sign = delta < 0 ? "−" : "+"
                showHUD("\(PlayerViewController.format(panTargetTime)) / \(PlayerViewController.format(d))   \(sign)\(PlayerViewController.format(abs(delta)))")
            case .none:
                break
            }
        case .ended:
            if panMode == .seek { engine.seek(to: panTargetTime) }
            panMode = .none
            scheduleHide()
        case .cancelled, .failed:
            panMode = .none
        default:
            break
        }
    }

    @objc private func pinched(_ gr: UIPinchGestureRecognizer) {
        guard gr.state == .ended else { return }
        if gr.scale > 1.15 && !engine.fill {
            engine.fill = true
        } else if gr.scale < 0.87 && engine.fill {
            engine.fill = false
        } else {
            return
        }
        fillButton.setTitle(engine.fill ? "Fit" : "Fill", for: .normal)
        showHUD(engine.fill ? "Fill screen" : "Fit to screen")
    }

    private func buildHUD() {
        hud.textColor = .white
        hud.font = UIFont.monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        hud.backgroundColor = UIColor(white: 0, alpha: 0.65)
        hud.textAlignment = .center
        hud.layer.cornerRadius = 10
        hud.clipsToBounds = true
        hud.alpha = 0
        hud.isUserInteractionEnabled = false
        hud.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hud)
        NSLayoutConstraint.activate([
            hud.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hud.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -70),
            hud.heightAnchor.constraint(equalToConstant: 44),
            hud.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -40),
        ])
    }

    private func showHUD(_ text: String) {
        hud.text = "    \(text)    "
        hud.alpha = 1
        hudTimer?.invalidate()
        hudTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: false) { [weak self] _ in
            UIView.animate(withDuration: 0.25) { self?.hud.alpha = 0 }
        }
    }

    // MARK: Skip intro / recap / credits

    private func buildSkipButton() {
        skipButton.backgroundColor = UIColor(white: 0.1, alpha: 0.85)
        skipButton.layer.cornerRadius = 8
        skipButton.layer.borderWidth = 1
        skipButton.layer.borderColor = UIColor(white: 1, alpha: 0.35).cgColor
        skipButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        skipButton.setTitleColor(.white, for: .normal)
        skipButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        skipButton.isHidden = true
        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
        skipButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(skipButton)
        NSLayoutConstraint.activate([
            skipButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            skipButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -64),
        ])
    }

    private func loadSkipSegments() {
        segments = []
        autoSkipped = []
        activeSegment = nil
        skipButton.isHidden = true
        guard AppSettings.shared.skipSegments, context.ref.type != "movie" else { return }
        let videoId = context.videoId
        SkipSegmentService.fetch(videoId: videoId) { [weak self] found in
            guard let self = self, self.context.videoId == videoId else { return }
            self.segments = found
        }
    }

    private func updateSkipSegment(at t: Double, playing: Bool) {
        guard !segments.isEmpty else { return }
        let current = segments.first { t >= $0.start && t < $0.end - 1 }
        if let seg = current, AppSettings.shared.autoSkipSegments, playing, !autoSkipped.contains(seg.start) {
            autoSkipped.insert(seg.start)
            skip(seg)
            return
        }
        let show = current != nil && upNextCard.isHidden
        if show, let seg = current, activeSegment?.start != seg.start {
            skipButton.setTitle(seg.kind.buttonTitle, for: .normal)
        }
        activeSegment = show ? current : nil
        if skipButton.isHidden == show {
            skipButton.isHidden = !show
            view.bringSubviewToFront(skipButton)
        }
    }

    @objc private func skipTapped() {
        guard let seg = activeSegment else { return }
        skip(seg)
    }

    private func skip(_ seg: SkipSegment) {
        let d = engine.duration
        engine.seek(to: d > 0 ? min(seg.end, d - 1) : seg.end)
        activeSegment = nil
        skipButton.isHidden = true
        showToast(seg.kind.doneMessage)
    }

    // MARK: Toast

    private func buildToast() {
        toast.textColor = .white
        toast.font = .systemFont(ofSize: 14, weight: .medium)
        toast.backgroundColor = UIColor(white: 0, alpha: 0.7)
        toast.textAlignment = .center
        toast.layer.cornerRadius = 8
        toast.clipsToBounds = true
        toast.alpha = 0
        toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            toast.heightAnchor.constraint(equalToConstant: 34),
            toast.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -40),
        ])
    }

    private func showToast(_ text: String) {
        toast.text = "   \(text)   "
        UIView.animate(withDuration: 0.2, animations: { self.toast.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.3, delay: 2, options: [], animations: { self.toast.alpha = 0 })
        }
    }
}

/// Full-screen container whose empty areas let touches fall through to the views below.
final class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}
