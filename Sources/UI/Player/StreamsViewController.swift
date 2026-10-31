import UIKit

final class StreamsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let ref: MediaRef
    private let videoId: String
    private let label: String?
    private let meta: MetaItem?

    private var all: [RankedStream] = []
    private var shown: [RankedStream] = []
    private var pending = 0
    private var total = 0
    private var filter: QualityFilter = .all
    private var sort: StreamSort = .quality
    private var autoPlayed = false

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let header = UIView()
    private let filterControl = UISegmentedControl(items: QualityFilter.allCases.map { $0.title })
    private let sortButton = UIButton(type: .system)
    private let bestButton = UIButton(type: .custom)
    private let statusLabel = UILabel()
    private let messageLabel = UILabel()

    init(ref: MediaRef, videoId: String, label: String?, meta: MetaItem?) {
        self.ref = ref
        self.videoId = videoId
        self.label = label
        self.meta = meta
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = label ?? ref.name
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = Theme.background

        tableView.backgroundColor = Theme.background
        tableView.separatorColor = UIColor(white: 1, alpha: 0.08)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.estimatedRowHeight = 76
        tableView.rowHeight = UITableView.automaticDimension
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        messageLabel.textColor = Theme.secondaryText
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.isHidden = true
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])

        buildHeader()
        load()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = header.systemLayoutSizeFitting(CGSize(width: tableView.bounds.width, height: 0),
                                                  withHorizontalFittingPriority: .required,
                                                  verticalFittingPriority: .fittingSizeLevel)
        if header.frame.height != size.height || header.frame.width != tableView.bounds.width {
            header.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: size.height)
            tableView.tableHeaderView = header
        }
    }

    private func buildHeader() {
        filterControl.selectedSegmentIndex = 0
        filterControl.addTarget(self, action: #selector(filterChanged), for: .valueChanged)

        sortButton.setTitle("Sort: \(sort.title) ▾", for: .normal)
        sortButton.tintColor = Theme.accent
        sortButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        sortButton.addTarget(self, action: #selector(sortTapped), for: .touchUpInside)

        bestButton.setTitle("  Play Best", for: .normal)
        bestButton.setImage(Icons.play, for: .normal)
        bestButton.tintColor = .white
        bestButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        bestButton.backgroundColor = Theme.accent
        bestButton.layer.cornerRadius = 8
        bestButton.contentEdgeInsets = UIEdgeInsets(top: 7, left: 12, bottom: 7, right: 14)
        bestButton.addTarget(self, action: #selector(bestTapped), for: .touchUpInside)
        bestButton.isEnabled = false
        bestButton.alpha = 0.5

        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = Theme.secondaryText

        let row = UIStackView(arrangedSubviews: [sortButton, UIView(), bestButton])
        row.alignment = .center
        let stack = UIStackView(arrangedSubviews: [filterControl, row, statusLabel])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: header.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
        ])
        tableView.tableHeaderView = header
    }

    private func load() {
        let addons = StreamFetcher.addons(type: ref.type, videoId: videoId)
        guard !addons.isEmpty else {
            messageLabel.text = "None of your addons provide streams for this.\n\nInstall a stream addon in Settings → Addons."
            messageLabel.isHidden = false
            tableView.isHidden = true
            return
        }
        total = addons.count
        pending = addons.count
        updateStatus()
        var byAddon: [Int: [StreamItem]] = [:]
        StreamFetcher.fetch(type: ref.type, videoId: videoId, partial: { [weak self] i, result in
            guard let self = self else { return }
            self.pending -= 1
            if case .success(let s) = result { byAddon[i] = s }
            var out: [RankedStream] = []
            var order = 0
            for (j, addon) in addons.enumerated() {
                for s in byAddon[j] ?? [] {
                    out.append(RankedStream(stream: s, addon: addon, order: order))
                    order += 1
                }
            }
            self.all = out
            self.refresh()
        }, done: { [weak self] _ in
            self?.pending = 0
            self?.refresh()
            self?.autoPlayIfNeeded()
        })
    }

    private func refresh() {
        let settings = AppSettings.shared
        let visible = all.filter { r in
            if settings.hideTorrents, case .torrent = r.stream.kind { return false }
            if StreamRanker.isHidden(r) { return false }
            return filter.matches(r.stream.quality) || filter == .all
        }
        shown = StreamRanker.sorted(visible, by: sort)
        tableView.reloadData()
        let hasBest = StreamRanker.best(all) != nil
        bestButton.isEnabled = hasBest
        bestButton.alpha = hasBest ? 1 : 0.5
        updateStatus()
    }

    private func updateStatus() {
        if pending > 0 {
            statusLabel.text = "Loading from \(pending) of \(total) addon\(total == 1 ? "" : "s")…"
        } else if shown.isEmpty {
            statusLabel.text = all.isEmpty ? "No streams found." : "No streams match this filter."
        } else {
            statusLabel.text = "\(shown.count) stream\(shown.count == 1 ? "" : "s")"
                + (AppSettings.shared.compatActive ? " · compatibility mode" : "")
        }
    }

    private func autoPlayIfNeeded() {
        guard AppSettings.shared.autoPlayBest, !autoPlayed, view.window != nil,
              let best = StreamRanker.best(all) else { return }
        autoPlayed = true
        StreamActions.play(best, context: playbackContext(for: best), from: self, source: bestButton)
    }

    private func playbackContext(for r: RankedStream) -> PlaybackContext {
        PlaybackContext(ref: ref, videoId: videoId, label: label, meta: meta,
                        addonId: r.addon.manifest.id, bingeGroup: r.stream.bingeGroup)
    }

    @objc private func filterChanged() {
        filter = QualityFilter(rawValue: filterControl.selectedSegmentIndex) ?? .all
        refresh()
    }

    @objc private func sortTapped() {
        let sheet = UIAlertController(title: "Sort Streams", message: nil, preferredStyle: .actionSheet)
        for s in StreamSort.allCases {
            sheet.addAction(UIAlertAction(title: (s == sort ? "✓ " : "") + s.title, style: .default) { [weak self] _ in
                guard let self = self else { return }
                self.sort = s
                self.sortButton.setTitle("Sort: \(s.title) ▾", for: .normal)
                self.refresh()
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentSheet(sheet, from: sortButton)
    }

    @objc private func bestTapped() {
        guard let best = StreamRanker.best(all) else { return }
        StreamActions.play(best, context: playbackContext(for: best), from: self, source: bestButton)
    }

    // MARK: Table

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { shown.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "stream")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "stream")
        cell.backgroundColor = Theme.background
        let selected = UIView()
        selected.backgroundColor = Theme.surface
        cell.selectedBackgroundView = selected
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        cell.textLabel?.textColor = Theme.text
        cell.detailTextLabel?.numberOfLines = 0
        cell.detailTextLabel?.font = .systemFont(ofSize: 12)
        cell.detailTextLabel?.textColor = Theme.secondaryText
        cell.accessoryType = .detailButton
        cell.tintColor = Theme.accent

        let r = shown[indexPath.row]
        let s = r.stream
        var badges = [s.qualityLabel, s.codec.label, s.sizeLabel, r.addon.manifest.name].compactMap { $0 }
        if AppSettings.shared.rememberAddon, r.addon.manifest.id == AppSettings.shared.preferredAddonId {
            badges.append("★")
        }
        cell.textLabel?.text = badges.joined(separator: "  ·  ")
        var detail = s.displayName
        if let t = s.title { detail += "\n" + t }
        switch s.kind {
        case .torrent: detail += "\nTorrent — not playable in Lumen"
        case .youtube: detail += "\nOpens in YouTube"
        case .external: detail += "\nOpens externally"
        default: break
        }
        if AppSettings.shared.compatActive && s.codec.isHeavy && s.isDirect {
            detail += "\nMay stutter on this device (needs newer video hardware)"
        }
        cell.detailTextLabel?.text = detail
        cell.contentView.alpha = s.isDirect ? 1 : 0.55
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let r = shown[indexPath.row]
        StreamActions.play(r, context: playbackContext(for: r), from: self, source: tableView.cellForRow(at: indexPath))
    }

    func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        let r = shown[indexPath.row]
        StreamActions.moreOptions(r, context: playbackContext(for: r), from: self, source: tableView.cellForRow(at: indexPath))
    }
}

