import AppKit
import Combine
import SwiftUI

@MainActor
private final class Studio: ObservableObject {
    let audio: AudioMonitor
    private let musicAudio: AudioMonitor
    private let spectrum: MusicSpectrum
    let monitorColors: MonitorColors
    let overlay: NotchOverlayController
    let island: MusicIsland
    private var musicSourceSubscription: AnyCancellable?
    private var autoAccentSubscription: AnyCancellable?
    private var tintSubscription: AnyCancellable?

    init() {
        // Seed preferences from the standalone apps. Studio writes to its own domain.
        let notch = UserDefaults.standard.persistentDomain(forName: "local.notchbeat.visualizer") ?? [:]
        let music = UserDefaults.standard.persistentDomain(forName: "local.jimbo.music") ?? [:]
        let studio = UserDefaults.standard.persistentDomain(forName: "local.jimbo.studio") ?? [:]
        var inherited = notch.merging(music) { _, newer in newer }.merging(studio) { _, newer in newer }
        if let url = Bundle.main.url(forResource: "BundledPreferences", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let preset = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] {
            inherited.merge(preset) { _, bundled in bundled }
        }
        UserDefaults.standard.register(defaults: inherited)
        monitorColors = MonitorColors()

        audio = AudioMonitor()
        musicAudio = AudioMonitor(ignoresOutputVolume: true)
        island = MusicIsland()
        spectrum = MusicSpectrum(input: musicAudio.frames, player: island.model)
        overlay = NotchOverlayController(audio: audio, usesIntegratedPlayer: true,
                                         musicSpectrumFrames: spectrum.frames)
        island.sharedScreen = { [weak overlay] in overlay?.preferredScreen }
        island.onFrameChange = { [weak overlay] frame in overlay?.positionAroundPlayer(frame) }
        let settings = overlay.settings
        island.model.artworkTintProvider = { [weak settings] artwork in
            let colors = artwork.flatMap { AlbumArtwork.colors(from: $0) }
            settings?.setArtworkColors(colors?.palette)
            func color(_ rgb: UInt32) -> Color {
                Color(red: Double((rgb >> 16) & 255) / 255,
                      green: Double((rgb >> 8) & 255) / 255,
                      blue: Double(rgb & 255) / 255)
            }
            return colors?.palette.first.map(color)
        }
        let frames = audio.frames
        let musicFrames = spectrum.frames
        let monitorColors = monitorColors
        island.spectrumView = { AnyView(PlayerSpectrum(frames: musicFrames, settings: settings, colors: monitorColors)) }
        autoAccentSubscription = musicFrames.$current
            .throttle(for: .milliseconds(75), scheduler: RunLoop.main, latest: true)
            .sink { [weak island] frame in
                guard let model = island?.model, let hue = frame.musicHue else { return }
                let accent = TrailPalette(hue: hue).primary
                if model.autoAccent != accent { model.autoAccent = accent }
            }
        // Track metadata and audio permissions are separate. Capture only music
        // apps, even if Automation cannot currently provide their track details.
        musicSourceSubscription = Timer.publish(every: 0.75, on: .main, in: .common).autoconnect()
            .prepend(Date())
            .sink { [weak musicAudio, weak island] _ in
                guard let musicAudio, let model = island?.model else { return }
                let players = Player.allCases.filter { model.source == "Auto" || $0.rawValue == model.source }
                let candidates = AudioApplication.choices().filter { app in
                    players.contains { $0.rawValue == app.bundleID }
                }
                let app = candidates.first { $0.bundleID == model.track?.player.rawValue }
                    ?? candidates.first { $0.bundleID == Player.spotify.rawValue }
                    ?? candidates.first
                guard let app else {
                    if musicAudio.running { musicAudio.stop() }
                    return
                }
                musicAudio.select(.application(app))
                if !musicAudio.running { musicAudio.start() }
            }
        island.model.visualizerTint = settings.palette(for: frames.current).primary
        tintSubscription = settings.objectWillChange
            .merge(with: frames.$current.map { _ in () })
            .throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
            .receive(on: RunLoop.main)
            .sink { [weak settings, weak frames, weak island] _ in
                guard let settings, let frames, let island else { return }
                let tint = settings.palette(for: frames.current).primary
                if island.model.visualizerTint != tint { island.model.visualizerTint = tint }
            }
        if ProcessInfo.processInfo.arguments.contains("--preview-player") {
            island.model.preview = true
        }
        DispatchQueue.main.async { [weak island] in island?.start() }
    }
}

@MainActor
private final class MusicSpectrum {
    let frames = AudioFrames()
    private var subscriptions = Set<AnyCancellable>()
    private let input: AudioFrames
    private weak var player: MusicModel?

    init(input: AudioFrames, player: MusicModel) {
        self.input = input
        self.player = player
        input.$current
            .sink { [weak self] frame in self?.update(from: frame) }
            .store(in: &subscriptions)
        Timer.publish(every: 1.0 / 24, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.update(from: self.input.current)
            }
            .store(in: &subscriptions)
    }

