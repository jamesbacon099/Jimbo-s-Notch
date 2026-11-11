import AppKit
import Combine
import SwiftUI

enum MonitorInput: String, CaseIterable, Identifiable {
    case musicApps = "Music apps"
    case system = "All system audio"
    case visualizer = "Visualizer source"

    var id: String { rawValue }
}

@MainActor
final class MusicModel: ObservableObject {
    @Published var track: Track?
    @Published var artwork: NSImage?
    @Published var expanded = false
    @Published var presentedSize: CGSize?
    @Published var preview = false
    @Published var externalAudioActive = false
    @Published var monitorInput = UserDefaults.standard.string(forKey: "monitorInput")
        .flatMap(MonitorInput.init(rawValue:)) ?? .musicApps {
        didSet {
            guard monitorInput != oldValue else { return }
            UserDefaults.standard.set(monitorInput.rawValue, forKey: "monitorInput")
            autoAccent = nil
            externalAudioActive = false
        }
    }
    @Published var progress = 0.0
    @Published private(set) var playerVolume: Double?
    @Published var status = "Choose a player to connect."
    @Published var connected = UserDefaults.standard.bool(forKey: "connected") {
        didSet { UserDefaults.standard.set(connected, forKey: "connected"); restart() }
    }
    @Published var source = UserDefaults.standard.string(forKey: "source") ?? "Auto" {
        didSet { UserDefaults.standard.set(source, forKey: "source"); restart() }
    }
    @Published var width = UserDefaults.standard.object(forKey: "width") as? Double ?? 364 {
        didSet { UserDefaults.standard.set(width, forKey: "width") }
    }
    @Published var shoulder = UserDefaults.standard.object(forKey: "shoulder") as? Double ?? 46 {
        didSet { UserDefaults.standard.set(shoulder, forKey: "shoulder") }
    }
    @Published var radius = UserDefaults.standard.object(forKey: "radius") as? Double ?? 19 {
        didSet { UserDefaults.standard.set(radius, forKey: "radius") }
    }
    @Published var tint = UserDefaults.standard.string(forKey: "tint") ?? "Violet" {
        didSet { UserDefaults.standard.set(tint, forKey: "tint") }
    }
    @Published var onHover = UserDefaults.standard.bool(forKey: "onHover") {
        didSet { UserDefaults.standard.set(onHover, forKey: "onHover") }
    }
    @Published var studioOnHover = UserDefaults.standard.bool(forKey: "studioOnHover") {
        didSet { UserDefaults.standard.set(studioOnHover, forKey: "studioOnHover") }
    }
    @Published var showPaused = UserDefaults.standard.object(forKey: "showPaused") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showPaused, forKey: "showPaused") }
    }
    @Published var glassTintSource = UserDefaults.standard.string(forKey: "glassTintSource") ?? "Album cover" {
        didSet { UserDefaults.standard.set(glassTintSource, forKey: "glassTintSource") }
    }
    @Published var visualizerTint: Color?
    @Published var autoAccent: Color?
    @Published var accentHue = UserDefaults.standard.object(forKey: "accentHue") as? Double ?? 0.75 {
        didSet { UserDefaults.standard.set(accentHue, forKey: "accentHue") }
    }
    @Published private var coverTint: Color?
    var artworkTintProvider: ((Data?) -> Color?)?

    private func updateArtworkTints(_ bytes: Data?) {
        coverTint = artworkTintProvider?(bytes)
    }

    var glassTint: Color {
        guard usesMusicMetadata else { return accent }
        switch glassTintSource {
        case "Album cover": return coverTint ?? accent
        case "Visualizer": return visualizerTint ?? accent
        default: return accent
        }
    }

    @Published var liquidGlassPlayer = UserDefaults.standard.bool(forKey: "liquidGlassPlayer") {
        didSet { UserDefaults.standard.set(liquidGlassPlayer, forKey: "liquidGlassPlayer") }
    }
    @Published var bottomGap = UserDefaults.standard.object(forKey: "bottomGap") as? Double ?? 0 {
        didSet { UserDefaults.standard.set(bottomGap, forKey: "bottomGap") }
    }

    let playback = Playback()
    private var volumeUpdate: Task<Void, Never>?
    private var poll: Task<Void, Never>?
    private var artworkBytes: Data?
    private var lastTrackRead: TimeInterval?

    var accent: Color {
        switch tint {
        case "Auto": return autoAccent ?? Color(red: 0.76, green: 0.63, blue: 1)
        case "Custom": return Color(hue: min(1, max(0, accentHue)), saturation: 0.70, brightness: 1)
        case "Album cover": return (usesMusicMetadata ? coverTint : autoAccent) ?? Color(red: 0.76, green: 0.63, blue: 1)
        case "Mint": return Color(red: 0.42, green: 1, blue: 0.75)
        case "Coral": return Color(red: 1, green: 0.48, blue: 0.40)
        case "Ice": return Color(red: 0.55, green: 0.82, blue: 1)
        case "White": return .white
        default: return Color(red: 0.76, green: 0.63, blue: 1)
        }
    }

    var usesMusicMetadata: Bool { monitorInput == .musicApps }
    var displayTrack: Track? { usesMusicMetadata ? track : nil }
    var displayArtwork: NSImage? { usesMusicMetadata ? artwork : nil }
    var visible: Bool {
        if !usesMusicMetadata { return preview || externalAudioActive || expanded }
        return preview || (displayTrack.map { $0.playing || showPaused || expanded } ?? false)
    }
    var title: String { displayTrack?.title ?? (usesMusicMetadata ? "Midnight Drive" : monitorInput.rawValue) }
    var artist: String { displayTrack?.artist ?? (usesMusicMetadata ? "Player preview" : "Live audio spectrum") }
    var duration: Double { track?.duration ?? 218 }

    init() { restart() }

    func restart() {
        poll?.cancel()
        volumeUpdate?.cancel()
        volumeUpdate = nil
        playerVolume = nil
        track = nil
        lastTrackRead = nil
        artwork = nil
        artworkBytes = nil
        updateArtworkTints(nil)
        guard connected else { status = "Choose a player to connect."; return }
        poll = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: .milliseconds(1200))
            }
        }
    }

    private func refresh() async {
        let players = Player.allCases.filter { $0.running && (source == "Auto" || $0.rawValue == source) }
        var best: (Track, Data?)?
        for player in players {
            guard !Task.isCancelled else { return }
            if let candidate = await playback.read(player) {
                if best == nil || candidate.0.playing { best = candidate }
                if candidate.0.playing { break }
            }
        }
        guard !Task.isCancelled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if best != nil {
            lastTrackRead = now
        } else if track != nil,
                  expanded || (lastTrackRead.map { now - $0 < 3 } ?? false) {
            // Players can briefly report no current track during a skip.
            return
        }
        if best?.0.player != track?.player {
            volumeUpdate?.cancel()
            volumeUpdate = nil
        }
        track = best?.0
        if volumeUpdate == nil { playerVolume = track?.volume }
        if artworkBytes != best?.1 {
            artworkBytes = best?.1
            artwork = artworkBytes.flatMap(NSImage.init(data:))
            updateArtworkTints(artworkBytes)
        }
        status = track.map { "Connected to \($0.player.name)" }
            ?? (players.isEmpty ? "Open Apple Music or Spotify." : "Play a track. Allow Automation access if prompted.")
    }

    func updateProgress() {
        if let track { progress = track.elapsed }
        else if preview { progress = 71 }
    }

    func command(_ command: String) {
        guard let player = track?.player, player.running else { return }
        Task {
            await playback.command(command, player: player)
            await refresh()
        }
    }

    func setPlayerVolume(_ requested: Double) {
        guard requested.isFinite, let player = track?.player, player.running else { return }
        let volume = Int(min(100, max(0, requested)).rounded())
        playerVolume = Double(volume)
        volumeUpdate?.cancel()
        volumeUpdate = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(110))
            guard let self, !Task.isCancelled, track?.player == player else { return }
            await playback.command("set sound volume to \(volume)", player: player)
            guard !Task.isCancelled else { return }
            volumeUpdate = nil
            await refresh()
        }
    }

    func seek(_ position: Double) {
        guard position.isFinite else { return }
        command("set player position to \(Int(max(0, min(duration, position))))")
    }
}

