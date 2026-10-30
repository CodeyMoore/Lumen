import UIKit

final class SearchViewController: RowsViewController, UISearchBarDelegate {
    private let searchController = UISearchController(searchResultsController: nil)
    private var generation = 0
    private var debounce: Timer?
    private var lastQuery = ""
    private let idleMessage = "Search movies and series\nacross your addons."

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Search"

        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.delegate = self
        searchController.searchBar.placeholder = "Movies, series…"
        searchController.searchBar.barStyle = .black
        searchController.searchBar.keyboardAppearance = .dark
        searchController.searchBar.tintColor = Theme.accent
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

        tableView.keyboardDismissMode = .onDrag
        showMessage(idleMessage)
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        debounce?.invalidate()
        debounce = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            self?.run(searchText)
        }
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        debounce?.invalidate()
        run(searchBar.text ?? "")
        searchBar.resignFirstResponder()
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        debounce?.invalidate()
        run("")
    }

    private func run(_ raw: String) {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query != lastQuery else { return }
        lastQuery = query
        generation += 1
        let gen = generation

        guard query.count >= 2 else {
            rows = []
            tableView.reloadData()
            showMessage(idleMessage)
            return
        }

        var newRows: [Row] = []
        for addon in AddonStore.shared.addons where addon.manifest.hasResource("catalog") {
            for cat in addon.manifest.catalogs where cat.supportsSearch {
                let key = "\(addon.manifest.id)|\(cat.type)"
                guard !newRows.contains(where: { $0.key == key }) else { continue }
                newRows.append(Row(key: key, title: "\(TypeNames.plural(cat.type)) · \(addon.manifest.name)",
                                   items: [], state: .loading, addon: addon, catalog: cat))
            }
        }

        rows = newRows
        tableView.reloadData()
        showMessage(newRows.isEmpty ? "None of your addons support search." : nil)

        for row in newRows {
            guard let addon = row.addon, let cat = row.catalog else { continue }
            StremioAPI.shared.catalog(addon: addon, catalog: cat, extra: [("search", query)]) { [weak self] result in
                guard let self = self, gen == self.generation,
                      let i = self.rows.firstIndex(where: { $0.key == row.key }) else { return }
                switch result {
                case .success(let metas):
                    self.rows[i].items = metas.map { PosterItem(ref: $0.ref) }
                    self.rows[i].state = metas.isEmpty ? .empty("No results") : .loaded
                case .failure:
                    self.rows[i].state = .failed("Search failed")
                }
                self.refreshRow(key: row.key)
            }
        }
    }
}
