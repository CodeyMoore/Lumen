import UIKit

final class HomeViewController: RowsViewController {
    private var generation = 0
    private let refresh = UIRefreshControl()

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Lumen"

        refresh.tintColor = .white
        refresh.addTarget(self, action: #selector(pulledToRefresh), for: .valueChanged)
        tableView.refreshControl = refresh

        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .addonsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(libraryChanged), name: .libraryChanged, object: nil)

        reload()
        AddonStore.shared.seedDefaultsIfNeeded {}
    }

    @objc private func pulledToRefresh() {
        AccountSync.pullProgress()
        reload()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.refresh.endRefreshing() }
    }

    private func continueRow() -> Row? {
        let states = LibraryStore.shared.continueWatching()
        guard !states.isEmpty else { return nil }
        let items = states.map { PosterItem(ref: $0.ref, subtitle: $0.videoLabel, progress: $0.progress) }
        return Row(key: "continue", title: "Continue Watching", items: items, state: .loaded, addon: nil, catalog: nil)
    }

    @objc private func reload() {
        generation += 1
        let gen = generation

        var catalogRows: [Row] = []
        for addon in AddonStore.shared.addons where addon.manifest.hasResource("catalog") {
            for cat in addon.manifest.catalogs where !cat.requiresExtra {
                catalogRows.append(Row(key: "\(addon.manifest.id)|\(cat.type)|\(cat.id)",
                                       title: cat.displayTitle, items: [], state: .loading,
                                       addon: addon, catalog: cat))
            }
        }

        rows = (continueRow().map { [$0] } ?? []) + catalogRows
        tableView.reloadData()
        updateMessage()

        for row in catalogRows {
            guard let addon = row.addon, let cat = row.catalog else { continue }
            StremioAPI.shared.catalog(addon: addon, catalog: cat) { [weak self] result in
                guard let self = self, gen == self.generation,
                      let i = self.rows.firstIndex(where: { $0.key == row.key }) else { return }
                switch result {
                case .success(let metas):
                    self.rows[i].items = metas.map { PosterItem(ref: $0.ref) }
                    self.rows[i].state = metas.isEmpty ? .empty("Nothing here right now") : .loaded
                case .failure:
                    self.rows[i].state = .failed("Couldn't load this catalog")
                }
                self.refreshRow(key: row.key)
            }
        }
    }

    private func updateMessage() {
        if !rows.isEmpty {
            showMessage(nil)
        } else if AddonStore.shared.addons.isEmpty {
            showMessage("No addons installed yet.\nAdd one in Settings → Addons.")
        } else {
            showMessage("Your addons don't provide any catalogs.")
        }
    }

    @objc private func libraryChanged() {
        let row = continueRow()
        let hasRow = rows.first?.key == "continue"
        if hasRow, let row = row {
            rows[0] = row
            refreshRow(key: "continue")
        } else if hasRow {
            rows.removeFirst()
            tableView.reloadData()
        } else if let row = row {
            rows.insert(row, at: 0)
            tableView.reloadData()
        }
        updateMessage()
    }

    override func didLongPress(_ item: PosterItem, rowKey: String, source: UIView) {
        guard rowKey == "continue" else { return }
        let sheet = UIAlertController(title: item.ref.name, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Remove from Continue Watching", style: .destructive) { _ in
            LibraryStore.shared.removeFromContinue(item.ref.id)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentSheet(sheet, from: source)
    }
}
