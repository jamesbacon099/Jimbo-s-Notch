import CoreGraphics
import Foundation
import ImageIO

enum AlbumArtwork {
    enum Player: String, CaseIterable {
        case music = "com.apple.Music"
        case spotify = "com.spotify.client"
    }

    struct Swatch: Equatable {
        let rgb: UInt32
        let weight: Double
    }

    struct ColorSet: Equatable {
        let classic: [UInt32]
        let proportional: [Swatch]
    }

    struct Track {
        let player: Player
        let id: String
        let colors: ColorSet?
    }

    static func read(_ player: Player, previous: Track?) async -> Track? {
        let known = previous?.player == player && previous?.colors != nil ? previous?.id ?? "" : ""
        let result = await Task.detached(priority: .utility) { query(player, known: known) }.value
        guard let result, !Task.isCancelled else { return nil }
        if result.id == known { return previous }
        var data = result.data
        if let url = result.url {
            var request = URLRequest(url: url, timeoutInterval: 5)
            request.cachePolicy = .returnCacheDataElseLoad
            if let (cover, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                data = cover
            }
        }
        guard !Task.isCancelled else { return nil }
        let artwork = data
        let colors = await Task.detached(priority: .utility) { artwork.flatMap(palette) }.value
        return Track(player: player, id: result.id, colors: colors)
    }

    private struct Result {
        let id: String
        var data: Data?
        var url: URL?
    }

    private static func query(_ player: Player, known: String) -> Result? {
        let artwork = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: artwork) }
        let body: String
        switch player {
        case .music:
            body = """
            set trackID to persistent ID of current track
            if trackID is item 1 of argv then return trackID
            if (count of artworks of current track) is 0 then return trackID
            set coverData to raw data of artwork 1 of current track
            """
        case .spotify:
            body = """
            set trackID to id of current track
            if trackID is item 1 of argv then return trackID
            return trackID & linefeed & (artwork url of current track)
            """
        }
        let finish = player == .music ? """
        set outputFile to open for access (POSIX file (item 2 of argv)) with write permission
        try
            write coverData to outputFile
        on error errorText number errorNumber
            close access outputFile
            error errorText number errorNumber
        end try
        close access outputFile
        return trackID
        """ : ""
        let script = """
        on run argv
            if application id "\(player.rawValue)" is not running then return ""
            with timeout of 4 seconds
                tell application id "\(player.rawValue)"
                    if player state is stopped then return ""
                    \(body)
                end tell
            end timeout
            \(finish)
        end run
        """

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script, "--", known, artwork.path]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let bytes = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let text = String(data: bytes, encoding: .utf8) else { return nil }
        let lines = text.split(whereSeparator: \.isNewline)
        guard let id = lines.first else { return nil }
        var result = Result(id: String(id))
        if player == .music {
            result.data = try? Data(contentsOf: artwork)
        } else if lines.count > 1, var url = URLComponents(string: String(lines[1])),
                  url.scheme == "https" || url.scheme == "http",
                  url.host?.hasSuffix(".scdn.co") == true {
            url.scheme = "https"
            result.url = url.url
        }
        return result
    }

    static func palette(_ data: Data) -> ColorSet? {
        colors(from: data)?.palette
    }

    static func colors(from data: Data) -> (palette: ColorSet, brightest: UInt32?)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 40
              ] as CFDictionary),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 160,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: 40, height: 40))

        struct Bucket {
            var count = 0
            var red = 0
            var green = 0
            var blue = 0

            var color: UInt32 {
                UInt32(red / count) << 16 | UInt32(green / count) << 8 | UInt32(blue / count)
            }
        }

        var buckets: [Int: Bucket] = [:]
        for offset in stride(from: 0, to: 6400, by: 4) where pixels[offset + 3] > 220 {
            let alpha = Int(pixels[offset + 3])
            let r = Int(pixels[offset]) * 255 / alpha
            let g = Int(pixels[offset + 1]) * 255 / alpha
            let b = Int(pixels[offset + 2]) * 255 / alpha
            let key = (r & 0xE0) << 16 | (g & 0xE0) << 8 | (b & 0xE0)
            var bucket = buckets[key, default: Bucket()]
            bucket.count += 1
            bucket.red += r
            bucket.green += g
            bucket.blue += b
            buckets[key] = bucket
        }

        func distance(_ a: UInt32, _ b: UInt32) -> Int {
            abs(Int(a >> 16) - Int(b >> 16))
            + abs(Int((a >> 8) & 255) - Int((b >> 8) & 255))
            + abs(Int(a & 255) - Int(b & 255))
        }
        let ranked = buckets.values.sorted { left, right in
            left.count == right.count ? left.color < right.color : left.count > right.count
        }
        let pixelCount = ranked.reduce(0) { $0 + $1.count }
        var classic: [UInt32] = []
        for bucket in ranked {
            if !classic.isEmpty && bucket.count * 100 < pixelCount * 3 { break }
            guard classic.allSatisfy({ distance($0, bucket.color) >= 85 }) else { continue }
            classic.append(bucket.color)
            if classic.count == 3 { break }
        }
        // Pool nearby shades before ranking so a dominant color with many
        // slightly different shades still occupies its share of the palette.
        var groups: [Bucket] = []
        for bucket in ranked {
            let nearest = groups.indices.min {
                distance(groups[$0].color, bucket.color) < distance(groups[$1].color, bucket.color)
            }
            if let nearest, distance(groups[nearest].color, bucket.color) < 85 {
                groups[nearest].count += bucket.count
                groups[nearest].red += bucket.red
                groups[nearest].green += bucket.green
                groups[nearest].blue += bucket.blue
            } else {
                groups.append(bucket)
            }
        }
        let dominant = groups.sorted {
            $0.count == $1.count ? $0.color < $1.color : $0.count > $1.count
        }.prefix(3)
        let total = dominant.reduce(0) { $0 + $1.count }
        guard total > 0 else { return nil }
        let colors = dominant.map { Swatch(rgb: $0.color, weight: Double($0.count) / Double(total)) }
        func luminance(_ rgb: UInt32) -> Double {
            func linear(_ component: UInt32) -> Double {
                let value = Double(component & 255) / 255
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(rgb >> 16) + 0.7152 * linear(rgb >> 8) + 0.0722 * linear(rgb)
        }
        let brightest = ranked.lazy.filter { $0.count >= 2 }.map(\.color)
            .filter { luminance($0) >= 0.175 }
            .max { luminance($0) < luminance($1) }
        return (ColorSet(classic: classic, proportional: colors), brightest)
    }
}