@MainActor
final class MusicIsland: NSObject {
    let model = MusicModel()
    private var panel: NSPanel?
    private var timer: Timer?
    private var expandedFrame = false
    private var pointerWasInside = false
    private var resizeTimer: Timer?
    private var resizeTarget: CGRect?
    private var presentedFrame: CGRect?
    private var expansionSubscription: AnyCancellable?
    var sharedScreen: (() -> NSScreen?)?
    var onFrameChange: ((CGRect?) -> Void)?
    var spectrumView: (() -> AnyView)?

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        expansionSubscription = model.$expanded.dropFirst().removeDuplicates()
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.update() }
        update()
    }

    private func update() {
        model.updateProgress()
        if let panel, panel.isVisible {
            // Include the topmost screen pixel and tolerate subpixel frame rounding.
            let inside = (presentedFrame ?? panel.frame).insetBy(dx: -1, dy: -2).contains(NSEvent.mouseLocation)
            let hoverEnabled = onFrameChange == nil ? model.onHover : model.studioOnHover
            if inside && !pointerWasInside && hoverEnabled { model.expanded = true }
            if !inside && model.expanded { model.expanded = false }
            pointerWasInside = inside
        }
        guard model.visible,
              let screen = sharedScreen?() ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else {
            resizeTimer?.invalidate()
            resizeTimer = nil
            resizeTarget = nil
            presentedFrame = nil
            panel?.orderOut(nil)
            pointerWasInside = false
            onFrameChange?(nil)
            if model.expanded { model.expanded = false }
            return
        }
        let top = screen.safeAreaInsets.top
        let center = screen.frame.midX
        let notchWidth = (screen.auxiliaryTopRightArea?.minX ?? center) -
                         (screen.auxiliaryTopLeftArea?.maxX ?? center)
        let cutout = max(148, notchWidth)
        let compactHeight = max(29, top)
        let compactWidth = cutout + model.shoulder * 2
        let width = model.expanded ? max(compactWidth, model.width) : compactWidth
        let height = model.expanded ? compactHeight + 190 : compactHeight
        let frame = NSRect(x: center - width / 2, y: screen.frame.maxY - height - (top == 0 && onFrameChange == nil ? model.bottomGap : 0),
                           width: width, height: height)
        let window = panel ?? makePanel(compactHeight: compactHeight, cutoutWidth: cutout)
        if onFrameChange != nil {
            // Keep one backing surface during expansion so the compositor never
            // exposes the desktop while it reallocates a larger window.
            let canvasWidth = max(compactWidth, model.width)
            let canvasHeight = compactHeight + 190
            let canvas = CGRect(x: center - canvasWidth / 2, y: frame.maxY - canvasHeight,
                                width: canvasWidth, height: canvasHeight)
            if window.frame != canvas { window.setFrame(canvas, display: true) }
            if !window.isVisible {
                present(frame)
                window.orderFrontRegardless()
            } else {
                resizeTogether(window, to: frame)
            }
        } else if !window.isVisible {
            window.setFrame(frame, display: true)
            window.orderFrontRegardless()
        } else if window.frame != frame {
            NSAnimationContext.runAnimationGroup { animation in
                animation.duration = expandedFrame == model.expanded ? 0 : 0.18
                window.animator().setFrame(frame, display: true)
            }
        }
        expandedFrame = model.expanded
    }

    private func present(_ frame: CGRect) {
        presentedFrame = frame
        if model.presentedSize != frame.size { model.presentedSize = frame.size }
        onFrameChange?(frame)
    }

    private func resizeTogether(_ window: NSPanel, to target: CGRect) {
        if resizeTarget == target { return }
        resizeTimer?.invalidate()
        resizeTimer = nil
        resizeTarget = target
        let start = presentedFrame ?? target
        guard start != target else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            present(target)
            return
        }
        let started = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self, weak window] timer in
            MainActor.assumeIsolated {
                guard let self, let window else { timer.invalidate(); return }
                let progress = min(1, (ProcessInfo.processInfo.systemUptime - started) / 0.34)
                // A critically damped curve settles without overshooting the screen edge.
                let t = progress * 7
                let ease = (1 - (1 + t) * exp(-t)) / (1 - 8 * exp(-7))
                func blend(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * ease }
                let scale = window.screen?.backingScaleFactor ?? 1
                let width = (blend(start.width, target.width) * scale).rounded() / scale
                let height = (blend(start.height, target.height) * scale).rounded() / scale
                let center = blend(start.midX, target.midX)
                let frame = CGRect(x: center - width / 2, y: target.maxY - height,
                                   width: width, height: height)
                self.present(frame)
                if progress >= 1 {
                    timer.invalidate()
                    self.resizeTimer = nil
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        resizeTimer = timer
    }

    private func makePanel(compactHeight: CGFloat, cutoutWidth: CGFloat) -> NSPanel {
        let window = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        window.title = "Jimbo Music Island"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary,
                                     .stationary, .ignoresCycle]
        let hostingView = NSHostingView(rootView: IslandView(model: model, compactHeight: compactHeight,
                                                            cutoutWidth: cutoutWidth, spectrumView: spectrumView))
        hostingView.sizingOptions = []
        window.contentView = hostingView
        panel = window
        return window
    }
}

private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

#if !JIMBO_STUDIO
@main
@MainActor
struct JimboMusicApp: App {
    private let island = MusicIsland()

    init() {
        DispatchQueue.main.async { [island] in island.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            SettingsView(model: island.model)
        } label: {
            Image(systemName: "music.note")
                .accessibilityLabel("Jimbo Music")
        }
        .menuBarExtraStyle(.window)
    }
}

#endif
