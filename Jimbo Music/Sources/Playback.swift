import AppKit
import Foundation

enum Player: String, CaseIterable, Identifiable {
    case music = "com.apple.Music"
    case spotify = "com.spotify.client"

    var id: String { rawValue }
    var name: String { self == .music ? "Apple Music" : "Spotify" }
    var running: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: rawValue).isEmpty }
}

struct Track {
    let player: Player
    let id: String
    let title: String
    let artist: String
    let duration: Double
    let position: Double
    let volume: Double?
    let playing: Bool
    let received = ProcessInfo.processInfo.systemUptime

    var elapsed: Double {
        min(duration, position + (playing ? ProcessInfo.processInfo.systemUptime - received : 0))
    }
}

actor Playback {
    private var cachedKey: String?
    private var cachedArtwork: Data?

    func read(_ player: Player) -> (Track, Data?)? {
        let duration = player == .spotify ? "(duration of song) / 1000" : "duration of song"
        let identifier = player == .spotify ? "id of song" : "persistent ID of song"
        guard let output = Self.script("""
            tell application id "\(player.rawValue)"
                if player state is stopped then return ""
                set song to current track
                set trackID to (get \(identifier)) as text
                set trackName to (get name of song) as text
                set trackArtist to (get artist of song) as text
                set trackVolume to ""
                try
                    set trackVolume to (get sound volume) as text
                end try
                set AppleScript's text item delimiters to ASCII character 31
                return {trackID, trackName, trackArtist, (\(duration)) as text, player position as text, (player state is playing) as text, trackVolume} as text
            end tell
            """), !output.isEmpty else { return nil }
        let fields = output.components(separatedBy: "\u{1f}")
        guard fields.count == 7 else { return nil }
        func seconds(_ value: String) -> Double {
            max(0, Double(value.replacingOccurrences(of: ",", with: ".")) ?? 0)
        }
        let track = Track(player: player, id: fields[0], title: fields[1], artist: fields[2],
                          duration: seconds(fields[3]), position: seconds(fields[4]),
                          volume: Double(fields[6]).map { min(100, max(0, $0)) }, playing: fields[5] == "true")
        let key = player.rawValue + ":" + track.id
        if cachedKey != key {
            cachedKey = key
            cachedArtwork = nil
            if player == .spotify,
               let address = Self.script("""
                   tell application id "\(player.rawValue)" to return artwork url of current track
                   """),
               let url = URL(string: address), url.scheme == "https", url.host?.hasSuffix(".scdn.co") == true {
                var request = URLRequest(url: url, timeoutInterval: 4)
                request.cachePolicy = .returnCacheDataElseLoad
                // Download separately so a slow cover never delays track controls.
                Task { await self.fetchCover(request, key: key) }
            } else if player == .music {
                let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: file) }
                _ = Self.script("""
                    tell application id "\(player.rawValue)"
                        if (count of artworks of current track) is 0 then return ""
                        set coverData to raw data of artwork 1 of current track
                    end tell
                    set outputFile to open for access (POSIX file (item 1 of argv)) with write permission
                    try
                        write coverData to outputFile
                    on error
                        close access outputFile
                        return ""
                    end try
                    close access outputFile
                    """, arguments: [file.path])
                cachedArtwork = try? Data(contentsOf: file)
            }
        }
        return (track, cachedArtwork)
    }

    private func fetchCover(_ request: URLRequest, key: String) async {
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, cachedKey == key else { return }
        cachedArtwork = data
    }

    func command(_ command: String, player: Player) {
        _ = Self.script("tell application id \"\(player.rawValue)\" to \(command)")
    }

    private static func script(_ body: String, arguments: [String] = []) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", """
            on run argv
                with timeout of 4 seconds
                    \(body)
                end timeout
            end run
            """, "--"] + arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: output, as: UTF8.self).trimmingCharacters(in: .newlines)
    }
}
