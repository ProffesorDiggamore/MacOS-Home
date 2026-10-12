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

        var progress: Double { duration > 0 ? min(1, position / duration) : 0 }
        var key: String { "\(player.rawValue)|\(title)|\(artist)|\(album)" }
    }

    @Published private(set) var track: Track?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var errorMessage: String?

    override var interval: TimeInterval { 2 }

    private let queue = DispatchQueue(label: "HomeWidgets.nowplaying", qos: .utility)
    private var artworkKey: String?
    private var inFlight = false

    override func sample() {
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
                self.errorMessage = best == nil ? lastError : nil
                if self.track != best { self.track = best }
                if let best, best.key != self.artworkKey {
                    self.artworkKey = best.key
                    self.loadArtwork(for: best)
                } else if best == nil {
                    self.artwork = nil
                    self.artworkKey = nil
                }
            }
        }
    }

    // MARK: Controls

    func playPause() { send("playpause") }
    func next() { send("next track") }
    func previous() { send("previous track") }

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

    private func loadArtwork(for track: Track) {
        artwork = nil
        if let link = track.artworkURL, let url = URL(string: link) {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                let image = data.flatMap(NSImage.init(data:))
                DispatchQueue.main.async {
                    guard let self, self.artworkKey == track.key else { return }
                    self.artwork = image
                }
            }.resume()
            return
        }
        guard track.player == .music else { return }
        queue.async { [weak self] in
            let (result, _) = Shell.runAppleScriptNow("tell application \"Music\" to get raw data of artwork 1 of current track")
            let image = result.flatMap { NSImage(data: $0.data) }
            DispatchQueue.main.async {
                guard let self, self.artworkKey == track.key else { return }
                self.artwork = image
            }
        }
    }

    static let sample = Track(title: "Way Maker", artist: "Leeland", album: "Better Word", isPlaying: true,
                              position: 94, duration: 312, player: .music, artworkURL: nil)
}
