import UIKit
import MediaPlayer

/// Lock screen / Control Center info and remote controls for the current player.
final class NowPlaying {
    struct Handlers {
        var play: () -> Void
        var pause: () -> Void
        var toggle: () -> Void
        var skip: (Double) -> Void
        var seek: (Double) -> Void
        var next: (() -> Void)?
    }

    private var tokens: [(MPRemoteCommand, Any)] = []
    private var info: [String: Any] = [:]
    private var artworkURL: String?

    func activate(_ h: Handlers) {
        deactivate()
        let c = MPRemoteCommandCenter.shared()
        func add(_ cmd: MPRemoteCommand, _ block: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) {
            cmd.isEnabled = true
            tokens.append((cmd, cmd.addTarget(handler: block)))
        }
        add(c.playCommand) { _ in h.play(); return .success }
        add(c.pauseCommand) { _ in h.pause(); return .success }
        add(c.togglePlayPauseCommand) { _ in h.toggle(); return .success }

        let interval = NSNumber(value: AppSettings.shared.skipInterval)
        c.skipBackwardCommand.preferredIntervals = [interval]
        c.skipForwardCommand.preferredIntervals = [interval]
        add(c.skipBackwardCommand) { e in
            h.skip(-((e as? MPSkipIntervalCommandEvent)?.interval ?? interval.doubleValue)); return .success
        }
        add(c.skipForwardCommand) { e in
            h.skip((e as? MPSkipIntervalCommandEvent)?.interval ?? interval.doubleValue); return .success
        }
        add(c.changePlaybackPositionCommand) { e in
            guard let p = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            h.seek(p.positionTime)
            return .success
        }
        if let next = h.next {
            add(c.nextTrackCommand) { _ in next(); return .success }
        } else {
            c.nextTrackCommand.isEnabled = false
        }
        c.previousTrackCommand.isEnabled = false
    }

    func setNextAvailable(_ available: Bool) {
        MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = available
    }

    func deactivate() {
        for (cmd, token) in tokens { cmd.removeTarget(token) }
        tokens = []
        info = [:]
        artworkURL = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// Sets the title, subtitle and artwork (artwork loads in the background).
    func setItem(title: String, subtitle: String?, artwork: String?) {
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyArtist] = subtitle ?? ""
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.video.rawValue
        info[MPMediaItemPropertyArtwork] = nil
        artworkURL = artwork
        publish()
        guard let art = artwork else { return }
        ImageLoader.shared.load(art, maxPixel: 600) { [weak self] image in
            guard let self = self, self.artworkURL == art, let image = image else { return }
            self.info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.publish()
        }
    }

    /// Call on play/pause, seeks and every few seconds; iOS extrapolates in between.
    func update(elapsed: Double, duration: Double, playing: Bool, rate: Float) {
        info[MPMediaItemPropertyPlaybackDuration] = duration > 0 ? duration : nil
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? Double(rate) : 0.0
        publish()
    }

    private func publish() {
        guard !info.isEmpty else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
