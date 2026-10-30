import UIKit

/// Small declarative grouped table used by Settings and Accounts.
class SettingsTableController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    enum Row {
        case toggle(String, Bool, (Bool) -> Void)
        case value(String, String?, (UIView) -> Void)
        case action(String, destructive: Bool, (UIView) -> Void)
        case info(String, String?)
    }

    struct Section {
        var title: String?
        var footer: String?
        var rows: [Row]
    }

    var sections: [Section] = []
    let tableView = UITableView(frame: .zero, style: .grouped)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        tableView.backgroundColor = Theme.background
        tableView.separatorColor = UIColor(white: 1, alpha: 0.08)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.estimatedRowHeight = 50
        tableView.rowHeight = UITableView.automaticDimension
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        rebuild()
    }

    /// Subclasses fill `sections`.
    func buildSections() -> [Section] { [] }

    func rebuild() {
        sections = buildSections()
        tableView.reloadData()
    }

    func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].rows.count }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section].title }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { sections[section].footer }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        (view as? UITableViewHeaderFooterView)?.textLabel?.textColor = Theme.secondaryText
    }

    func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        (view as? UITableViewHeaderFooterView)?.textLabel?.textColor = Theme.secondaryText
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.backgroundColor = Theme.surface
        let selected = UIView()
        selected.backgroundColor = Theme.surfaceHigh
        cell.selectedBackgroundView = selected
        cell.textLabel?.textColor = Theme.text
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.textColor = Theme.secondaryText
        cell.detailTextLabel?.numberOfLines = 2

        switch sections[indexPath.section].rows[indexPath.row] {
        case .toggle(let title, let on, let change):
            cell.textLabel?.text = title
            cell.selectionStyle = .none
            let toggle = ClosureSwitch()
            toggle.isOn = on
            toggle.onTintColor = Theme.accent
            toggle.onChange = change
            cell.accessoryView = toggle
        case .value(let title, let value, _):
            cell.textLabel?.text = title
            cell.detailTextLabel?.text = value
            cell.accessoryType = .disclosureIndicator
        case .action(let title, let destructive, _):
            cell.textLabel?.text = title
            cell.textLabel?.textColor = destructive ? UIColor(red: 1, green: 0.38, blue: 0.38, alpha: 1) : Theme.accent
        case .info(let title, let value):
            cell.textLabel?.text = title
            cell.detailTextLabel?.text = value
            cell.selectionStyle = .none
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let source = tableView.cellForRow(at: indexPath) ?? view
        switch sections[indexPath.section].rows[indexPath.row] {
        case .value(_, _, let action), .action(_, _, let action):
            action(source)
        default:
            break
        }
    }

    /// Action-sheet picker helper.
    func choose<T>(_ title: String, _ options: [(T, String)], current: (T) -> Bool, from source: UIView,
                   _ pick: @escaping (T) -> Void) {
        let sheet = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        for (value, label) in options {
            sheet.addAction(UIAlertAction(title: (current(value) ? "✓ " : "") + label, style: .default) { [weak self] _ in
                pick(value)
                self?.rebuild()
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentSheet(sheet, from: source)
    }
}

final class ClosureSwitch: UISwitch {
    var onChange: ((Bool) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addTarget(self, action: #selector(changed), for: .valueChanged)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func changed() { onChange?(isOn) }
}