    private func update(from captured: AudioFrame) {
        if captured.left.hasSpectrum || captured.right.hasSpectrum {
            if frames.current != captured { frames.current = captured }
            return
        }
        guard player?.track?.playing == true else {
            if frames.current != AudioFrame() { frames.current = AudioFrame() }
            return
        }

        // A muted player may send no samples. Show gentle playback activity
        // until measured frequencies are available again.
        let now = ProcessInfo.processInfo.systemUptime
        var activity = ChannelFrame(level: 0.04)
        for band in 0..<16 {
            let motion = 0.5 + 0.5 * sin(now * 4.4 - Double(band) * 0.63)
            activity.spectrum[band] = Float(0.07 + motion * 0.26)
        }
        frames.current = AudioFrame(left: activity, right: activity, animationTime: now, musicHue: (now * 0.11).truncatingRemainder(dividingBy: 1), mode: .mono)
    }
}

@MainActor
private final class MonitorColors: ObservableObject {
    @Published var selection = UserDefaults.standard.string(forKey: "monitorEqualizerPalette")
        .flatMap(VisualizerPalette.init(rawValue:)) ?? .albumArt {
        didSet { UserDefaults.standard.set(selection.rawValue, forKey: "monitorEqualizerPalette") }
    }
    @Published var hue = UserDefaults.standard.object(forKey: "monitorEqualizerHue") as? Double ?? 0.5 {
        didSet { UserDefaults.standard.set(hue, forKey: "monitorEqualizerHue") }
    }

    func tint(settings: VisualizerSettings, frame: AudioFrame) -> Color {
        if selection == .automatic || (selection == .albumArt && settings.artworkColors == nil),
           let musicHue = frame.musicHue {
            return TrailPalette(hue: musicHue).primary
        }
        return settings.palette(for: selection, hue: hue).primary
    }

}

private struct PlayerSpectrum: View {
    @ObservedObject var frames: AudioFrames
    @ObservedObject var settings: VisualizerSettings
    @ObservedObject var colors: MonitorColors

    private var tint: Color { colors.tint(settings: settings, frame: frames.current) }

    var body: some View {
        let frame = frames.current
        HStack(alignment: .center, spacing: 1) {
            ForEach(0..<8) { index in
                let low = index * 2
                let high = low + 2
                let peak = (low..<high).reduce(Float.zero) { peak, band in
                    max(peak, frame.left.spectrum[band], frame.right.spectrum[band])
                }
                Capsule()
                    .fill(tint.opacity(0.72 + Double(min(1, peak)) * 0.28))
                    .frame(width: 2, height: 3 + CGFloat(peak) * 15)
            }
        }
        .accessibilityLabel("Live audio spectrum")
    }
}

private struct StudioControls: View {
    @ObservedObject var studio: Studio
    @State private var tab = "Visualizer"

    var body: some View {
        VStack(spacing: 0) {
            Picker("Controls", selection: $tab) {
                Text("Music Monitor").tag("Music")
                Text("Visualizer").tag("Visualizer")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.top, 14)
            if tab == "Music" {
                StudioMusicControls(model: studio.island.model, settings: studio.overlay.settings, colors: studio.monitorColors)
            } else {
                NotchBeatControls(audio: studio.audio, overlay: studio.overlay, settings: studio.overlay.settings)
            }
        }
        .frame(width: 400)
    }
}

private struct MonitorColorControls: View {
    @ObservedObject var colors: MonitorColors

    var body: some View {
        Text("Equalizer color").font(.callout.weight(.semibold))
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 8) {
            ForEach(VisualizerPalette.allCases) { palette in
                Button { colors.selection = palette } label: {
                    VStack(spacing: 4) {
                        Circle()
                            .fill(LinearGradient(colors: palette.colors.colors,
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 22, height: 22)
                            .overlay {
                                Circle().strokeBorder(.primary.opacity(colors.selection == palette ? 0.9 : 0.15),
                                                      lineWidth: colors.selection == palette ? 2 : 1)
                            }
                        Text(palette.rawValue).font(.system(size: 9)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                    .background(.primary.opacity(colors.selection == palette ? 0.10 : 0),
                                in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(colors.selection == palette ? .isSelected : [])
            }
        }
        if colors.selection == .spectrum {
            Slider(value: $colors.hue, in: 0...1) { Text("Equalizer hue") }
        }
    }
}

private struct StudioMusicControls: View {
    @ObservedObject var model: MusicModel
    @ObservedObject var settings: VisualizerSettings

    @ObservedObject var colors: MonitorColors

    var body: some View {
        SettingsView(model: model, appName: "Music Monitor", visualizerTheme: settings.basePalette.primary,
                     equalizerColorControls: AnyView(MonitorColorControls(colors: colors)))
    }
}

@main
@MainActor
struct JimboStudioApp: App {
    @StateObject private var studio = Studio()

    var body: some Scene {
        MenuBarExtra {
            StudioControls(studio: studio)
        } label: {
            Image(systemName: "waveform.circle")
                .accessibilityLabel("Jimbo's Notch Buddy")
        }
        .menuBarExtraStyle(.window)
    }
}
