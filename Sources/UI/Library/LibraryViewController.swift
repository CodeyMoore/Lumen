import UIKit

final class LibraryViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private let segment = UISegmentedControl(items: ["All", "Movies", "Series"])
    private let layout = UICollectionViewFlowLayout()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private let emptyLabel = UILabel()
    private var items: [LibraryItem] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Library"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Downloads", style: .plain,
                                                            target: self, action: #selector(openDownloads))
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "History", style: .plain,
                                                           target: self, action: #selector(openHistory))
        view.backgroundColor = Theme.background

        segment.selectedSegmentIndex = 0
        segment.tintColor = Theme.accent
        segment.addTarget(self, action: #selector(reload), for: .valueChanged)

        layout.minimumLineSpacing = 18
        layout.minimumInteritemSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 12, left: 16, bottom: 24, right: 16)
        collectionView.backgroundColor = Theme.background
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(PosterCell.self, forCellWithReuseIdentifier: PosterCell.reuseId)
        collectionView.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:))))

        emptyLabel.textColor = Theme.secondaryText
        emptyLabel.font = .systemFont(ofSize: 16)
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0

        for v in [segment, collectionView, emptyLabel] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        NSLayoutConstraint.activate([
            segment.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            segment.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            segment.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            collectionView.topAnchor.constraint(equalTo: segment.bottomAnchor, constant: 4),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor, constant: -40),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .libraryChanged, object: nil)
        reload()
    }

    @objc private func openHistory() {
        navigationController?.pushViewController(HistoryViewController(), animated: true)
    }

    @objc private func openDownloads() {
        navigationController?.pushViewController(DownloadsViewController(), animated: true)
    }

    @objc private func reload() {
        let all = LibraryStore.shared.items
        switch segment.selectedSegmentIndex {
        case 1: items = all.filter { $0.ref.type == "movie" }
        case 2: items = all.filter { $0.ref.type != "movie" }
        default: items = all
        }
        collectionView.reloadData()
        emptyLabel.isHidden = !items.isEmpty
        emptyLabel.text = all.isEmpty
            ? "Your library is empty.\nTap “+ Library” on any title to save it here."
            : "Nothing here in this filter."
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in self.layout.invalidateLayout() })
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { items.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PosterCell.reuseId, for: indexPath) as! PosterCell
        let ref = items[indexPath.item].ref
        let progress = LibraryStore.shared.watchState(for: ref.id)?.progress
        cell.configure(with: PosterItem(ref: ref, subtitle: nil, progress: progress))
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

    @objc private func longPressed(_ gr: UILongPressGestureRecognizer) {
        guard gr.state == .began,
              let ip = collectionView.indexPathForItem(at: gr.location(in: collectionView)),
              let cell = collectionView.cellForItem(at: ip) else { return }
        let ref = items[ip.item].ref
        let sheet = UIAlertController(title: ref.name, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Remove from Library", style: .destructive) { _ in
            LibraryStore.shared.removeFromLibrary(ref.id)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentSheet(sheet, from: cell)
    }
}