// MARK: - Players & actions

enum ExternalPlayer: CaseIterable {
    case vlc, infuse, nplayer, outplayer

    var name: String {
        switch self {
        case .vlc: return "VLC"
        case .infuse: return "Infuse"
        case .nplayer: return "nPlayer"
        case .outplayer: return "Outplayer"
        }
    }

    func url(for stream: URL) -> URL? {
        let s = stream.absoluteString
        let encoded = StremioAPI.encode(s)
        switch self {
        case .vlc: return URL(string: "vlc-x-callback://x-callback-url/stream?url=\(encoded)")
        case .infuse: return URL(string: "infuse://x-callback-url/play?url=\(encoded)")
        case .nplayer: return URL(string: "nplayer-\(s)")
        case .outplayer: return URL(string: "outplayer://\(s)")
        }
    }

    func open(_ stream: URL, from vc: UIViewController?) {
        guard let target = url(for: stream) else { return }
        let name = self.name
        UIApplication.shared.open(target, options: [:]) { ok in
            if !ok { vc?.showAlert("\(name) isn't installed", "Install \(name) from the App Store, or pick another player in Settings.") }
        }
    }
}

enum StreamActions {
    /// Plays with the player chosen in Settings.
    static func play(_ r: RankedStream, context: PlaybackContext, from vc: UIViewController, source: UIView?) {
        let stream = r.stream
        switch stream.kind {
        case .direct(let url):
            if AppSettings.shared.rememberAddon { AppSettings.shared.preferredAddonId = r.addon.manifest.id }
            let choice = AppSettings.shared.player
            if let external = choice.external {
                external.open(url, from: vc)
            } else {
                let player = PlayerViewController(context: context, url: url, headers: stream.headers,
                                                  engine: choice == .system ? .avPlayer : .vlc)
                vc.present(player, animated: true)
            }
        case .youtube(let id):
            if let url = URL(string: "https://www.youtube.com/watch?v=\(StremioAPI.encode(id))") {
                UIApplication.shared.open(url, options: [:])
            }
        case .external(let url):
            UIApplication.shared.open(url, options: [:])
        case .torrent(let hash):
            let alert = UIAlertController(
                title: "Torrent stream",
                message: "Lumen can't play torrents directly. Use an addon that provides HTTP links instead.",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Copy Magnet Link", style: .default) { _ in
                UIPasteboard.general.string = "magnet:?xt=urn:btih:\(hash)"
            })
            alert.addAction(UIAlertAction(title: "OK", style: .cancel))
            vc.topPresenter.present(alert, animated: true)
        case .unsupported:
            vc.showAlert("Unsupported stream", "Lumen doesn't know how to open this stream.")
        }
    }

    /// Every way to open a stream, plus download and copy.
    static func moreOptions(_ r: RankedStream, context: PlaybackContext, from vc: UIViewController, source: UIView?) {
        guard case .direct(let url) = r.stream.kind else {
            play(r, context: context, from: vc, source: source)
            return
        }
        let sheet = UIAlertController(title: r.stream.displayName, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Play with VLC Engine", style: .default) { _ in
            vc.present(PlayerViewController(context: context, url: url, headers: r.stream.headers, engine: .vlc), animated: true)
        })
        sheet.addAction(UIAlertAction(title: "Play with iOS Player", style: .default) { _ in
            vc.present(PlayerViewController(context: context, url: url, headers: r.stream.headers, engine: .avPlayer), animated: true)
        })
        for p in ExternalPlayer.allCases {
            sheet.addAction(UIAlertAction(title: "Open in \(p.name)", style: .default) { _ in p.open(url, from: vc) })
        }
        sheet.addAction(UIAlertAction(title: "Download", style: .default) { _ in
            DownloadManager.shared.start(ref: context.ref, videoId: context.videoId, label: context.label,
                                         url: url, headers: r.stream.headers)
            vc.showAlert("Downloading", "Track it in Library → Downloads.")
        })
        sheet.addAction(UIAlertAction(title: "Copy Link", style: .default) { _ in
            UIPasteboard.general.string = url.absoluteString
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        vc.presentSheet(sheet, from: source)
    }
}
