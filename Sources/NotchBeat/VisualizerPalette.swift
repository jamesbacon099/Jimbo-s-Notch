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
        case .automatic: return TrailPalette(color(0xFFAD5A), color(0x53E9CB), color(0x9E7EFF))
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
            if selectedPalette != .automatic {
                lastFixedPalette = selectedPalette
                defaults.set(selectedPalette.rawValue, forKey: "lastFixedPalette")
            }
        }
    }

    @Published private(set) var spectrumHue: Double

    private let defaults: UserDefaults
    private var lastFixedPalette: VisualizerPalette

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedHue = defaults.object(forKey: "spectrumHue") as? Double ?? 0.5
        spectrumHue = min(1, max(0, savedHue))
        let selection = defaults.string(forKey: "selectedPalette").flatMap(VisualizerPalette.init(rawValue:)) ?? .automatic
        let savedFixed = defaults.string(forKey: "lastFixedPalette").flatMap(VisualizerPalette.init(rawValue:))
        selectedPalette = selection
        lastFixedPalette = selection == .automatic ? savedFixed ?? .prism : selection
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

    var basePalette: TrailPalette {
        selectedPalette == .spectrum ? TrailPalette(hue: spectrumHue) : selectedPalette.colors
    }

    func palette(for frame: AudioFrame) -> TrailPalette {
        if selectedPalette == .automatic, let hue = frame.musicHue {
            return TrailPalette(hue: hue)
        }
        return basePalette
    }
}
