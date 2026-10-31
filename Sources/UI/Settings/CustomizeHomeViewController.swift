import UIKit

/// Reorder and show/hide Home rows (saved per profile).
final class CustomizeHomeViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private struct Item {
        let key: String
        let title: String
        var visible: Bool
    }

    private var items: [Item] = []
    private let tableView = UITableView(frame: .zero, style: .grouped)

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Customize Home"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = Theme.background
        if presentingViewController != nil && navigationController?.viewControllers.first === self {
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped))
        }
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Reset", style: .plain, target: self, action: #selector(resetTapped))

        tableView.backgroundColor = Theme.background
        tableView.separatorColor = UIColor(white: 1, alpha: 0.08)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.isEditing = true
        tableView.allowsSelectionDuringEditing = true
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        load()
    }

    private func load() {
        let hidden = HomeLayout.shared.hidden
        let entries = HomeLayout.shared.ordered(HomeRows.all()) { $0.key }
        items = entries.map { Item(key: $0.key, title: $0.title, visible: !hidden.contains($0.key)) }
        tableView.reloadData()
    }

    private func save() {
        HomeLayout.shared.save(order: items.map { $0.key },
                               hidden: Set(items.filter { !$0.visible }.map { $0.key }))
    }

    @objc private func doneTapped() { dismiss(animated: true) }

    @objc private func resetTapped() {
        HomeLayout.shared.reset()
        load()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Drag to reorder. Switch off rows you don't want on Home. Each profile has its own layout."
    }

    func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        (view as? UITableViewHeaderFooterView)?.textLabel?.textColor = Theme.secondaryText
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = Theme.surface
        cell.textLabel?.textColor = Theme.text
        cell.textLabel?.numberOfLines = 2
        cell.selectionStyle = .none
        let item = items[indexPath.row]
        cell.textLabel?.text = item.title
        cell.textLabel?.alpha = item.visible ? 1 : 0.45
        let toggle = ClosureSwitch()
        toggle.isOn = item.visible
        toggle.onTintColor = Theme.accent
        let key = item.key
        toggle.onChange = { [weak self] on in
            guard let self = self, let i = self.items.firstIndex(where: { $0.key == key }) else { return }
            self.items[i].visible = on
            self.save()
            self.tableView.reloadRows(at: [IndexPath(row: i, section: 0)], with: .none)
        }
        cell.editingAccessoryView = toggle
        return cell
    }

    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle { .none }

    func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool { false }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { true }

    func tableView(_ tableView: UITableView, moveRowAt source: IndexPath, to destination: IndexPath) {
        let item = items.remove(at: source.row)
        items.insert(item, at: destination.row)
        save()
    }
}
