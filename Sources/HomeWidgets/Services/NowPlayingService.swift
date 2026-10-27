import AppKit

/// Reads the current track from Music or Spotify via AppleScript.
/// Only talks to a player that's already running, so it never launches one by accident.
final class NowPlayingService: PollingMonitor {
    static let shared = NowPlayingService()

    enum Player: String {
        case music = "Music"
        case spotify = "Spotify"

        var bundleID: String {
            switch self {
            case .music: return "com.apple.Music"
            case .spotify: return "com.spotify.client"
            }
        }
    }

    struct Track: Equatable {
        let title: String
        let artist: String
        let album: String
        let isPlaying: Bool
        let position: Double
        let duration: Double
        let player: Player
        let artworkURL: String?
        var sampledAt = Date()

        var progress: Double { duration > 0 ? min(1, position / duration) : 0 }

        /// Where playback is now, counting time since the last sample (so the bar moves smoothly between samples).
        func progress(at date: Date) -> Double {
            guard duration > 0 else { return 0 }
            let now = isPlaying ? position + max(0, date.timeIntervalSince(sampledAt)) : position
            return min(1, now / duration)
        }

        static func == (lhs: Track, rhs: Track) -> Bool {
            lhs.key == rhs.key && lhs.isPlaying == rhs.isPlaying && abs(lhs.position - rhs.position) < 0.5 && lhs.duration == rhs.duration
        }
        var key: String { "\(player.rawValue)|\(title)|\(artist)|\(album)" }
    }

    @Published private(set) var track: Track?
    @Published private(set) var artwork: NSImage?
    /// True from a skip until the new cover arrives; the old cover blurs meanwhile.
    @Published private(set) var artworkLoading = false
    @Published private(set) var errorMessage: String?

    /// Music and Spotify announce track changes, so the timer is only a safety net.
    /// The progress bar moves on its own between samples.
    override var interval: TimeInterval { track?.isPlaying == true ? 10 : 30 }

    private let queue = DispatchQueue(label: "HomeWidgets.nowplaying", qos: .utility)
    private var artworkKey: String?
    private var inFlight = false
    private var playerObservers: [NSObjectProtocol] = []

    override func didStop() {
        playerObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        playerObservers = []
    }

    override func sample() {
        if playerObservers.isEmpty {
            let center = DistributedNotificationCenter.default()
            for name in ["com.apple.Music.playerInfo", "com.spotify.client.PlaybackStateChanged"] {
                playerObservers.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                    self?.refresh()
                })
            }
        }
        guard !inFlight else { return }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let players = [Player.spotify, .music].filter { running.contains($0.bundleID) }
        guard !players.isEmpty else {
            if track != nil { track = nil }
            artwork = nil
            artworkKey = nil
            return
        }
        inFlight = true
        queue.async { [weak self] in
            var found: [Track] = []
            var lastError: String?
            for player in players {
                let (track, error) = Self.query(player)
                if let track { found.append(track) }
                if let error { lastError = error }
            }
            let best = found.first(where: \.isPlaying) ?? found.first
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                let message = best == nil ? lastError : nil
                if self.errorMessage != message { self.errorMessage = message }
                let wasPlaying = self.track?.isPlaying
                if self.track != best { self.track = best }
                if wasPlaying != best?.isPlaying { self.reschedule() }
                if let best, best.key != self.artworkKey {
                    self.artworkKey = best.key
                    self.loadArtwork(for: best)
                } else if best == nil {
                    self.artwork = nil
                    self.artworkKey = nil
                    self.artworkLoading = false
                }
            }
        }
    }

    // MARK: Controls

    func playPause() { send("playpause") }
    func next() { skip("next track") }
    func previous() { skip("previous track") }

    /// Blurs the current cover right away; it sharpens again on the new one.
    private func skip(_ command: String) {
        artworkLoading = true
        send(command)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            if self?.artworkLoading == true { self?.artworkLoading = false }
        }
    }

    private func send(_ command: String) {
        guard let player = track?.player else { return }
        Shell.appleScript("tell application \"\(player.rawValue)\" to \(command)") { [weak self] _, _ in
            self?.refresh()
        }
    }

    // MARK: AppleScript

    private static func query(_ player: Player) -> (Track?, String?) {
        let extra = player == .spotify ? ", artwork url of t" : ""
        let source = """
        tell application "\(player.rawValue)"
            if player state is stopped then return {}
            set t to current track
            return {name of t, artist of t, album of t, (player state as text), player position, duration of t\(extra)}
        end tell
        """
        let (result, error) = Shell.runAppleScriptNow(source)
        guard let list = result, list.numberOfItems >= 6 else { return (nil, error) }
        func string(_ index: Int) -> String { list.atIndex(index)?.stringValue ?? "" }
        func number(_ index: Int) -> Double { list.atIndex(index)?.doubleValue ?? 0 }
        var duration = number(6)
        if player == .spotify { duration /= 1000 } // Spotify reports milliseconds
        let title = string(1)
        guard !title.isEmpty else { return (nil, nil) }
        let track = Track(title: title,
                          artist: string(2),
                          album: string(3),
                          isPlaying: string(4) == "playing",
                          position: number(5),
                          duration: duration,
                          player: player,
                          artworkURL: list.numberOfItems >= 7 ? list.atIndex(7)?.stringValue : nil)
        return (track, nil)
    }

    /// Keeps the old cover (blurred) until the new one is ready, instead of flashing a placeholder.
    private func loadArtwork(for track: Track) {
        if artwork != nil { artworkLoading = true }
        let finish: (NSImage?) -> Void = { [weak self] image in
            DispatchQueue.main.async {
                guard let self, self.artworkKey == track.key else { return }
                self.artwork = image
                self.artworkLoading = false
            }
        }
        if let link = track.artworkURL, let url = URL(string: link) {
            URLSession.shared.dataTask(with: url) { data, _, _ in finish(data.flatMap(NSImage.init(data:))) }.resume()
            return
        }
        guard track.player == .music else { return finish(nil) }
        queue.async {
            let (result, _) = Shell.runAppleScriptNow("tell application \"Music\" to get raw data of artwork 1 of current track")
            finish(result.flatMap { NSImage(data: $0.data) })
        }
    }

    static let sample = Track(title: "Way Maker", artist: "Leeland", album: "Better Word", isPlaying: true,
                              position: 94, duration: 312, player: .music, artworkURL: nil)
}
