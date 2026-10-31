import UIKit

/// Everything the current profile has finished watching, grouped by day.
final class HistoryViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private struct Day {
        let title: String
        var entries: [(index: Int, entry: HistoryEntry)]
    }

    private var days: [Day] = []
    private let tableView = UITableView(frame: .zero, style: .grouped)
    private let emptyLabel = UILabel()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        f.doesRelativeDateFormatting = true
        return f
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "History"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Clear", style: .plain, target: self, action: #selector(clearTapped))
        view.backgroundColor = Theme.background

        tableView.backgroundColor = Theme.background
        tableView.separatorColor = UIColor(white: 1, alpha: 0.08)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 76
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        emptyLabel.text = "Nothing here yet.\n\nTitles you finish watching on this profile show up here."
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

        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .libraryChanged, object: nil)
        reload()
    }

    @objc private func reload() {
        let cal = Calendar.current
        var out: [Day] = []
        for (i, e) in LibraryStore.shared.history.enumerated() {
            let title = HistoryViewController.dayFormatter.string(from: e.watchedAt)
            if let last = out.last, let first = last.entries.first,
               cal.isDate(first.entry.watchedAt, inSameDayAs: e.watchedAt) {
                out[out.count - 1].entries.append((i, e))
            } else {
                out.append(Day(title: title, entries: [(i, e)]))
            }
        }
        days = out
        tableView.reloadData()
        emptyLabel.isHidden = !days.isEmpty
        navigationItem.rightBarButtonItem?.isEnabled = !days.isEmpty
    }

    @objc private func clearTapped() {
        let alert = UIAlertController(title: "Clear History?",
                                      message: "This only clears the list. Watched marks and Continue Watching stay as they are.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { _ in LibraryStore.shared.clearHistory() })
        present(alert, animated: true)
    }

    func numberOfSections(in tableView: UITableView) -> Int { days.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { days[section].entries.count }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { days[section].title }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        (view as? UITableViewHeaderFooterView)?.textLabel?.textColor = Theme.secondaryText
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "history") as? HistoryCell ?? HistoryCell()
        let e = days[indexPath.section].entries[indexPath.row].entry
        var detail = [HistoryViewController.timeFormatter.string(from: e.watchedAt)]
        if let label = e.label { detail.insert(label, at: 0) }
        cell.configure(title: e.ref.name.isEmpty ? "Untitled" : e.ref.name,
                       detail: detail.joined(separator: "  ·  "), poster: e.ref.poster)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let e = days[indexPath.section].entries[indexPath.row].entry
        navigationController?.pushViewController(DetailViewController(ref: e.ref), animated: true)
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        LibraryStore.shared.removeHistory(at: days[indexPath.section].entries[indexPath.row].index)
    }

    func tableView(_ tableView: UITableView, titleForDeleteConfirmationButtonForRowAt indexPath: IndexPath) -> String? {
        "Remove"
    }
}

private final class HistoryCell: UITableViewCell {
    private let poster = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()

    init() {
        super.init(style: .default, reuseIdentifier: "history")
        backgroundColor = Theme.surface
        let selected = UIView()
        selected.backgroundColor = Theme.surfaceHigh
        selectedBackgroundView = selected

        poster.contentMode = .scaleAspectFill
        poster.clipsToBounds = true
        poster.layer.cornerRadius = 4
        poster.backgroundColor = Theme.surfaceHigh
        titleLabel.textColor = Theme.text
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        detailLabel.textColor = Theme.secondaryText
        detailLabel.font = .systemFont(ofSize: 13)

        let text = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        text.axis = .vertical
        text.spacing = 3
        for v in [poster, text] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(v)
        }
        NSLayoutConstraint.activate([
            poster.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            poster.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            poster.widthAnchor.constraint(equalToConstant: 40),
            poster.heightAnchor.constraint(equalToConstant: 60),
            text.leadingAnchor.constraint(equalTo: poster.trailingAnchor, constant: 12),
            text.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            text.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, detail: String, poster url: String?) {
        titleLabel.text = title
        detailLabel.text = detail
        poster.loadImage(url, maxPixel: 160)
    }
}
