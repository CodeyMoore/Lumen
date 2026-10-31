import UIKit

enum ProfileAvatar {
    static let colors: [UIColor] = [
        UIColor(red: 0.49, green: 0.40, blue: 1.00, alpha: 1),
        UIColor(red: 0.98, green: 0.45, blue: 0.40, alpha: 1),
        UIColor(red: 0.26, green: 0.72, blue: 0.55, alpha: 1),
        UIColor(red: 0.98, green: 0.70, blue: 0.25, alpha: 1),
        UIColor(red: 0.25, green: 0.62, blue: 0.95, alpha: 1),
        UIColor(red: 0.90, green: 0.40, blue: 0.75, alpha: 1),
        UIColor(red: 0.55, green: 0.60, blue: 0.68, alpha: 1),
    ]

    static let colorNames = ["Violet", "Coral", "Green", "Amber", "Blue", "Pink", "Slate"]

    static func color(_ index: Int) -> UIColor { colors[abs(index) % colors.count] }

    static func image(for profile: UserProfile, size: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let img = renderer.image { _ in
            color(profile.colorIndex).setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: size, height: size)).fill()
            let text = profile.initial as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size * 0.46, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
            let ts = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: (size - ts.width) / 2, y: (size - ts.height) / 2), withAttributes: attrs)
        }
        return img.withRenderingMode(.alwaysOriginal)
    }
}

/// "Who's watching?" screen, shown on launch and from the Home profile button.
final class ProfilePickerViewController: UIViewController {
    private let dismissible: Bool
    private let stack = UIStackView()
    private let scroll = UIScrollView()

    init(dismissible: Bool) {
        self.dismissible = dismissible
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        let title = UILabel()
        title.text = "Who's watching?"
        title.font = .systemFont(ofSize: 28, weight: .bold)
        title.textColor = Theme.text
        title.textAlignment = .center

        stack.axis = .horizontal
        stack.spacing = 22
        stack.alignment = .top
        stack.distribution = .equalSpacing

        scroll.showsHorizontalScrollIndicator = false
        scroll.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let manage = UIButton(type: .system)
        manage.setTitle("Manage Profiles", for: .normal)
        manage.tintColor = Theme.secondaryText
        manage.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        manage.addTarget(self, action: #selector(manageTapped), for: .touchUpInside)

        for v in [title, scroll, manage] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }

        if dismissible {
            let close = UIButton(type: .custom)
            close.setImage(Icons.close, for: .normal)
            close.tintColor = Theme.secondaryText
            close.contentEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
            close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
            close.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(close)
            NSLayoutConstraint.activate([
                close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
                close.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            ])
        }

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            title.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            title.bottomAnchor.constraint(equalTo: scroll.topAnchor, constant: -36),

            scroll.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 140),

            stack.topAnchor.constraint(equalTo: scroll.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -24),
            stack.heightAnchor.constraint(equalTo: scroll.heightAnchor),

            manage.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 28),
            manage.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(rebuild), name: .profileChanged, object: nil)
        rebuild()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Center the profiles when they fit on screen.
        let inset = max(0, (scroll.bounds.width - scroll.contentSize.width) / 2)
        if abs(scroll.contentInset.left - inset) > 0.5 {
            scroll.contentInset = UIEdgeInsets(top: 0, left: inset, bottom: 0, right: 0)
        }
    }

    @objc private func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, p) in ProfileStore.shared.profiles.enumerated() {
            let button = UIButton(type: .custom)
            button.tag = i
            button.setImage(ProfileAvatar.image(for: p, size: 88), for: .normal)
            button.addTarget(self, action: #selector(profileTapped(_:)), for: .touchUpInside)
            if p.id == ProfileStore.shared.currentId {
                button.layer.cornerRadius = 48
                button.layer.borderWidth = 3
                button.layer.borderColor = UIColor.white.cgColor
                button.contentEdgeInsets = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
            }
            let name = UILabel()
            name.text = p.name
            name.textColor = Theme.text
            name.font = .systemFont(ofSize: 15, weight: .medium)
            name.textAlignment = .center
            let column = UIStackView(arrangedSubviews: [button, name])
            column.axis = .vertical
            column.spacing = 10
            column.alignment = .center
            button.widthAnchor.constraint(equalToConstant: 96).isActive = true
            button.heightAnchor.constraint(equalToConstant: 96).isActive = true
            stack.addArrangedSubview(column)
        }
        view.setNeedsLayout()
    }

    @objc private func profileTapped(_ sender: UIButton) {
        let profiles = ProfileStore.shared.profiles
        guard profiles.indices.contains(sender.tag) else { return }
        let id = profiles[sender.tag].id
        if id != ProfileStore.shared.currentId { ProfileStore.shared.switchTo(id) }
        dismiss(animated: true)
    }

    @objc private func closeTapped() { dismiss(animated: true) }

    @objc private func manageTapped() {
        let nav = UINavigationController(rootViewController: ProfilesViewController())
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }
}

