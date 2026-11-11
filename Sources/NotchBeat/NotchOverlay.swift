import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchOverlayController: ObservableObject {
    @Published private(set) var isCrowded = false
    @Published private(set) var fittedSize: CGSize?
    @Published var sizing = TrailSizing() {
        didSet { sizing.saveChanges(from: oldValue) }
    }
    let settings = VisualizerSettings()

    private let audio: AudioMonitor
    private var hasSignal = false
    private var subscriptions = Set<AnyCancellable>()
    private var timer: Timer?
    private var islandSpace: MenuBarSpace?
    private var islandBounds: CGRect?
    private var islandProbeRunning = false
    private var islandProbeRevision = 0
    private var nextIslandProbe: TimeInterval = 0
    private var panels: [TrailSide: NSPanel] = [:]

    init(audio: AudioMonitor) {
        self.audio = audio
        audio.frames.$current.map(\.isActive).removeDuplicates().sink { [weak self] hasSignal in
            self?.hasSignal = hasSignal
            self?.updateActivity()
        }.store(in: &subscriptions)

        settings.$selectedPalette.removeDuplicates()
            .combineLatest(audio.$running.removeDuplicates(), audio.$source.removeDuplicates())
            .receive(on: RunLoop.main)
            .sink { [weak self] _, running, source in
                self?.settings.updateArtwork(listening: running, source: source)
            }.store(in: &subscriptions)

        audio.$lowPower.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self, self.hasSignal else { return }
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
        panel.contentView = NSHostingView(rootView: TrailView(audio: audio, frames: audio.frames, settings: settings, side: side))
        return panel
    }

    private func updateActivity() {
        if hasSignal {
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
        } else {
            timer?.invalidate()
            timer = nil
            resetIslandProbe()
            setCrowded(false)
            hide()
        }
    }

    private func refresh() {
        guard NSMenu.menuBarVisible(),
              let primary = NSScreen.screens.first,
              let screen = NSScreen.screens.first(where: { isBuiltIn($0) && (IslandFootprint.hasPROLEDDisplay || $0.safeAreaInsets.top > 0) })
                ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else {
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

        updateIslandBounds(in: space)
        guard let pair = space.balancedLanes(island: islandBounds, scale: screen.backingScaleFactor,
                                             requestedSize: sizing.requestedSize, gap: sizing.gap) else {
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
        guard space.hasNotch, !islandProbeRunning, now >= nextIslandProbe else { return }
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

private struct TrailView: View {
    @ObservedObject var audio: AudioMonitor
    @ObservedObject var frames: AudioFrames
    @ObservedObject var settings: VisualizerSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let side: TrailSide

    var body: some View {
        let frame = frames.current
        let channel = side == .left ? frame.left : frame.right
        ClassicTrail(channel: channel, time: reduceMotion ? 0 : frame.animationTime,
                     palette: settings.palette(for: frame), side: side, mirrored: frame.mode == .mono,
                     lowPower: audio.lowPower, innerInset: 2)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
