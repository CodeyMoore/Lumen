import UIKit
import AVFoundation
import MobileVLCKit

enum EngineState {
    case loading
    case playing
    case paused
    case ended
    case failed(String)
}

struct TrackOption {
    let id: Int
    let name: String
}

/// A video backend the player UI can drive. The controller polls it a few times a second.
protocol PlayerEngine: AnyObject {
    var view: UIView { get }
    var state: EngineState { get }
    var isBuffering: Bool { get }
    var currentTime: Double { get }
    var duration: Double { get }
    var rate: Float { get set }
    var fill: Bool { get set }
    var name: String { get }

    func load(url: URL, headers: [String: String], startAt: Double)
    func play()
    func pause()
    func seek(to seconds: Double)
    func stop()

    func audioTracks() -> [TrackOption]
    var currentAudioTrack: Int { get }
    func selectAudioTrack(_ id: Int)

    /// Subtitle tracks inside the video file (not addon subtitles).
    func embeddedSubtitles() -> [TrackOption]
    var currentEmbeddedSubtitle: Int { get }
    func selectEmbeddedSubtitle(_ id: Int) // -1 turns them off
}

// MARK: - AVPlayer

private final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

final class AVEngine: PlayerEngine {
    private let layerView = PlayerLayerView()
    private let player = AVPlayer()
    private var ended = false
    private var pendingStart: Double = 0
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var rateValue: Float = 1

    let name = "iOS player"
    var view: UIView { layerView }

    init() {
        layerView.backgroundColor = .black
        layerView.playerLayer.player = player
        layerView.playerLayer.videoGravity = .resizeAspect
    }

    deinit {
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
    }

    func load(url: URL, headers: [String: String], startAt: Double) {
        ended = false
        pendingStart = startAt
        let options: [String: Any]? = headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": headers]
        let item = AVPlayerItem(asset: AVURLAsset(url: url, options: options))
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in self?.ended = true }
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self = self, item.status == .readyToPlay, self.pendingStart > 0 else { return }
                self.seek(to: self.pendingStart)
                self.pendingStart = 0
            }
        }
        player.replaceCurrentItem(with: item)
        play()
    }

    var state: EngineState {
        guard let item = player.currentItem else { return .loading }
        if item.status == .failed {
            return .failed(item.error?.localizedDescription ?? "This stream couldn't be played.")
        }
        if ended { return .ended }
        if item.status != .readyToPlay { return .loading }
        return player.timeControlStatus == .paused ? .paused : .playing
    }

    var isBuffering: Bool { player.timeControlStatus == .waitingToPlayAtSpecifiedRate }

    var currentTime: Double {
        let t = player.currentTime().seconds
        return t.isFinite ? t : 0
    }

    var duration: Double {
        let d = player.currentItem?.duration.seconds ?? 0
        return d.isFinite ? d : 0
    }

    var rate: Float {
        get { rateValue }
        set {
            rateValue = newValue
            if player.rate > 0 { player.rate = newValue }
        }
    }

    var fill: Bool {
        get { layerView.playerLayer.videoGravity == .resizeAspectFill }
        set { layerView.playerLayer.videoGravity = newValue ? .resizeAspectFill : .resizeAspect }
    }

    func play() {
        if ended {
            ended = false
            player.seek(to: .zero)
        }
        player.play()
        player.rate = rateValue
    }

    func pause() { player.pause() }

    func seek(to seconds: Double) {
        ended = false
        player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600))
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func group(_ c: AVMediaCharacteristic) -> AVMediaSelectionGroup? {
        player.currentItem?.asset.mediaSelectionGroup(forMediaCharacteristic: c)
    }

    func audioTracks() -> [TrackOption] {
        guard let g = group(.audible) else { return [] }
        return g.options.enumerated().map { TrackOption(id: $0.offset, name: $0.element.displayName) }
    }

    var currentAudioTrack: Int {
        guard let g = group(.audible), let item = player.currentItem,
              let sel = item.currentMediaSelection.selectedMediaOption(in: g) else { return -1 }
        return g.options.firstIndex(of: sel) ?? -1
    }

    func selectAudioTrack(_ id: Int) {
        guard let g = group(.audible), g.options.indices.contains(id) else { return }
        player.currentItem?.select(g.options[id], in: g)
    }

    func embeddedSubtitles() -> [TrackOption] {
        guard let g = group(.legible) else { return [] }
        return g.options.enumerated().map { TrackOption(id: $0.offset, name: $0.element.displayName) }
    }

    var currentEmbeddedSubtitle: Int {
        guard let g = group(.legible), let item = player.currentItem,
              let sel = item.currentMediaSelection.selectedMediaOption(in: g) else { return -1 }
        return g.options.firstIndex(of: sel) ?? -1
    }

    func selectEmbeddedSubtitle(_ id: Int) {
        guard let g = group(.legible) else { return }
        if g.options.indices.contains(id) {
            player.currentItem?.select(g.options[id], in: g)
        } else {
            player.currentItem?.select(nil, in: g)
        }
    }
}

