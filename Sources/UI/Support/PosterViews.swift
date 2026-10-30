import UIKit

struct PosterItem {
    let ref: MediaRef
    var subtitle: String? = nil
    var progress: Double? = nil
}

enum RowState {
    case loading
    case loaded
    case empty(String)
    case failed(String)
}

final class PosterCell: UICollectionViewCell {
    static let reuseId = "PosterCell"

    static func height(forWidth w: CGFloat) -> CGFloat { w * 1.5 + 40 }

    private let posterView = UIView()
    private let fallbackLabel = UILabel()
    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let progressBar = ProgressBar()

    override init(frame: CGRect) {
        super.init(frame: frame)

        posterView.backgroundColor = Theme.surface
        posterView.layer.cornerRadius = 8
        posterView.clipsToBounds = true

        fallbackLabel.textColor = UIColor(white: 1, alpha: 0.5)
        fallbackLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        fallbackLabel.textAlignment = .center
        fallbackLabel.numberOfLines = 0

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true

        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = Theme.text
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = Theme.secondaryText

        for v in [posterView, titleLabel, subtitleLabel] {
            v.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(v)
        }
        for v in [fallbackLabel, imageView, progressBar] {
            v.translatesAutoresizingMaskIntoConstraints = false
            posterView.addSubview(v)
        }

        NSLayoutConstraint.activate([
            posterView.topAnchor.constraint(equalTo: contentView.topAnchor),
            posterView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            posterView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            posterView.heightAnchor.constraint(equalTo: posterView.widthAnchor, multiplier: 1.5),

            fallbackLabel.leadingAnchor.constraint(equalTo: posterView.leadingAnchor, constant: 8),
            fallbackLabel.trailingAnchor.constraint(equalTo: posterView.trailingAnchor, constant: -8),
            fallbackLabel.centerYAnchor.constraint(equalTo: posterView.centerYAnchor),

            imageView.topAnchor.constraint(equalTo: posterView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: posterView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: posterView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: posterView.trailingAnchor),

            progressBar.leadingAnchor.constraint(equalTo: posterView.leadingAnchor, constant: 6),
            progressBar.trailingAnchor.constraint(equalTo: posterView.trailingAnchor, constant: -6),
            progressBar.bottomAnchor.constraint(equalTo: posterView.bottomAnchor, constant: -6),
            progressBar.heightAnchor.constraint(equalToConstant: 3),

            titleLabel.topAnchor.constraint(equalTo: posterView.bottomAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with item: PosterItem) {
        titleLabel.text = item.ref.name
        fallbackLabel.text = item.ref.name
        subtitleLabel.text = item.subtitle
        imageView.loadImage(item.ref.poster, maxPixel: 480)
        if let p = item.progress, p > 0 {
            progressBar.isHidden = false
            progressBar.progress = max(p, 0.03)
        } else {
            progressBar.isHidden = true
        }
    }

    override var isHighlighted: Bool {
        didSet { contentView.alpha = isHighlighted ? 0.6 : 1 }
    }
}

final class PosterRowCell: UITableViewCell, UICollectionViewDataSource, UICollectionViewDelegate {
    static let reuseId = "PosterRowCell"

    static func posterWidth(for traits: UITraitCollection) -> CGFloat {
        traits.horizontalSizeClass == .regular ? 140 : 108
    }

    static func height(for traits: UITraitCollection) -> CGFloat {
        let w = posterWidth(for: traits)
        return 44 + PosterCell.height(forWidth: w) + 14
    }

    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .white)
    private let layout = UICollectionViewFlowLayout()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private var items: [PosterItem] = []

    var onSelect: ((PosterItem) -> Void)?
    var onLongPress: ((PosterItem, UIView) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        titleLabel.font = .systemFont(ofSize: 19, weight: .bold)
        titleLabel.textColor = Theme.text
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textColor = Theme.secondaryText
        statusLabel.numberOfLines = 2

        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.scrollsToTop = false
        collectionView.decelerationRate = .fast
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(PosterCell.self, forCellWithReuseIdentifier: PosterCell.reuseId)

        let press = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
        collectionView.addGestureRecognizer(press)

        for v in [titleLabel, collectionView, statusLabel, spinner] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(v)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16),

            collectionView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            collectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),

            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16),
            statusLabel.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),

            spinner.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        collectionView.setContentOffset(.zero, animated: false)
    }

    func configure(title: String, items: [PosterItem], state: RowState) {
        titleLabel.text = title
        self.items = items
        let w = PosterRowCell.posterWidth(for: traitCollection)
        layout.itemSize = CGSize(width: w, height: PosterCell.height(forWidth: w))
        collectionView.reloadData()

        switch state {
        case .loading:
            spinner.startAnimating()
            statusLabel.text = nil
        case .loaded:
            spinner.stopAnimating()
            statusLabel.text = nil
        case .empty(let msg), .failed(let msg):
            spinner.stopAnimating()
            statusLabel.text = msg
        }
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PosterCell.reuseId, for: indexPath) as! PosterCell
        cell.configure(with: items[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard items.indices.contains(indexPath.item) else { return }
        onSelect?(items[indexPath.item])
    }

    @objc private func longPressed(_ gr: UILongPressGestureRecognizer) {
        guard gr.state == .began,
              let ip = collectionView.indexPathForItem(at: gr.location(in: collectionView)),
              items.indices.contains(ip.item),
              let cell = collectionView.cellForItem(at: ip) else { return }
        onLongPress?(items[ip.item], cell)
    }
}