/// Settings → Profiles.
final class ProfilesViewController: SettingsTableController {
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Profiles"
        navigationItem.largeTitleDisplayMode = .never
        if navigationController?.viewControllers.first === self {
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped))
        }
        NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .profileChanged, object: nil)
    }

    @objc private func changed() { rebuild() }
    @objc private func doneTapped() { dismiss(animated: true) }

    override func buildSections() -> [Section] {
        let store = ProfileStore.shared
        var rows: [Row] = store.profiles.map { p in
            let current = p.id == store.currentId
            var detail = current ? "Current" : ""
            if p.syncAccounts { detail += detail.isEmpty ? "Syncs accounts" : " · Syncs accounts" }
            return .value(p.name, detail) { [weak self] src in self?.profileActions(p, from: src) }
        }
        rows.append(.action("Add Profile", destructive: false) { [weak self] _ in self?.addProfile() })
        return [
            Section(title: nil,
                    footer: "Each profile has its own library, Continue Watching, watched marks and Home layout. Addons and settings are shared. Only profiles with account sync on send activity to Stremio, Trakt or Nuvio.",
                    rows: rows),
            Section(title: nil, footer: nil, rows: [
                .toggle("Choose profile when Lumen opens", store.askOnLaunch) { store.askOnLaunch = $0 },
            ]),
        ]
    }

    private func profileActions(_ p: UserProfile, from source: UIView) {
        let store = ProfileStore.shared
        let sheet = UIAlertController(title: p.name, message: nil, preferredStyle: .actionSheet)
        if p.id != store.currentId {
            sheet.addAction(UIAlertAction(title: "Switch to \(p.name)", style: .default) { _ in store.switchTo(p.id) })
        }
        sheet.addAction(UIAlertAction(title: "Rename", style: .default) { [weak self] _ in self?.rename(p) })
        sheet.addAction(UIAlertAction(title: "Change Colour", style: .default) { [weak self] _ in
            self?.pickColor(current: p.colorIndex, from: source) { idx in
                var updated = p
                updated.colorIndex = idx
                store.update(updated)
            }
        })
        sheet.addAction(UIAlertAction(title: p.syncAccounts ? "Turn Off Account Sync" : "Turn On Account Sync",
                                      style: .default) { _ in
            var updated = p
            updated.syncAccounts.toggle()
            store.update(updated)
        })
        if store.profiles.count > 1 {
            sheet.addAction(UIAlertAction(title: "Delete Profile", style: .destructive) { [weak self] _ in
                let confirm = UIAlertController(title: "Delete \(p.name)?",
                                                message: "Its library, progress and watched marks will be removed.",
                                                preferredStyle: .alert)
                confirm.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                confirm.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in store.delete(p.id) })
                self?.present(confirm, animated: true)
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentSheet(sheet, from: source)
    }

    private func namePrompt(title: String, current: String?, _ done: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "Name"
            tf.text = current
            tf.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak alert] _ in
            let name = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { done(String(name.prefix(24))) }
        })
        present(alert, animated: true)
    }

    private func rename(_ p: UserProfile) {
        namePrompt(title: "Rename Profile", current: p.name) { name in
            var updated = p
            updated.name = name
            ProfileStore.shared.update(updated)
        }
    }

    private func addProfile() {
        namePrompt(title: "New Profile", current: nil) { name in
            let color = ProfileStore.shared.profiles.count % ProfileAvatar.colors.count
            ProfileStore.shared.add(name: name, colorIndex: color)
        }
    }

    private func pickColor(current: Int, from source: UIView, _ done: @escaping (Int) -> Void) {
        let sheet = UIAlertController(title: "Colour", message: nil, preferredStyle: .actionSheet)
        for (i, name) in ProfileAvatar.colorNames.enumerated() {
            sheet.addAction(UIAlertAction(title: (i == current ? "✓ " : "") + name, style: .default) { _ in done(i) })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentSheet(sheet, from: source)
    }
}

extension NSLayoutConstraint {
    func withPriority(_ p: UILayoutPriority) -> NSLayoutConstraint {
        priority = p
        return self
    }
}
