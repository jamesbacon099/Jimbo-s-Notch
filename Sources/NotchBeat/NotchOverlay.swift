import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchOverlayController: ObservableObject {
    @Published private(set) var isCrowded = false
    @Published private(set) var gapRange = -100.0...100.0
    @Published private(set) var fittedSize: CGSize?
    let settings = VisualizerSettings()
    let musicSpectrumFrames: AudioFrames?

    private let audio: AudioMonitor
    private let usesIntegratedPlayer: Bool
    private var integratedFrame: CGRect?
    private var subscriptions = Set<AnyCancellable>()
    private var timer: Timer?
    private var islandSpace: MenuBarSpace?
    private var islandBounds: CGRect?
    private var islandProbeRunning = false
    private var islandProbeRevision = 0
    private var nextIslandProbe: TimeInterval = 0
    private var panels: [TrailSide: NSPanel] = [:]

    init(audio: AudioMonitor, usesIntegratedPlayer: Bool = false, musicSpectrumFrames: AudioFrames? = nil) {
        self.audio = audio
        self.musicSpectrumFrames = musicSpectrumFrames
        self.usesIntegratedPlayer = usesIntegratedPlayer
        // Defer panel creation until the app's initial SwiftUI layout is complete.
        DispatchQueue.main.async { [weak self] in self?.updateActivity() }

        if !usesIntegratedPlayer {
            settings.$selectedPalette.removeDuplicates()
                .combineLatest(audio.$source.removeDuplicates())
                .receive(on: RunLoop.main)
                .sink { [weak self] _, source in
                    self?.settings.updateArtwork(source: source)
                }.store(in: &subscriptions)
        }

        audio.$lowPower.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }
            self.timer?.invalidate()
            self.timer = nil
            self.updateActivity()
        }.store(in: &subscriptions)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .merge(with: NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification))
            .sink { [weak self] _ in
                self?.resetIslandProbe()
                self?.hide()
            }
            .store(in: &subscriptions)
    }

    private func makePanel(_ side: TrailSide) -> NSPanel {
        let panel = TrailPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: TrailView(audio: audio, frames: audio.frames, equalizerFrames: musicSpectrumFrames ?? audio.frames, settings: settings, side: side))
        return panel
    }

    private func updateActivity() {
        if timer == nil {
            let interval = audio.lowPower ? 0.33 : 0.12
            let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            timer.tolerance = interval * 0.10
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        refresh()
    }

    var preferredScreen: NSScreen? {
        NSScreen.screens.first(where: { isBuiltIn($0) && (IslandFootprint.hasPROLEDDisplay || $0.safeAreaInsets.top > 0) })
            ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    func positionAroundPlayer(_ frame: CGRect?) {
        guard usesIntegratedPlayer, integratedFrame != frame else { return }
        integratedFrame = frame
        refresh()
    }

    private func refresh() {
        guard NSMenu.menuBarVisible(),
              let primary = NSScreen.screens.first,
              let screen = preferredScreen else {
            setCrowded(false)
            hide()
            return
        }
        let hasSystemIsland = IslandFootprint.hasPROLEDDisplay && isBuiltIn(screen)
        let inset = screen.safeAreaInsets.top
        let barHeight = hasSystemIsland || inset <= 0 ? max(inset, NSStatusBar.system.thickness) : inset
        let space = MenuBarSpace.forDisplay(
            frame: screen.frame,
            auxiliaryLeft: screen.auxiliaryTopLeftArea,
            auxiliaryRight: screen.auxiliaryTopRightArea,
            barHeight: barHeight,
            originY: primary.frame.maxY,
            systemIsland: hasSystemIsland
        )

        if !usesIntegratedPlayer { updateIslandBounds(in: space) }
        let footprint = usesIntegratedPlayer ? integratedFrame : islandBounds
        let availableGap = space.gapRange(island: footprint)
        if gapRange != availableGap { gapRange = availableGap }
        let gap = min(availableGap.upperBound, max(availableGap.lowerBound, settings.sizing.gap))
        guard let pair = space.balancedLanes(island: footprint, scale: screen.backingScaleFactor,
                                             requestedSize: settings.sizing.requestedSize, gap: gap,
                                             centeredOnAnchor: settings.selectedStyle == .fire) else {
            setCrowded(true)
            hide()
            return
        }
        setCrowded(false)
        if fittedSize != pair.left.size { fittedSize = pair.left.size }
        place(.left, frame: pair.left)
        place(.right, frame: pair.right)
    }

    private func updateIslandBounds(in space: MenuBarSpace) {
        if islandSpace != space {
            resetIslandProbe()
            islandSpace = space
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard !islandProbeRunning, now >= nextIslandProbe else { return }
        nextIslandProbe = now + (audio.lowPower ? 0.65 : 0.24)
        islandProbeRunning = true
        let revision = islandProbeRevision
        Task { [weak self] in
            let bounds = await Task.detached(priority: .utility) {
                IslandFootprint.current(in: space)
            }.value
            guard let self else { return }
            self.islandProbeRunning = false
            guard self.islandProbeRevision == revision else { return }
            self.islandBounds = bounds
        }
    }

    private func resetIslandProbe() {
        islandProbeRevision += 1
        islandSpace = nil
        islandBounds = nil
        nextIslandProbe = 0
    }

    private func isBuiltIn(_ screen: NSScreen) -> Bool {
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
        return CGDisplayIsBuiltin(id.uint32Value) != 0
    }

    private func setCrowded(_ crowded: Bool) {
        if isCrowded != crowded { isCrowded = crowded }
    }

    private func place(_ side: TrailSide, frame: CGRect) {
        let panel = panels[side] ?? makePanel(side)
        panels[side] = panel
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func hide() {
        if fittedSize != nil { fittedSize = nil }
        for panel in panels.values where panel.isVisible {
            panel.orderOut(nil)
        }
    }

}

private final class TrailPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct TrailClock {
    private(set) var time = 3.4
    private(set) var speed = 0.045
    private var lastUpdate: TimeInterval?

    mutating func tick(at now: TimeInterval, playing: Bool) {
        defer { lastUpdate = now }
        guard let lastUpdate else { return }
        let elapsed = min(0.2, max(0, now - lastUpdate))
        let target = playing ? 1.0 : 0.045
        speed += (target - speed) * (1 - exp(-elapsed / (playing ? 0.25 : 0.65)))
        time += elapsed * speed
    }
}

private struct TrailView: View {
    @ObservedObject var audio: AudioMonitor
    @ObservedObject var frames: AudioFrames
    @ObservedObject var equalizerFrames: AudioFrames
    @ObservedObject var settings: VisualizerSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let side: TrailSide
    @State private var heldFrame: AudioFrame?
    @State private var clock = TrailClock()
    @State private var idleTime = ProcessInfo.processInfo.systemUptime

    var body: some View {
        let musicOnly = settings.selectedStyle == .equalizer && equalizerFrames !== frames
        let current = musicOnly ? equalizerFrames.current : frames.current
        let isDancer = settings.selectedStyle == .dancers
        let currentChannel = side == .left ? current.left : current.right
        let idleDancers = isDancer && !current.isActive
        let hasSignal = settings.selectedStyle == .equalizer ? currentChannel.hasSpectrum : currentChannel.isActive
        let idleEffect = !isDancer && !hasSignal
        let idleFrame = musicOnly ? Self.quietEqualizerFrame : heldFrame ?? Self.stillFrame
        let frame = idleEffect ? idleFrame : current
        let channel = side == .left ? frame.left : frame.right
        let time = isDancer ? (idleDancers ? max(frame.animationTime, idleTime) : frame.animationTime) : clock.time
        trail(frame: frame, channel: channel, time: time, idleEffect: idleEffect)
        .onChange(of: current, initial: true) { _, frame in
            guard !isDancer else { return }
            let channel = side == .left ? frame.left : frame.right
            if settings.selectedStyle == .equalizer ? channel.hasSpectrum : channel.isActive {
                if !musicOnly { heldFrame = frame }
                clock.tick(at: ProcessInfo.processInfo.systemUptime, playing: true)
            }
        }
        .task(id: reduceMotion ? 0 : idleDancers ? 1 : idleEffect ? 2 : 0) {
            guard (idleDancers || idleEffect), !reduceMotion else { return }
            while !Task.isCancelled {
                let now = ProcessInfo.processInfo.systemUptime
                if idleDancers {
                    idleTime = now
                } else {
                    clock.tick(at: now, playing: false)
                }
                try? await Task.sleep(for: .milliseconds(audio.lowPower ? 66 : 33))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static let quietEqualizerFrame: AudioFrame = {
        let channel = ChannelFrame(level: 0.003)
        return AudioFrame(left: channel, right: channel)
    }()

    // Before the first audio frame, render a quiet, fixed sample of the selected style.
    private static let stillFrame: AudioFrame = {
        var channel = ChannelFrame(level: 0.08, bass: 0.04)
        for index in 0..<16 {
            channel.bands[index] = Float(0.04 + 0.12 * abs(sin(Double(index) * 0.47)))
            channel.spectrum[index] = channel.bands[index]
        }
        return AudioFrame(left: channel, right: channel, animationTime: 3.4)
    }()

    private func trail(frame: AudioFrame, channel: ChannelFrame, time: TimeInterval, idleEffect: Bool) -> some View {
        var channel = channel
        if frame.animationTime > 0 && settings.selectedStyle == .dancers {
            let age = min(0.05, max(0, time - frame.animationTime))
            channel.danceBeat += age / channel.beatDuration
        }
        let fire = settings.selectedStyle == .fire
        let fromNotch = settings.flowFromNotch || (fire && idleEffect)
        if !idleEffect && settings.selectedStyle != .dancers, let hit = channel.lastHit {
            channel.lastHit = time - max(0, frame.animationTime - hit)
        } else if idleEffect {
            channel.lastHit = nil
        }
        if settings.selectedStyle == .equalizer && equalizerFrames === frames && !reduceMotion {
            let idleAmount = max(0, 1 - clock.speed)
            for index in 0..<16 {
                let ripple = (0.5 + 0.5 * sin(time * 4 + Double(index) * 0.66)) * 0.07
                channel.spectrum[index] = min(1, channel.spectrum[index] + Float(ripple * idleAmount))
            }
        }
        return VisualizerTrail(style: settings.selectedStyle, flowFromNotch: fromNotch,
                               dancersPerSide: settings.dancersPerSide, relaxedDance: settings.relaxedDance,
                               channel: channel, time: reduceMotion ? 0 : time,
                               palette: settings.palette(for: frame), side: side, mirrored: frame.mode == .mono,
                               lowPower: audio.lowPower, innerInset: fire && fromNotch ? 0 : 2, glassFade: settings.liquidGlassColors, splashDensity: settings.splashDensity, dancerSparks: settings.dancerSparks)
    }
}