// MARK: - VLC

final class VLCEngine: NSObject, PlayerEngine {
    private let videoView = UIView()
    private let player = VLCMediaPlayer()
    private var hasPlayed = false
    private var cropString: UnsafeMutablePointer<CChar>?
    private var fillValue = false

    let name = "VLC engine"
    var view: UIView { videoView }

    override init() {
        super.init()
        videoView.backgroundColor = .black
        player.drawable = videoView
    }

    deinit {
        player.stop()
        if let p = cropString { free(p) }
    }

    func load(url: URL, headers: [String: String], startAt: Double) {
        hasPlayed = false
        let media = VLCMedia(url: url)
        var options: [String: Any] = ["network-caching": 2000]
        for (k, v) in headers {
            switch k.lowercased() {
            case "user-agent": options["http-user-agent"] = v
            case "referer", "referrer": options["http-referrer"] = v
            default: break
            }
        }
        if startAt > 1 { options["start-time"] = Int(startAt) }
        media.addOptions(options)
        player.media = media
        player.play()
    }

    var state: EngineState {
        switch player.state {
        case .error:
            return .failed("This stream couldn't be opened.")
        case .ended:
            return .ended
        case .stopped:
            return hasPlayed ? .ended : .loading
        case .paused:
            return .paused
        case .playing, .esAdded:
            hasPlayed = true
            return .playing
        case .opening, .buffering:
            if player.isPlaying { hasPlayed = true; return .playing }
            return hasPlayed ? .paused : .loading
        default:
            return .loading
        }
    }

    var isBuffering: Bool {
        player.state == .buffering || player.state == .opening
    }

    var currentTime: Double { Double(player.time.intValue) / 1000 }

    var duration: Double {
        guard let length = player.media?.length else { return 0 }
        return max(0, Double(length.intValue) / 1000)
    }

    var rate: Float {
        get { player.rate }
        set { player.rate = newValue }
    }

    var fill: Bool {
        get { fillValue }
        set {
            fillValue = newValue
            if let p = cropString { free(p) }
            cropString = nil
            if newValue {
                let size = videoView.bounds.size
                if size.width > 0, size.height > 0 {
                    cropString = strdup("\(Int(size.width)):\(Int(size.height))")
                }
            }
            player.videoCropGeometry = cropString
        }
    }

    func play() {
        if case .ended = state {
            player.stop()
            hasPlayed = false
        }
        player.play()
    }

    func pause() { player.pause() }

    func seek(to seconds: Double) {
        player.time = VLCTime(int: Int32(max(0, seconds) * 1000))
    }

    func stop() { player.stop() }

    private func tracks(names: [Any]?, indexes: [Any]?) -> [TrackOption] {
        let n = (names as? [String]) ?? []
        let i = (indexes as? [NSNumber]) ?? []
        return zip(i, n).compactMap { idx, name in
            idx.intValue < 0 ? nil : TrackOption(id: idx.intValue, name: name)
        }
    }

    func audioTracks() -> [TrackOption] {
        tracks(names: player.audioTrackNames, indexes: player.audioTrackIndexes)
    }

    var currentAudioTrack: Int { Int(player.currentAudioTrackIndex) }

    func selectAudioTrack(_ id: Int) { player.currentAudioTrackIndex = Int32(id) }

    func embeddedSubtitles() -> [TrackOption] {
        tracks(names: player.videoSubTitlesNames, indexes: player.videoSubTitlesIndexes)
    }

    var currentEmbeddedSubtitle: Int { Int(player.currentVideoSubTitleIndex) }

    func selectEmbeddedSubtitle(_ id: Int) { player.currentVideoSubTitleIndex = Int32(id) }
}
