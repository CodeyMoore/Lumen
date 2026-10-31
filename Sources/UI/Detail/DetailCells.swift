import UIKit

final class HeroCell: UITableViewCell {
    static let reuseId = "HeroCell"

    private let backdrop = UIImageView()
    private let gradient = GradientView()
    private let posterView = UIImageView()
    private let titleLabel = UILabel()
    private let infoLabel = UILabel()
    private let genresLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let playButton = UIButton(type: .custom)
    private let libraryButton = UIButton(type: .custom)
    private let trailerButton = UIButton(type: .system)
    private var trailerCollapsed: NSLayoutConstraint!

    var onPlay: (() -> Void)?
    var onLibrary: (() -> Void)?
    var onTrailer: (() -> Void)? {
        didSet {
            trailerButton.isHidden = onTrailer == nil
            trailerCollapsed.isActive = onTrailer == nil
        }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        backdrop.contentMode = .scaleAspectFill
        backdrop.clipsToBounds = true
        backdrop.backgroundColor = Theme.surface
        gradient.colors = [Theme.background.withAlphaComponent(0), Theme.background]

        posterView.contentMode = .scaleAspectFill
        posterView.clipsToBounds = true
        posterView.backgroundColor = Theme.surface
        posterView.layer.cornerRadius = 8
        posterView.layer.borderWidth = 1
        posterView.layer.borderColor = UIColor(white: 1, alpha: 0.1).cgColor

        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = Theme.text
        titleLabel.numberOfLines = 0
        infoLabel.font = .systemFont(ofSize: 14)
        infoLabel.textColor = Theme.secondaryText
        infoLabel.numberOfLines = 0
        genresLabel.font = .systemFont(ofSize: 13, weight: .medium)
        genresLabel.textColor = Theme.secondaryText
        genresLabel.numberOfLines = 0
        descriptionLabel.font = .systemFont(ofSize: 15)
        descriptionLabel.textColor = UIColor(white: 1, alpha: 0.85)
        descriptionLabel.numberOfLines = 0

        self.style(playButton, background: Theme.accent)
        playButton.setImage(Icons.play, for: .normal)
        playButton.tintColor = .white
        playButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 0)
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        self.style(libraryButton, background: Theme.surfaceHigh)
        libraryButton.addTarget(self, action: #selector(libraryTapped), for: .touchUpInside)
        trailerButton.setTitle("▶︎  Watch Trailer", for: .normal)
        trailerButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        trailerButton.tintColor = Theme.accent
        trailerButton.contentHorizontalAlignment = .left
        trailerButton.addTarget(self, action: #selector(trailerTapped), for: .touchUpInside)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, infoLabel])
        textStack.axis = .vertical
        textStack.spacing = 4

        let buttons = UIStackView(arrangedSubviews: [playButton, libraryButton])
        buttons.axis = .horizontal
        buttons.spacing = 12
        buttons.distribution = .fillEqually

        for v in [backdrop, gradient, posterView, textStack, buttons, trailerButton, genresLabel, descriptionLabel] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(v)
        }

        let ratio = backdrop.heightAnchor.constraint(equalTo: backdrop.widthAnchor, multiplier: 0.5625)
        ratio.priority = .defaultHigh

        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: contentView.topAnchor),
            backdrop.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            ratio,
            backdrop.heightAnchor.constraint(lessThanOrEqualToConstant: 340),

