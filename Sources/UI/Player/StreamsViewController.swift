import UIKit

final class StreamsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private enum State {
        case loading
        case loaded([StreamItem])
        case failed
    }

    private struct Group {
        let addon: Addon
        var state: State
    }

    private let ref: MediaRef
    private let videoId: String
    private let label: String?
    private var groups: [Group] = []

    private let tableView = UITableView(frame: .zero, style: .grouped)
    private let messageLabel = UILabel()

    init(ref: MediaRef, videoId: String, label: String?) {
        self.ref = ref
        self.videoId = videoId
        self.label = label
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
        tableView.estimatedRowHeight = 70
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

        load()
    }

    private func load() {
        let addons = AddonStore.shared.addons(supporting: "stream", type: ref.type, id: videoId)
        guard !addons.isEmpty else {
            messageLabel.text = "None of your addons provide streams for this.\n\nInstall a stream addon from the Addons tab."
            messageLabel.isHidden = false
            return
        }
        groups = addons.map { Group(addon: $0, state: .loading) }
        tableView.reloadData()

        for (i, addon) in addons.enumerated() {
            StremioAPI.shared.streams(addon: addon, type: ref.type, id: videoId) { [weak self] result in
                guard let self = self, self.groups.indices.contains(i) else { return }
                switch result {
                case .success(let streams): self.groups[i].state = .loaded(streams)
                case .failure: self.groups[i].state = .failed
                }
                self.tableView.reloadSections(IndexSet(integer: i), with: .fade)
            }
        }
    }

    // MARK: Table

    func numberOfSections(in tableView: UITableView) -> Int { groups.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if case .loaded(let streams) = groups[section].state { return max(1, streams.count) }
        return 1
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        groups[section].addon.manifest.name
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        (view as? UITableViewHeaderFooterView)?.textLabel?.textColor = Theme.secondaryText
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "stream")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "stream")
        cell.backgroundColor = Theme.surface
        let selected = UIView()
        selected.backgroundColor = Theme.surfaceHigh
        cell.selectedBackgroundView = selected
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        cell.textLabel?.textColor = Theme.text
        cell.detailTextLabel?.numberOfLines = 0
        cell.detailTextLabel?.font = .systemFont(ofSize: 13)
        cell.detailTextLabel?.textColor = Theme.secondaryText
        cell.accessoryView = nil
        cell.selectionStyle = .default
        cell.contentView.alpha = 1

        switch groups[indexPath.section].state {
        case .loading:
            cell.textLabel?.text = "Loading…"
            cell.detailTextLabel?.text = nil
            let spinner = UIActivityIndicatorView(style: .white)
            spinner.startAnimating()
            cell.accessoryView = spinner
            cell.selectionStyle = .none
        case .failed:
            cell.textLabel?.text = "Couldn't load streams"
            cell.detailTextLabel?.text = "The addon didn't respond."
            cell.selectionStyle = .none
        case .loaded(let streams):
            guard !streams.isEmpty else {
                cell.textLabel?.text = "No streams found"
                cell.detailTextLabel?.text = nil
                cell.selectionStyle = .none
                return cell
            }
            let s = streams[indexPath.row]
            cell.textLabel?.text = s.displayName
            var detail = s.title ?? ""
            switch s.kind {
            case .torrent:
                detail += (detail.isEmpty ? "" : "\n") + "Torrent — not playable in Lumen"
                cell.contentView.alpha = 0.5
            case .youtube:
                detail += (detail.isEmpty ? "" : "\n") + "Opens in YouTube"
            case .external:
                detail += (detail.isEmpty ? "" : "\n") + "Opens externally"
            default:
                break
            }
            cell.detailTextLabel?.text = detail.isEmpty ? nil : detail
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard case .loaded(let streams) = groups[indexPath.section].state,
              streams.indices.contains(indexPath.row) else { return }
        StreamActions.handle(streams[indexPath.row], ref: ref, videoId: videoId, label: label,
                             from: self, source: tableView.cellForRow(at: indexPath))
    }
}

// MARK: - Stream actions & external players

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
            if !ok { vc?.showAlert("\(name) isn't installed", "Install \(name) from the App Store, or pick another player.") }
        }
    }
}

enum StreamActions {
    static func handle(_ stream: StreamItem, ref: MediaRef, videoId: String, label: String?,
                       from vc: UIViewController, source: UIView?) {
        switch stream.kind {
        case .direct(let url):
            let sheet = UIAlertController(title: stream.displayName, message: nil, preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: "Play", style: .default) { _ in
                let player = PlayerViewController(ref: ref, videoId: videoId, label: label,
                                                  url: url, headers: stream.headers)
                vc.present(player, animated: true)
            })
            for p in ExternalPlayer.allCases {
                sheet.addAction(UIAlertAction(title: "Open in \(p.name)", style: .default) { _ in
                    p.open(url, from: vc)
                })
            }
            sheet.addAction(UIAlertAction(title: "Copy Link", style: .default) { _ in
                UIPasteboard.general.string = url.absoluteString
            })
            sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            vc.presentSheet(sheet, from: source)

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
}
