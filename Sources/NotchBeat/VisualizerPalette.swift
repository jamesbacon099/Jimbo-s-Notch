import AppKit
import SwiftUI

struct TrailPalette {
    let primary: Color
    let secondary: Color
    let highlight: Color
    var coverGradient: Gradient? = nil
    var sparkleHighlight: Color = .white

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
    case sunset = "Sunset"
    case rave = "Rave"
    case mint = "Mint"
    case blackAndWhite = "B&W"
    case allWhite = "All White"
    case allBlack = "All Black"
    case spectrum = "Spectrum"

    var id: String { rawValue }
    var displayName: String { self == .automatic ? "Rainbow" : rawValue }

    var colors: TrailPalette {
        switch self {
        case .sunset: return TrailPalette(color(0xFF824D), color(0xE83475), color(0xFFDC82))
        case .rave: return TrailPalette(color(0xFF36DB), color(0x693AFF), color(0x59FFCE))
        case .mint: return TrailPalette(color(0x8DFFD5), color(0x21BA98), color(0xE8FFF2))
        case .allWhite: return TrailPalette(.white, .white, .white)
        case .allBlack:
            var palette = TrailPalette(.black, .black, .black)
            palette.sparkleHighlight = .black
            return palette
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
    @Published var liquidGlassColors: Bool {
        didSet { defaults.set(liquidGlassColors, forKey: "liquidGlassColors") }
    }

    @Published var relaxedDance = RelaxedDance.martialArts {
        didSet { defaults.set(relaxedDance.rawValue, forKey: "relaxedDance") }
    }

    @Published var dancersPerSide: Int {
        didSet { defaults.set(dancersPerSide, forKey: "dancersPerSide") }
    }

    @Published var rainfallFromNotch: Bool {
        didSet { defaults.set(rainfallFromNotch, forKey: "rainfallFromNotch") }
    }
    @Published var rainfallDensity: Double {
        didSet { defaults.set(rainfallDensity, forKey: "rainfallDensity") }
    }
    @Published var laserThickness: Double {
        didSet { defaults.set(laserThickness, forKey: "laserThickness") }
    }

    @Published var dancerThickness: Double {
        didSet { defaults.set(dancerThickness, forKey: "dancerThickness") }
    }

    @Published var dancerSparks: Bool {
        didSet { defaults.set(dancerSparks, forKey: "dancerSparks") }
    }

    @Published var splashDensity: Double {
        didSet { defaults.set(splashDensity, forKey: "splashDensity") }
    }

    @Published var flowFromNotch: Bool {
        didSet { defaults.set(flowFromNotch, forKey: "fireFromNotch") }
    }

    @Published var effectMotion: EffectMotion {
        didSet {
            defaults.set(["speed": effectMotion.speed, "density": effectMotion.density,
                          "reversed": effectMotion.reversed], forKey: effectPrefix + "motion")
        }
    }

    private static func loadMotion(_ defaults: UserDefaults, style: VisualizerStyle) -> EffectMotion {
        let values = defaults.dictionary(forKey: "visualizer." + style.rawValue + ".motion") ?? [:]
        return EffectMotion(speed: min(2.5, max(0.25, values["speed"] as? Double ?? 1)),
                            density: min(2.5, max(0.6, values["density"] as? Double ?? 1)),
                            reversed: values["reversed"] as? Bool ?? false)
    }

    @Published var plasmaSparks: PlasmaSparks {
        didSet {
            defaults.set(plasmaSparks.size, forKey: "plasmaSparkSize")
            defaults.set(plasmaSparks.density, forKey: "plasmaSparkDensity")
        }
    }

    @Published var proportionalAlbumColors: Bool {
        didSet { defaults.set(proportionalAlbumColors, forKey: "proportionalAlbumColors") }
    }

    @Published var keepColorSettings: Bool {
        didSet {
            guard keepColorSettings != oldValue else { return }
            defaults.set(keepColorSettings, forKey: "keepColorSettings")
            if keepColorSettings {
                defaults.set(selectedPalette.rawValue, forKey: colorPrefix + "selectedPalette")
                defaults.set(lastFixedPalette.rawValue, forKey: colorPrefix + "lastFixedPalette")
                defaults.set(spectrumHue, forKey: colorPrefix + "spectrumHue")
            } else {
                restoreEffectColors()
            }
        }
    }

    private var colorPrefix: String { keepColorSettings ? Self.sharedColorPrefix : effectPrefix }
    private static let sharedColorPrefix = "visualizer.sharedColors."

    private func restoreEffectColors() {
        let colors = Self.loadColors(defaults, prefix: effectPrefix)
        selectedPalette = colors.palette
        lastFixedPalette = colors.fixed
        spectrumHue = colors.hue
    }

    @Published var selectedStyle: VisualizerStyle {
        didSet {
            guard selectedStyle != oldValue else { return }
            defaults.set(selectedStyle.rawValue, forKey: "selectedVisualizerStyle")
            if !keepColorSettings { restoreEffectColors() }
            sizing = TrailSizing(defaults: defaults, prefix: effectPrefix)
            effectMotion = Self.loadMotion(defaults, style: selectedStyle)
        }
    }

    @Published var sizing: TrailSizing {
        didSet { sizing.saveChanges(from: oldValue, to: defaults, prefix: effectPrefix) }
    }

    private var effectPrefix: String { "visualizer." + selectedStyle.rawValue + "." }

    @Published var selectedPalette: VisualizerPalette {
        didSet {
            defaults.set(selectedPalette.rawValue, forKey: colorPrefix + "selectedPalette")
            if selectedPalette != .automatic && selectedPalette != .albumArt {
                lastFixedPalette = selectedPalette
                defaults.set(selectedPalette.rawValue, forKey: colorPrefix + "lastFixedPalette")
            }
        }
    }

    @Published private(set) var spectrumHue: Double

    @Published private(set) var artworkColors: AlbumArtwork.ColorSet?
    private var artworkTask: Task<Void, Never>?
    private var artworkPlayers: [AlbumArtwork.Player] = []
    private let defaults: UserDefaults
    private var lastFixedPalette: VisualizerPalette

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        plasmaSparks = PlasmaSparks(
            size: min(3, max(0.35, defaults.object(forKey: "plasmaSparkSize") as? Double ?? 1)),
            density: min(3, max(0, defaults.object(forKey: "plasmaSparkDensity") as? Double ?? 1))
        )
        proportionalAlbumColors = defaults.bool(forKey: "proportionalAlbumColors")
        let sharesColors = defaults.bool(forKey: "keepColorSettings")
        keepColorSettings = sharesColors
        rainfallFromNotch = defaults.bool(forKey: "rainfallFromNotch")
        rainfallDensity = min(3, max(1, defaults.object(forKey: "rainfallDensity") as? Double ?? 1))
        laserThickness = min(1.5, max(0.35, defaults.object(forKey: "laserThickness") as? Double ?? 1))
        dancerThickness = min(2.4, max(0.65, defaults.object(forKey: "dancerThickness") as? Double ?? 1))
        dancerSparks = defaults.bool(forKey: "dancerSparks")
        splashDensity = min(3, max(1, defaults.object(forKey: "splashDensity") as? Double ?? 1))
        liquidGlassColors = defaults.bool(forKey: "liquidGlassColors")
        relaxedDance = defaults.string(forKey: "relaxedDance").flatMap { saved in
            switch saved {
            case "Rave": return .raveHeadbang
            case "Martial arts flow": return .martialArts
            default: return RelaxedDance(rawValue: saved)
            }
        } ?? .martialArts
        dancersPerSide = min(5, max(1, defaults.integer(forKey: "dancersPerSide")))
        flowFromNotch = defaults.object(forKey: "fireFromNotch") as? Bool ?? true
        let style: VisualizerStyle = defaults.string(forKey: "selectedVisualizerStyle")
            .flatMap { saved in
                switch saved {
                case "Mist", "Water": return .dancers
                case "Inferno": return .splash
                case "Aurora", "Lightning": return .arcade
                case "Orbit": return .pulse
                case "Shatter": return .circuit
                case "Embers", "Jellyfish": return .cityLights
                default: return VisualizerStyle(rawValue: saved)
                }
            } ?? .classic
        selectedStyle = style
        effectMotion = Self.loadMotion(defaults, style: style)
        let prefix = "visualizer." + style.rawValue + "."
        let colors = Self.loadColors(defaults, prefix: sharesColors ? Self.sharedColorPrefix : prefix)
        spectrumHue = colors.hue
        selectedPalette = colors.palette
        lastFixedPalette = colors.fixed
        sizing = TrailSizing(defaults: defaults, prefix: prefix)
    }

    private static func loadColors(_ defaults: UserDefaults, prefix: String)
        -> (palette: VisualizerPalette, fixed: VisualizerPalette, hue: Double) {
        func value(_ key: String) -> Any? {
            defaults.object(forKey: prefix + key) ?? defaults.object(forKey: key)
        }
        let palette = (value("selectedPalette") as? String).flatMap(VisualizerPalette.init(rawValue:)) ?? .automatic
        let savedFixed = (value("lastFixedPalette") as? String).flatMap(VisualizerPalette.init(rawValue:))
        let fixed = [.automatic, .albumArt].contains(palette) ? savedFixed ?? .prism : palette
        let hue = min(1, max(0, value("spectrumHue") as? Double ?? 0.5))
        return (palette, fixed, hue)
    }

    func setAutoColor(_ enabled: Bool) {
        selectedPalette = enabled ? .automatic : lastFixedPalette
    }

    func selectSpectrum(_ hue: Double, persist: Bool) {
        let hue = min(1, max(0, hue))
        if spectrumHue != hue { spectrumHue = hue }
        if selectedPalette != .spectrum { selectedPalette = .spectrum }
        if persist { defaults.set(hue, forKey: colorPrefix + "spectrumHue") }
    }

    func setArtworkColors(_ colors: AlbumArtwork.ColorSet?) {
        if artworkColors != colors { artworkColors = colors }
    }

    func updateArtwork(source: AudioMonitor.AudioSource) {
        var players: [AlbumArtwork.Player] = []
        if selectedPalette == .albumArt {
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

    var basePalette: TrailPalette { palette(for: selectedPalette, hue: spectrumHue) }

    func palette(for selection: VisualizerPalette, hue: Double) -> TrailPalette {
        if selection == .albumArt, let artworkColors, let first = artworkColors.classic.first {
            func visible(_ key: UInt32, floor: Double) -> Color {
                let r = Double(key >> 16)
                let g = Double((key >> 8) & 255)
                let b = Double(key & 255)
                let peak = max(r, g, b)
                guard peak > 0 else { return Color(white: floor / 255) }
                let gain = max(1, floor / peak)
                return Color(red: r * gain / 255, green: g * gain / 255, blue: b * gain / 255)
            }
            guard proportionalAlbumColors, !artworkColors.proportional.isEmpty else {
                return TrailPalette(visible(first, floor: 170),
                                    visible(artworkColors.classic.dropFirst().first ?? first, floor: 120),
                                    visible(artworkColors.classic.dropFirst(2).first ?? first, floor: 225))
            }
            let swatches = artworkColors.proportional
            let colors = swatches.map { visible($0.rgb, floor: 108) }
            var stops: [Gradient.Stop] = []
            var position = 0.0
            for (index, swatch) in swatches.enumerated() {
                let end = min(1, position + swatch.weight)
                let softEdge = min(0.04, swatch.weight * 0.16)
                stops.append(.init(color: colors[index], location: index == 0 ? 0 : position + softEdge))
                stops.append(.init(color: colors[index], location: index == colors.count - 1 ? 1 : end - softEdge))
                position = end
            }
            var palette = TrailPalette(colors[0], colors.dropFirst().first ?? colors[0], colors.last ?? colors[0])
            palette.coverGradient = Gradient(stops: stops)
            return palette
        }
        return selection == .spectrum ? TrailPalette(hue: hue) : selection.colors
    }

    func palette(for frame: AudioFrame) -> TrailPalette {
        if selectedPalette == .automatic || (selectedPalette == .albumArt && artworkColors == nil),
           let hue = frame.musicHue {
            return TrailPalette(hue: hue)
        }
        return basePalette
    }
}
