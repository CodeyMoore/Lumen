import UIKit

final class AddonsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .grouped)
    private let spinner = UIActivityIndicatorView(style: .white)
    private var isMutating = false

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Addons"
        view.backgroundColor = Theme.background

        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addTapped)),
            editButtonItem,
        ]

        tableView.backgroundColor = Theme.background
        tableView.separatorColor = UIColor(white: 1, alpha: 0.08)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.estimatedRowHeight = 80
        tableView.rowHeight = UITableView.automaticDimension
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(addonsChanged), name: .addonsChanged, object: nil)
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        tableView.setEditing(editing, animated: animated)
    }

    @objc private func addonsChanged() {
        guard !isMutating else { return }
        tableView.reloadData()
    }

    // MARK: Install

    @objc private func addTapped() { promptInstall(prefill: nil) }

    func promptInstall(prefill: String?) {
        let alert = UIAlertController(title: "Install Addon",
                                      message: "Paste the addon's manifest URL.",
                                      preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "https://…/manifest.json"
            tf.keyboardType = .URL
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
            tf.clearButtonMode = .whileEditing
            tf.text = prefill
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Install", style: .default) { [weak self, weak alert] _ in
            self?.install(alert?.textFields?.first?.text ?? "")
        })
        (tabBarController ?? self).topPresenter.present(alert, animated: true)
    }

    private func install(_ text: String) {
        guard let normalized = StremioAPI.normalizeManifestURL(text) else {
            showAlert("Invalid URL", "That doesn't look like an addon manifest URL.")
            return
        }
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: spinner)
        spinner.startAnimating()
        StremioAPI.shared.fetchAddon(normalized) { [weak self] result in
            guard let self = self else { return }
            self.spinner.stopAnimating()
            self.navigationItem.leftBarButtonItem = nil
            switch result {
            case .success(let addon):
                AddonStore.shared.add(addon)
                self.showAlert("Installed", "\(addon.manifest.name) is ready.")
            case .failure(let error):
                self.showAlert("Couldn't install addon", error.localizedDescription)
            }
        }
    }

    // MARK: Table

    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? AddonStore.shared.addons.count : 1
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Installed" : nil
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == 0 else { return nil }
        return "Order matters: details load from the first addon that has them. Lumen plays direct HTTP(S) streams; torrent-only streams aren't supported. Swipe to remove, or tap Edit to reorder."
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "addon")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "addon")
        cell.backgroundColor = Theme.surface
        let selected = UIView()
        selected.backgroundColor = Theme.surfaceHigh
        cell.selectedBackgroundView = selected
        cell.textLabel?.textColor = Theme.text
        cell.detailTextLabel?.textColor = Theme.secondaryText
        cell.detailTextLabel?.numberOfLines = 3

        if indexPath.section == 0 {
            let m = AddonStore.shared.addons[indexPath.row].manifest
            cell.textLabel?.text = m.version.isEmpty ? m.name : "\(m.name)  v\(m.version)"
            cell.textLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
            cell.textLabel?.textAlignment = .natural
            var detail = m.capabilitySummary
            if let d = m.description { detail = d + "\n" + detail }
            cell.detailTextLabel?.text = detail
        } else {
            cell.textLabel?.text = "Restore Default Addons"
            cell.textLabel?.textColor = Theme.accent
            cell.textLabel?.font = .systemFont(ofSize: 16)
            cell.detailTextLabel?.text = "Cinemeta (catalogs & details) and OpenSubtitles"
        }
        return cell
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        (view as? UITableViewHeaderFooterView)?.textLabel?.textColor = Theme.secondaryText
    }

    func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        (view as? UITableViewHeaderFooterView)?.textLabel?.textColor = Theme.secondaryText
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let cell = tableView.cellForRow(at: indexPath)

        if indexPath.section == 1 {
            AddonStore.shared.installDefaults { [weak self] ok in
                if !ok { self?.showAlert("Couldn't reach the default addons", "Check your connection and try again.") }
            }
            return
        }

        let addon = AddonStore.shared.addons[indexPath.row]
        let sheet = UIAlertController(title: addon.manifest.name, message: addon.transportUrl, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Copy Manifest URL", style: .default) { _ in
            UIPasteboard.general.string = addon.transportUrl
        })
        sheet.addAction(UIAlertAction(title: "Update", style: .default) { [weak self] _ in
            self?.install(addon.transportUrl)
        })
        sheet.addAction(UIAlertAction(title: "Remove", style: .destructive) { _ in
            if let i = AddonStore.shared.addons.firstIndex(where: { $0.manifest.id == addon.manifest.id }) {
                AddonStore.shared.remove(at: i)
            }
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentSheet(sheet, from: cell)
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool { indexPath.section == 0 }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        isMutating = true
        AddonStore.shared.remove(at: indexPath.row)
        tableView.deleteRows(at: [indexPath], with: .automatic)
        isMutating = false
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { indexPath.section == 0 }

    func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt source: IndexPath,
                   toProposedIndexPath proposed: IndexPath) -> IndexPath {
        if proposed.section == 0 { return proposed }
        return IndexPath(row: max(0, AddonStore.shared.addons.count - 1), section: 0)
    }

    func tableView(_ tableView: UITableView, moveRowAt source: IndexPath, to destination: IndexPath) {
        isMutating = true
        AddonStore.shared.move(from: source.row, to: destination.row)
        isMutating = false
    }
}
