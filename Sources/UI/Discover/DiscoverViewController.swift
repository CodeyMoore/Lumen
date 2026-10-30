import UIKit

/// Browse any addon catalog with its filters (genre, year…), with endless scrolling.
final class DiscoverViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private struct Source {
        let addon: Addon
        let catalog: CatalogDescriptor
    }

    private var sources: [Source] = []
    private var types: [String] = []
    private var selectedType = ""
    private var selectedSource: Source?
    private var selectedExtras: [String: String] = [:]

    private var items: [MetaItem] = []
    private var loading = false
    private var reachedEnd = false
    private var generation = 0

    private let filterScroll = UIScrollView()
    private let filterStack = UIStackView()
    private let layout = UICollectionViewFlowLayout()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private let messageLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .white)

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Discover"
        view.backgroundColor = Theme.background

        filterScroll.showsHorizontalScrollIndicator = false
        filterStack.spacing = 8
        filterStack.translatesAutoresizingMaskIntoConstraints = false
        filterScroll.addSubview(filterStack)

        layout.minimumLineSpacing = 18
        layout.minimumInteritemSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 12, left: 16, bottom: 30, right: 16)
        collectionView.backgroundColor = Theme.background
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(PosterCell.self, forCellWithReuseIdentifier: PosterCell.reuseId)

        messageLabel.textColor = Theme.secondaryText
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        spinner.hidesWhenStopped = true

        for v in [filterScroll, collectionView, messageLabel, spinner] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        NSLayoutConstraint.activate([
            filterScroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            filterScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filterScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filterScroll.heightAnchor.constraint(equalToConstant: 40),
            filterStack.topAnchor.constraint(equalTo: filterScroll.topAnchor, constant: 2),
            filterStack.bottomAnchor.constraint(equalTo: filterScroll.bottomAnchor),
            filterStack.leadingAnchor.constraint(equalTo: filterScroll.leadingAnchor, constant: 16),
            filterStack.trailingAnchor.constraint(equalTo: filterScroll.trailingAnchor, constant: -16),
            filterStack.heightAnchor.constraint(equalToConstant: 36),

            collectionView.topAnchor.constraint(equalTo: filterScroll.bottomAnchor, constant: 4),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            messageLabel.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor, constant: -40),
            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            spinner.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(reloadSources), name: .addonsChanged, object: nil)
        reloadSources()
    }

    // MARK: Sources & filters

    @objc private func reloadSources() {
        sources = []
        for addon in AddonStore.shared.addons where addon.manifest.hasResource("catalog") {
            for cat in addon.manifest.catalogs where cat.isBrowsable {
                sources.append(Source(addon: addon, catalog: cat))
            }
        }
        types = []
        for s in sources where !types.contains(s.catalog.type) { types.append(s.catalog.type) }
        if !types.contains(selectedType) { selectedType = types.first ?? "" }
        pickSource(sources.first { $0.catalog.type == selectedType })
    }

    private func pickSource(_ source: Source?) {
        selectedSource = source
        selectedExtras = [:]
        if let cat = source?.catalog {
            for e in cat.filterExtras where e.isRequired {
                selectedExtras[e.name] = e.options.first
            }
        }
        rebuildFilterBar()
        reload()
    }

    private func pill(_ title: String, action: Selector) -> UIButton {
        let b = UIButton(type: .custom)
        b.setTitle(title + "  ▾", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        b.setTitleColor(.white, for: .normal)
        b.setTitleColor(UIColor(white: 1, alpha: 0.5), for: .highlighted)
        b.backgroundColor = Theme.surfaceHigh
        b.layer.cornerRadius = 17
        b.contentEdgeInsets = UIEdgeInsets(top: 7, left: 14, bottom: 7, right: 14)
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    private func rebuildFilterBar() {
        filterStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let source = selectedSource else { return }
        if types.count > 1 {
            filterStack.addArrangedSubview(pill(TypeNames.plural(selectedType), action: #selector(typeTapped(_:))))
        }
        let catTitle = sources.filter { $0.catalog.type == selectedType }.count > 1
            ? "\(source.catalog.name) (\(source.addon.manifest.name))" : source.catalog.name
        filterStack.addArrangedSubview(pill(catTitle, action: #selector(catalogTapped(_:))))
        for (i, extra) in source.catalog.filterExtras.enumerated() {
            let b = pill(selectedExtras[extra.name] ?? "Any \(extra.name.capitalized)", action: #selector(extraTapped(_:)))
            b.tag = i
            filterStack.addArrangedSubview(b)
        }
    }

    @objc private func typeTapped(_ sender: UIButton) {
        let sheet = UIAlertController(title: "Type", message: nil, preferredStyle: .actionSheet)
        for t in types {
            sheet.addAction(UIAlertAction(title: (t == selectedType ? "✓ " : "") + TypeNames.plural(t), style: .default) { [weak self] _ in
                guard let self = self else { return }
                self.selectedType = t
                self.pickSource(self.sources.first { $0.catalog.type == t })
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentSheet(sheet, from: sender)
    }

    @objc private func catalogTapped(_ sender: UIButton) {
        let sheet = UIAlertController(title: "Catalog", message: nil, preferredStyle: .actionSheet)
        for s in sources where s.catalog.type == selectedType {
            let isCurrent = s.catalog.id == selectedSource?.catalog.id && s.addon.manifest.id == selectedSource?.addon.manifest.id
            sheet.addAction(UIAlertAction(title: (isCurrent ? "✓ " : "") + "\(s.catalog.name) · \(s.addon.manifest.name)",
                                          style: .default) { [weak self] _ in
                self?.pickSource(s)
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentSheet(sheet, from: sender)
    }

    @objc private func extraTapped(_ sender: UIButton) {
        guard let extras = selectedSource?.catalog.filterExtras, extras.indices.contains(sender.tag) else { return }
        let extra = extras[sender.tag]
        let sheet = UIAlertController(title: extra.name.capitalized, message: nil, preferredStyle: .actionSheet)
        if !extra.isRequired {
            sheet.addAction(UIAlertAction(title: (selectedExtras[extra.name] == nil ? "✓ " : "") + "Any", style: .default) { [weak self] _ in
                self?.selectedExtras[extra.name] = nil
                self?.rebuildFilterBar()
                self?.reload()
            })
        }
        for option in extra.options.prefix(60) {
            sheet.addAction(UIAlertAction(title: (selectedExtras[extra.name] == option ? "✓ " : "") + option, style: .default) { [weak self] _ in
                self?.selectedExtras[extra.name] = option
                self?.rebuildFilterBar()
                self?.reload()
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentSheet(sheet, from: sender)
    }

    // MARK: Loading

    private func reload() {
        generation += 1
        items = []
        reachedEnd = false
        loading = false
        collectionView.reloadData()
        collectionView.setContentOffset(.zero, animated: false)
        if selectedSource == nil {
            messageLabel.text = AddonStore.shared.addons.isEmpty
                ? "No addons installed yet.\nAdd one in Settings → Addons."
                : "Your addons don't have browsable catalogs."
            messageLabel.isHidden = false
            return
        }
        messageLabel.isHidden = true
        loadMore()
    }

    private func loadMore() {
        guard let source = selectedSource, !loading, !reachedEnd else { return }
        loading = true
        if items.isEmpty { spinner.startAnimating() }
        let gen = generation
        var extra: [(String, String)] = selectedExtras.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        if !items.isEmpty {
            guard source.catalog.supportsSkip else { reachedEnd = true; loading = false; return }
            extra.append(("skip", String(items.count)))
        }
        StremioAPI.shared.catalog(addon: source.addon, catalog: source.catalog, extra: extra) { [weak self] result in
            guard let self = self, gen == self.generation else { return }
            self.loading = false
            self.spinner.stopAnimating()
            switch result {
            case .success(let metas):
                let known = Set(self.items.map { $0.id })
                let fresh = metas.filter { !known.contains($0.id) }
                if fresh.isEmpty { self.reachedEnd = true }
                self.items += fresh
                self.collectionView.reloadData()
                if self.items.isEmpty {
                    self.messageLabel.text = "Nothing found."
                    self.messageLabel.isHidden = false
                }
            case .failure:
                self.reachedEnd = true
                if self.items.isEmpty {
                    self.messageLabel.text = "Couldn't load this catalog."
                    self.messageLabel.isHidden = false
                }
            }
        }
    }

    // MARK: Collection

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { items.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PosterCell.reuseId, for: indexPath) as! PosterCell
        let m = items[indexPath.item]
        cell.configure(with: PosterItem(ref: m.ref, subtitle: m.releaseInfo, progress: nil))
        if indexPath.item >= items.count - 8 { loadMore() }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let available = collectionView.bounds.width - 32
        let target: CGFloat = traitCollection.horizontalSizeClass == .regular ? 150 : 108
        let columns = max(3, Int((available + 12) / (target + 12)))
        let w = floor((available - CGFloat(columns - 1) * 12) / CGFloat(columns))
        return CGSize(width: w, height: PosterCell.height(forWidth: w))
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        navigationController?.pushViewController(DetailViewController(ref: items[indexPath.item].ref), animated: true)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in self.layout.invalidateLayout() })
    }
}
