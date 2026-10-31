import UIKit
import SafariServices

final class DetailViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private var ref: MediaRef
    private var meta: MetaItem?
    private var seasons: [Int] = []
    private var selectedSeason = 0
    private var episodes: [Video] = []

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let spinner = UIActivityIndicatorView(style: .whiteLarge)
    private let errorLabel = UILabel()

    init(ref: MediaRef) {
        self.ref = ref
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var hasEpisodes: Bool {
        guard let m = meta else { return false }
        return m.type != "movie" && !m.videos.isEmpty
    }

    private var movieVideoId: String { meta?.defaultVideoId ?? meta?.id ?? ref.id }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationItem.largeTitleDisplayMode = .never

        tableView.backgroundColor = Theme.background
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.estimatedRowHeight = 120
        tableView.rowHeight = UITableView.automaticDimension
        tableView.register(HeroCell.self, forCellReuseIdentifier: HeroCell.reuseId)
        tableView.register(EpisodeCell.self, forCellReuseIdentifier: EpisodeCell.reuseId)
        tableView.isHidden = true

        errorLabel.textColor = Theme.secondaryText
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true

        for v in [tableView, spinner, errorLabel] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(libraryChanged), name: .libraryChanged, object: nil)
        load()
    }

    // MARK: Loading

    private func load() {
        let candidates = AddonStore.shared.addons(supporting: "meta", type: ref.type, id: ref.id)
        guard !candidates.isEmpty else {
            fail("None of your addons can show details for this title.")
            return
        }
        spinner.startAnimating()
        attempt(candidates, index: 0)
    }

    private func attempt(_ list: [Addon], index: Int) {
        guard index < list.count else { fail("Couldn't load details."); return }
        StremioAPI.shared.meta(addon: list[index], type: ref.type, id: ref.id) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let m): self.apply(m)
            case .failure: self.attempt(list, index: index + 1)
            }
        }
    }

    private func fail(_ message: String) {
        spinner.stopAnimating()
        errorLabel.text = message
        errorLabel.isHidden = false
    }

    private func apply(_ m: MetaItem) {
        meta = m
        ref = MediaRef(id: ref.id, type: ref.type,
                       name: m.name.isEmpty ? ref.name : m.name,
                       poster: m.poster ?? ref.poster)
        seasons = Array(Set(m.videos.map { $0.season ?? 0 })).sorted()

        let resumeSeason = LibraryStore.shared.watchState(for: ref.id).flatMap { ws in
            m.videos.first(where: { $0.id == ws.videoId })?.season
        }
        selectedSeason = resumeSeason ?? seasons.first(where: { $0 > 0 }) ?? seasons.first ?? 0
        updateEpisodes()

        spinner.stopAnimating()
        tableView.isHidden = false
        tableView.reloadData()
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "•••", style: .plain,
                                                            target: self, action: #selector(moreTapped(_:)))
    }

    private func updateEpisodes() {
        episodes = (meta?.videos ?? [])
            .filter { ($0.season ?? 0) == selectedSeason }
            .sorted { a, b in
                if (a.episode ?? 0) != (b.episode ?? 0) { return (a.episode ?? 0) < (b.episode ?? 0) }
                return (a.released ?? .distantPast) < (b.released ?? .distantPast)
            }
    }

    @objc private func libraryChanged() {
        guard meta != nil else { return }
        tableView.reloadData()
    }

    // MARK: Play

    private func resumeVideo() -> Video? {
        guard let m = meta else { return nil }
        if let ws = LibraryStore.shared.watchState(for: ref.id),
           let v = m.videos.first(where: { $0.id == ws.videoId }) {
            return v
        }
        let ordered = Episodes.ordered(m.videos)
        let regular = ordered.filter { ($0.season ?? 0) > 0 }
        let pool = regular.isEmpty ? ordered : regular
        return pool.first { !LibraryStore.shared.isWatched($0.id) } ?? pool.first ?? episodes.first
    }

    private func playTitle() -> String {
        if hasEpisodes {
            guard let v = resumeVideo() else { return "Play" }
            let ws = LibraryStore.shared.watchState(for: ref.id)
            let resuming = ws?.videoId == v.id && ws?.isUpNext == false
            return (resuming ? "Resume " : "Play ") + v.shortLabel
        }
        return LibraryStore.shared.position(for: movieVideoId) > 0 ? "Resume" : "Play"
    }

    private func playTapped() {
        if hasEpisodes {
            guard let v = resumeVideo() else { return }
            openStreams(videoId: v.id, label: v.longLabel)
        } else {
            openStreams(videoId: movieVideoId, label: nil)
        }
    }

    private func openStreams(videoId: String, label: String?) {
        let vc = StreamsViewController(ref: ref, videoId: videoId, label: label, meta: meta)
        navigationController?.pushViewController(vc, animated: true)
    }

    // MARK: Watched & trailers

    private func setWatched(_ videos: [Video], watched: Bool) {
        guard let m = meta else { return }
        let last = Episodes.ordered(videos).last
        let next = last.flatMap { Episodes.next(after: $0.id, in: m.videos) }
        LibraryStore.shared.setWatched(videos.map { $0.id }, watched: watched, ref: ref, next: next)
    }

    @objc private func moreTapped(_ sender: UIBarButtonItem) {
        guard let m = meta else { return }
        let sheet = UIAlertController(title: ref.name, message: nil, preferredStyle: .actionSheet)
        if hasEpisodes {
            let seasonName = selectedSeason == 0 ? "Specials" : "Season \(selectedSeason)"
            let allWatched = !episodes.isEmpty && episodes.allSatisfy { LibraryStore.shared.isWatched($0.id) }
            sheet.addAction(UIAlertAction(title: "Mark \(seasonName) \(allWatched ? "Unwatched" : "Watched")",
                                          style: .default) { [weak self] _ in
                guard let self = self else { return }
                self.setWatched(self.episodes, watched: !allWatched)
            })
            let aired = m.videos.filter { ($0.released ?? .distantPast) <= Date() && ($0.season ?? 0) > 0 }
            sheet.addAction(UIAlertAction(title: "Mark All Episodes Watched", style: .default) { [weak self] _ in
                self?.setWatched(aired, watched: true)
            })
            sheet.addAction(UIAlertAction(title: "Mark All Episodes Unwatched", style: .default) { [weak self] _ in
                guard let self = self else { return }
                self.setWatched(m.videos, watched: false)
                LibraryStore.shared.removeFromContinue(self.ref.id)
            })
        } else {
            let watched = LibraryStore.shared.isWatched(movieVideoId)
            sheet.addAction(UIAlertAction(title: watched ? "Mark as Unwatched" : "Mark as Watched", style: .default) { [weak self] _ in
                guard let self = self else { return }
                LibraryStore.shared.setWatched([self.movieVideoId], watched: !watched, ref: self.ref)
                if !watched { LibraryStore.shared.removeFromContinue(self.ref.id) }
            })
        }
        if !m.trailers.isEmpty {
            sheet.addAction(UIAlertAction(title: "Watch Trailer", style: .default) { [weak self] _ in self?.playTrailer() })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController { pop.barButtonItem = sender }
        present(sheet, animated: true)
    }

    private func playTrailer() {
        guard let trailers = meta?.trailers, !trailers.isEmpty else { return }
        guard trailers.count > 1 else { openTrailer(trailers[0].id); return }
        let sheet = UIAlertController(title: "Trailers", message: nil, preferredStyle: .actionSheet)
        for (i, t) in trailers.prefix(8).enumerated() {
            sheet.addAction(UIAlertAction(title: "\(t.title) \(i + 1)", style: .default) { [weak self] _ in
                self?.openTrailer(t.id)
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentSheet(sheet, from: nil)
    }

    private func openTrailer(_ youtubeId: String) {
        let id = StremioAPI.encode(youtubeId)
        if let app = URL(string: "youtube://watch?v=\(id)"), UIApplication.shared.canOpenURL(app) {
            UIApplication.shared.open(app, options: [:])
        } else if let web = URL(string: "https://m.youtube.com/watch?v=\(id)") {
            let safari = SFSafariViewController(url: web)
            safari.preferredControlTintColor = Theme.accent
            safari.preferredBarTintColor = Theme.background
            present(safari, animated: true)
        }
    }

    @objc private func seasonTapped(_ sender: UIButton) {
        let sheet = UIAlertController(title: "Season", message: nil, preferredStyle: .actionSheet)
        for s in seasons {
            let title = s == 0 ? "Specials" : "Season \(s)"
            sheet.addAction(UIAlertAction(title: s == selectedSeason ? "✓ \(title)" : title, style: .default) { [weak self] _ in
                guard let self = self else { return }
                self.selectedSeason = s
                self.updateEpisodes()
                self.tableView.reloadData()
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentSheet(sheet, from: sender)
    }

    // MARK: Table

    func numberOfSections(in tableView: UITableView) -> Int {
        meta == nil ? 0 : (hasEpisodes ? 2 : 1)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : episodes.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0, let m = meta {
            let cell = tableView.dequeueReusableCell(withIdentifier: HeroCell.reuseId, for: indexPath) as! HeroCell
            cell.configure(meta: m, inLibrary: LibraryStore.shared.contains(ref.id), playTitle: playTitle())
            cell.onPlay = { [weak self] in self?.playTapped() }
            cell.onTrailer = m.trailers.isEmpty ? nil : { [weak self] in self?.playTrailer() }
            cell.onLibrary = { [weak self] in
                guard let self = self else { return }
                LibraryStore.shared.toggle(self.ref)
            }
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: EpisodeCell.reuseId, for: indexPath) as! EpisodeCell
        let v = episodes[indexPath.row]
        cell.configure(video: v,
                       progress: LibraryStore.shared.progress(for: v.id)?.fraction,
                       watched: LibraryStore.shared.isWatched(v.id))
        return cell
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section == 1 else { return nil }
        let header = UIView()
        header.backgroundColor = Theme.background
        let button = UIButton(type: .system)
        let label = selectedSeason == 0 ? "Specials" : "Season \(selectedSeason)"
        button.setTitle(seasons.count > 1 ? "\(label)  ▾" : (seasons.first == nil ? "Episodes" : label), for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        button.setTitleColor(Theme.text, for: .normal)
        button.isEnabled = seasons.count > 1
        button.setTitleColor(Theme.text, for: .disabled)
        button.addTarget(self, action: #selector(seasonTapped(_:)), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            button.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])
        return header
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        section == 1 ? 50 : CGFloat.leastNormalMagnitude
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        CGFloat.leastNormalMagnitude
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? { nil }

    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        indexPath.section == 1
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.section == 1, episodes.indices.contains(indexPath.row) else { return nil }
        let v = episodes[indexPath.row]
        let watched = LibraryStore.shared.isWatched(v.id)
        let action = UIContextualAction(style: .normal, title: watched ? "Unwatched" : "Watched") { [weak self] _, _, done in
            self?.setWatched([v], watched: !watched)
            done(true)
        }
        action.backgroundColor = watched ? Theme.surfaceHigh : Theme.accent
        return UISwipeActionsConfiguration(actions: [action])
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1 else { return }
        let v = episodes[indexPath.row]
        openStreams(videoId: v.id, label: v.longLabel)
    }
}
