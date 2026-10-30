import UIKit

final class DownloadsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()

    private var records: [DownloadRecord] { DownloadManager.shared.records }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Downloads"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = Theme.background

        tableView.backgroundColor = Theme.background
        tableView.separatorColor = UIColor(white: 1, alpha: 0.08)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 64
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        emptyLabel.text = "No downloads yet.\n\nOn a stream, tap ⓘ then Download."
        emptyLabel.textColor = Theme.secondaryText
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .downloadsChanged, object: nil)
        reload()
    }

    @objc private func reload() {
        tableView.reloadData()
        emptyLabel.isHidden = !records.isEmpty
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { records.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "dl")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "dl")
        cell.backgroundColor = Theme.background
        let selected = UIView()
        selected.backgroundColor = Theme.surface
        cell.selectedBackgroundView = selected
        cell.textLabel?.textColor = Theme.text
        cell.textLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        cell.detailTextLabel?.textColor = Theme.secondaryText

        let r = records[indexPath.row]
        cell.textLabel?.text = r.title
        switch r.state {
        case .downloading:
            let size = r.totalBytes > 0 ? " of " + ByteCountFormatter.string(fromByteCount: r.totalBytes, countStyle: .file) : ""
            cell.detailTextLabel?.text = "Downloading \(Int(r.progress * 100))%\(size)"
        case .done:
            let size = r.totalBytes > 0 ? ByteCountFormatter.string(fromByteCount: r.totalBytes, countStyle: .file) : "Ready"
            cell.detailTextLabel?.text = "\(size) · Tap to play"
        case .failed:
            cell.detailTextLabel?.text = "Failed\(r.errorMessage.map { ": \($0)" } ?? "") · Tap to retry"
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let r = records[indexPath.row]
        switch r.state {
        case .done:
            guard let file = r.localURL, FileManager.default.fileExists(atPath: file.path) else {
                showAlert("File missing", "This download's file was removed.")
                return
            }
            let ctx = PlaybackContext(ref: r.ref, videoId: r.videoId, label: r.label, meta: nil, addonId: nil, bingeGroup: nil)
            let engine: PlayerViewController.EngineKind = AppSettings.shared.player == .system ? .avPlayer : .vlc
            present(PlayerViewController(context: ctx, url: file, headers: [:], engine: engine), animated: true)
        case .failed:
            DownloadManager.shared.retry(r.id)
        case .downloading:
            break
        }
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool { true }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        DownloadManager.shared.delete(records[indexPath.row].id)
    }
}