            gradient.topAnchor.constraint(equalTo: backdrop.topAnchor),
            gradient.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor),
            gradient.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
            gradient.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),

            posterView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            posterView.topAnchor.constraint(equalTo: backdrop.bottomAnchor, constant: -70),
            posterView.widthAnchor.constraint(equalToConstant: 100),
            posterView.heightAnchor.constraint(equalToConstant: 150),

            textStack.leadingAnchor.constraint(equalTo: posterView.trailingAnchor, constant: 14),
            textStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            textStack.bottomAnchor.constraint(equalTo: posterView.bottomAnchor),

            buttons.topAnchor.constraint(equalTo: posterView.bottomAnchor, constant: 18),
            buttons.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            buttons.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            buttons.heightAnchor.constraint(equalToConstant: 46),

            trailerButton.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 8),
            trailerButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            genresLabel.topAnchor.constraint(equalTo: trailerButton.bottomAnchor, constant: 8),
            genresLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            genresLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            descriptionLabel.topAnchor.constraint(equalTo: genresLabel.bottomAnchor, constant: 8),
            descriptionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            descriptionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            descriptionLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
        ])
        trailerCollapsed = trailerButton.heightAnchor.constraint(equalToConstant: 0)
        trailerButton.isHidden = true
        trailerCollapsed.isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func style(_ b: UIButton, background: UIColor) {
        b.backgroundColor = background
        b.layer.cornerRadius = 10
        b.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        b.titleLabel?.lineBreakMode = .byTruncatingTail
        b.setTitleColor(.white, for: .normal)
        b.setTitleColor(UIColor(white: 1, alpha: 0.6), for: .highlighted)
    }

    func configure(meta: MetaItem, inLibrary: Bool, playTitle: String) {
        backdrop.loadImage(meta.background ?? meta.poster, maxPixel: 1100)
        posterView.loadImage(meta.poster, maxPixel: 480)
        titleLabel.text = meta.name
        var info: [String] = []
        if let r = meta.releaseInfo { info.append(r) }
        if let r = meta.runtime { info.append(r) }
        if let r = meta.imdbRating { info.append("★ \(r)") }
        infoLabel.text = info.joined(separator: "  ·  ")
        genresLabel.text = meta.genres.prefix(5).joined(separator: " · ")
        descriptionLabel.text = meta.description
        playButton.setTitle(playTitle, for: .normal)
        libraryButton.setTitle(inLibrary ? "✓ In Library" : "+ Library", for: .normal)
    }

    @objc private func playTapped() { onPlay?() }
    @objc private func libraryTapped() { onLibrary?() }
    @objc private func trailerTapped() { onTrailer?() }
}

final class EpisodeCell: UITableViewCell {
    static let reuseId = "EpisodeCell"

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private let thumb = UIImageView()
    private let progressBar = ProgressBar()
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let overviewLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        let selected = UIView()
        selected.backgroundColor = Theme.surface
        selectedBackgroundView = selected

        thumb.contentMode = .scaleAspectFill
        thumb.clipsToBounds = true
        thumb.backgroundColor = Theme.surface
        thumb.layer.cornerRadius = 6

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = Theme.text
        titleLabel.numberOfLines = 2
        metaLabel.font = .systemFont(ofSize: 12)
        metaLabel.textColor = Theme.secondaryText
        overviewLabel.font = .systemFont(ofSize: 13)
        overviewLabel.textColor = Theme.secondaryText
        overviewLabel.numberOfLines = 3

        let stack = UIStackView(arrangedSubviews: [titleLabel, metaLabel, overviewLabel])
        stack.axis = .vertical
        stack.spacing = 3

        for v in [thumb, stack] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(v)
        }
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        thumb.addSubview(progressBar)

        let pull = stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        pull.priority = UILayoutPriority(250)

        NSLayoutConstraint.activate([
            thumb.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            thumb.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            thumb.widthAnchor.constraint(equalToConstant: 132),
            thumb.heightAnchor.constraint(equalToConstant: 74),
            thumb.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),

            progressBar.leadingAnchor.constraint(equalTo: thumb.leadingAnchor, constant: 5),
            progressBar.trailingAnchor.constraint(equalTo: thumb.trailingAnchor, constant: -5),
            progressBar.bottomAnchor.constraint(equalTo: thumb.bottomAnchor, constant: -5),
            progressBar.heightAnchor.constraint(equalToConstant: 3),

            stack.leadingAnchor.constraint(equalTo: thumb.trailingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),
            pull,
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(video: Video, progress: Double?, watched: Bool) {
        let name = video.title.isEmpty ? "Episode \(video.episode ?? 0)" : video.title
        if let e = video.episode {
            titleLabel.text = "\(e). \(name)"
        } else {
            titleLabel.text = name
        }
        var meta: [String] = []
        if let d = video.released { meta.append(EpisodeCell.dateFormatter.string(from: d)) }
        if watched { meta.append("Watched ✓") }
        metaLabel.text = meta.joined(separator: "  ·  ")
        metaLabel.isHidden = meta.isEmpty
        overviewLabel.text = video.overview
        overviewLabel.isHidden = video.overview == nil
        thumb.loadImage(video.thumbnail, maxPixel: 400)
        if let p = progress, p > 0 {
            progressBar.isHidden = false
            progressBar.progress = p
        } else {
            progressBar.isHidden = true
        }
        contentView.alpha = watched ? 0.7 : 1
    }
}
