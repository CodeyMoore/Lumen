import UIKit

/// Every row Home can show, used by Home itself and the "Customize Home" screen.
enum HomeRows {
    static let continueKey = "continue"

    struct Entry {
        let key: String
        let title: String
        let addon: Addon?
        let catalog: CatalogDescriptor?
    }

    static func all() -> [Entry] {
        var out = [Entry(key: continueKey, title: "Continue Watching", addon: nil, catalog: nil)]
        for addon in AddonStore.shared.addons where addon.manifest.hasResource("catalog") {
            for cat in addon.manifest.catalogs where !cat.requiresExtra {
                out.append(Entry(key: "\(addon.manifest.id)|\(cat.type)|\(cat.id)",
                                 title: cat.displayTitle, addon: addon, catalog: cat))
            }
        }
        return out
    }
}

final class HomeViewController: RowsViewController {
    private var generation = 0
    private let refresh = UIRefreshControl()
    /// Catalog rows as loaded, independent of layout (so layout changes don't refetch).
    private var catalogRows: [String: Row] = [:]
    private var catalogOrder: [String] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Lumen"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Edit", style: .plain,
                                                            target: self, action: #selector(customizeTapped))

        refresh.tintColor = .white
        refresh.addTarget(self, action: #selector(pulledToRefresh), for: .valueChanged)
        tableView.refreshControl = refresh

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(reload), name: .addonsChanged, object: nil)
        nc.addObserver(self, selector: #selector(libraryChanged), name: .libraryChanged, object: nil)
        nc.addObserver(self, selector: #selector(layoutChanged), name: .homeLayoutChanged, object: nil)
        nc.addObserver(self, selector: #selector(profileChanged), name: .profileChanged, object: nil)

        updateProfileButton()
        reload()
        AddonStore.shared.seedDefaultsIfNeeded {}
    }

    // MARK: Profile button

    @objc private func profileChanged() {
        updateProfileButton()
        rebuildRows()
    }

    private func updateProfileButton() {
        guard ProfileStore.shared.profiles.count > 1 else {
            navigationItem.leftBarButtonItem = nil
            return
        }
        let button = UIButton(type: .custom)
        let p = ProfileStore.shared.current
        button.setImage(ProfileAvatar.image(for: p, size: 30), for: .normal)
        button.addTarget(self, action: #selector(profileTapped), for: .touchUpInside)
        button.frame = CGRect(x: 0, y: 0, width: 34, height: 34)
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: button)
    }

    @objc private func profileTapped() {
        present(ProfilePickerViewController(dismissible: true), animated: true)
    }

    @objc private func customizeTapped() {
        let nav = UINavigationController(rootViewController: CustomizeHomeViewController())
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    // MARK: Loading

    @objc private func pulledToRefresh() {
        AccountSync.pullProgress()
        reload()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.refresh.endRefreshing() }
    }

    private func continueRow() -> Row? {
        let states = LibraryStore.shared.continueWatching()
        guard !states.isEmpty else { return nil }
        let items = states.map {
            PosterItem(ref: $0.ref, subtitle: $0.shortLabel, progress: $0.isUpNext ? nil : $0.progress)
        }
        return Row(key: HomeRows.continueKey, title: "Continue Watching", items: items, state: .loaded,
                   addon: nil, catalog: nil)
    }

    @objc private func reload() {
        generation += 1
        let gen = generation
        catalogRows = [:]
        catalogOrder = []
        for e in HomeRows.all() {
            guard let addon = e.addon, let cat = e.catalog else { continue }
            catalogRows[e.key] = Row(key: e.key, title: e.title, items: [], state: .loading, addon: addon, catalog: cat)
            catalogOrder.append(e.key)
        }
        _ = gen
        rows = []
        rebuildRows() // fetches every visible row; hidden rows load when shown again
    }

    private func fetch(row: Row, addon: Addon, catalog: CatalogDescriptor, generation gen: Int) {
        StremioAPI.shared.catalog(addon: addon, catalog: catalog) { [weak self] result in
            guard let self = self, gen == self.generation, var stored = self.catalogRows[row.key] else { return }
            switch result {
            case .success(let metas):
                stored.items = metas.map { PosterItem(ref: $0.ref) }
                stored.state = metas.isEmpty ? .empty("Nothing here right now") : .loaded
            case .failure:
                stored.state = .failed("Couldn't load this catalog")
            }
            self.catalogRows[row.key] = stored
            if let i = self.rows.firstIndex(where: { $0.key == row.key }) {
                self.rows[i] = stored
                self.refreshRow(key: row.key)
            }
        }
    }

    /// Applies the saved layout to the current rows without refetching.
    private func rebuildRows() {
        let hidden = HomeLayout.shared.hidden
        var candidates: [Row] = []
        if let c = continueRow() { candidates.append(c) }
        for key in catalogOrder { if let r = catalogRows[key] { candidates.append(r) } }
        let ordered = HomeLayout.shared.ordered(candidates) { $0.key }.filter { !hidden.contains($0.key) }

        // Rows that are newly visible and haven't loaded yet need fetching.
        for r in ordered where r.key != HomeRows.continueKey {
            if case .loading = r.state, let addon = r.addon, let cat = r.catalog,
               !rows.contains(where: { $0.key == r.key }) {
                fetch(row: r, addon: addon, catalog: cat, generation: generation)
            }
        }

        let sameKeys = ordered.map { $0.key } == rows.map { $0.key }
        rows = ordered
        if sameKeys {
            refreshRow(key: HomeRows.continueKey)
        } else {
            tableView.reloadData()
        }
        updateMessage()
    }

    @objc private func layoutChanged() { rebuildRows() }

    private func updateMessage() {
        if !rows.isEmpty {
            showMessage(nil)
        } else if AddonStore.shared.addons.isEmpty {
            showMessage("No addons installed yet.\nAdd one in Settings → Addons.")
        } else if !catalogOrder.isEmpty {
            showMessage("All rows are hidden.\nTap Edit to choose what Home shows.")
        } else {
            showMessage("Your addons don't provide any catalogs.")
        }
    }

    @objc private func libraryChanged() {
        rebuildRows()
    }

    override func didLongPress(_ item: PosterItem, rowKey: String, source: UIView) {
        guard rowKey == HomeRows.continueKey else { return }
        let sheet = UIAlertController(title: item.ref.name, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Remove from Continue Watching", style: .destructive) { _ in
            LibraryStore.shared.removeFromContinue(item.ref.id)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentSheet(sheet, from: source)
    }
}
