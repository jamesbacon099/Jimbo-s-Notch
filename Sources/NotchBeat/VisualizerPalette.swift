import AppKit
import SwiftUI

struct TrailPalette {
    let primary: Color
    let secondary: Color
    let highlight: Color

    var colors: [Color] { [primary, secondary, highlight] }

    init(_ primary: Color, _ secondary: Color, _ highlight: Color) {
        self.primary = primary
        self.secondary = secondary
        self.highlight = highlight
    }

    init(hue: Double) {
        self.init(Color(hue: hue, saturation: 0.76, brightness: 1),
                  Color(hue: (hue + 0.15).truncatingRemainder(dividingBy: 1), saturation: 0.81, brightness: 0.98),
                  Color(hue: (hue + 0.86).truncatingRemainder(dividingBy: 1), saturation: 0.55, brightness: 1))
    }
}

enum VisualizerPalette: String, CaseIterable, Identifiable {
    case automatic = "Auto"
    case albumArt = "Album Art"
    case prism = "Prism"
    case tide = "Tide"
    case bloom = "Bloom"
    case ember = "Ember"
    case volt = "Volt"
    case glacier = "Glacier"
    case blackAndWhite = "B&W"
    case spectrum = "Spectrum"

    var id: String { rawValue }

    var colors: TrailPalette {
        switch self {
        case .blackAndWhite: return TrailPalette(.white, color(0x292929), color(0xBEBEBE))
        case .spectrum: return TrailPalette(hue: 0.5)
        case .automatic, .albumArt: return TrailPalette(color(0xFFAD5A), color(0x53E9CB), color(0x9E7EFF))
        case .prism: return TrailPalette(.cyan, color(0xA77AFF), color(0xFF63C6))
        case .tide: return TrailPalette(color(0x55FFD0), color(0x29A8FF), color(0x5770FF))
        case .bloom: return TrailPalette(color(0xFF87BA), color(0xAD81FF), color(0xFFBB90))
        case .ember: return TrailPalette(color(0xFFB64C), color(0xFF5B52), color(0xF96BC6))
        case .volt: return TrailPalette(color(0xCEFF59), color(0x40EFA2), color(0x60ACFF))
        case .glacier: return TrailPalette(color(0xD5F6FF), color(0x73A6FF), color(0xC1AEFF))
        }
    }

    private func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

@MainActor
final class VisualizerSettings: ObservableObject {
    @Published var selectedPalette: VisualizerPalette {
        didSet {
            defaults.set(selectedPalette.rawValue, forKey: "selectedPalette")
            if selectedPalette != .automatic && selectedPalette != .albumArt {
                lastFixedPalette = selectedPalette
                defaults.set(selectedPalette.rawValue, forKey: "lastFixedPalette")
            }
        }
    }

    @Published private(set) var spectrumHue: Double

    @Published private(set) var artworkColors: [UInt32]?
    private var artworkTask: Task<Void, Never>?
    private var artworkPlayers: [AlbumArtwork.Player] = []
    private let defaults: UserDefaults
    private var lastFixedPalette: VisualizerPalette

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedHue = defaults.object(forKey: "spectrumHue") as? Double ?? 0.5
        spectrumHue = min(1, max(0, savedHue))
        let selection = defaults.string(forKey: "selectedPalette").flatMap(VisualizerPalette.init(rawValue:)) ?? .automatic
        let savedFixed = defaults.string(forKey: "lastFixedPalette").flatMap(VisualizerPalette.init(rawValue:))
        selectedPalette = selection
        lastFixedPalette = [.automatic, .albumArt].contains(selection) ? savedFixed ?? .prism : selection
    }

    func setAutoColor(_ enabled: Bool) {
        selectedPalette = enabled ? .automatic : lastFixedPalette
    }

    func selectSpectrum(_ hue: Double, persist: Bool) {
        let hue = min(1, max(0, hue))
        if spectrumHue != hue { spectrumHue = hue }
        if selectedPalette != .spectrum { selectedPalette = .spectrum }
        if persist { defaults.set(hue, forKey: "spectrumHue") }
    }

    func updateArtwork(listening: Bool, source: AudioMonitor.AudioSource) {
        var players: [AlbumArtwork.Player] = []
        if listening && selectedPalette == .albumArt {
            switch source {
            case .system: players = AlbumArtwork.Player.allCases
            case .application(let app): players = AlbumArtwork.Player.allCases.filter { $0.rawValue == app.bundleID }
            case .microphone: break
            }
        }
        guard players != artworkPlayers else { return }
        artworkPlayers = players
        if artworkColors != nil { artworkColors = nil }
        artworkTask?.cancel()
        startArtworkPolling()
    }

    private func startArtworkPolling() {
        guard artworkTask == nil, !artworkPlayers.isEmpty else { return }
        let players = artworkPlayers
        artworkTask = Task { [weak self] in
            defer {
                // Wait for the current query to finish before starting another player poll.
                self?.artworkTask = nil
                self?.startArtworkPolling()
            }
            var current: AlbumArtwork.Track?
            while !Task.isCancelled {
                var next: AlbumArtwork.Track?
                for player in players where !NSRunningApplication.runningApplications(withBundleIdentifier: player.rawValue).isEmpty {
                    next = await AlbumArtwork.read(player, previous: current)
                    if next?.colors != nil || Task.isCancelled { break }
                }
                guard !Task.isCancelled, let self else { return }
                current = next
                if artworkColors != current?.colors { artworkColors = current?.colors }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    var basePalette: TrailPalette {
        if selectedPalette == .albumArt, let artworkColors, let first = artworkColors.first {
            func visible(_ key: UInt32, floor: Double) -> Color {
                let r = Double(key >> 16)
                let g = Double((key >> 8) & 255)
                let b = Double(key & 255)
                let peak = max(r, g, b)
                guard peak > 0 else { return Color(white: floor / 255) }
                let gain = max(1, floor / peak)
                return Color(red: r * gain / 255, green: g * gain / 255, blue: b * gain / 255)
            }
            return TrailPalette(visible(first, floor: 170),
                                visible(artworkColors.dropFirst().first ?? first, floor: 120),
                                visible(artworkColors.dropFirst(2).first ?? first, floor: 225))
        }
        return selectedPalette == .spectrum ? TrailPalette(hue: spectrumHue) : selectedPalette.colors
    }

    func palette(for frame: AudioFrame) -> TrailPalette {
        if selectedPalette == .automatic || (selectedPalette == .albumArt && artworkColors == nil),
           let hue = frame.musicHue {
            return TrailPalette(hue: hue)
        }
        return basePalette
    }
}
