import UIKit

/// Base screen made of horizontally scrolling poster rows (Home and Search).
class RowsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    struct Row {
        let key: String
        var title: String
        var items: [PosterItem]
        var state: RowState
        var addon: Addon?
        var catalog: CatalogDescriptor?
    }

    var rows: [Row] = []
    let tableView = UITableView(frame: .zero, style: .plain)
    private let messageLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        tableView.backgroundColor = Theme.background
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(PosterRowCell.self, forCellReuseIdentifier: PosterRowCell.reuseId)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        let background = UIView()
        messageLabel.textColor = Theme.secondaryText
        messageLabel.font = .systemFont(ofSize: 16)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(messageLabel)
        tableView.backgroundView = background

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: background.centerYAnchor, constant: -40),
            messageLabel.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 32),
            messageLabel.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -32),
        ])
    }

    func showMessage(_ text: String?) {
        messageLabel.text = text
        messageLabel.isHidden = text == nil
    }

    /// Updates a row in place so its scroll position is kept.
    func refreshRow(key: String) {
        guard let i = rows.firstIndex(where: { $0.key == key }) else { return }
        if let cell = tableView.cellForRow(at: IndexPath(row: i, section: 0)) as? PosterRowCell {
            configure(cell, with: rows[i])
        }
    }

    private func configure(_ cell: PosterRowCell, with row: Row) {
        cell.configure(title: row.title, items: row.items, state: row.state)
        let key = row.key
        cell.onSelect = { [weak self] item in self?.didSelect(item) }
        cell.onLongPress = { [weak self] item, source in self?.didLongPress(item, rowKey: key, source: source) }
    }

    func didSelect(_ item: PosterItem) {
        navigationController?.pushViewController(DetailViewController(ref: item.ref), animated: true)
    }

    func didLongPress(_ item: PosterItem, rowKey: String, source: UIView) {}

    // MARK: Table

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: PosterRowCell.reuseId, for: indexPath) as! PosterRowCell
        configure(cell, with: rows[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        PosterRowCell.height(for: traitCollection)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.horizontalSizeClass != traitCollection.horizontalSizeClass {
            tableView.reloadData()
        }
    }
}
