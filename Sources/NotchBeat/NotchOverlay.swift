import AppKit
import ApplicationServices
import Combine
import SwiftUI

@MainActor
final class NotchOverlayController: ObservableObject {
    enum Fit: Equatable {
        case idle, compact, adaptive, crowded
    }

    @Published private(set) var layoutAccess = AXIsProcessTrusted()
    @Published private(set) var fit = Fit.idle
    @Published private(set) var layoutSetupStarted = false
    @Published private(set) var fittedSize: CGSize?
    @Published var sizing = TrailSizing() {
        didSet { sizing.saveChanges(from: oldValue) }
    }
    let settings = VisualizerSettings()

    private let audio: AudioMonitor
    private var hasSignal = false
    private var subscriptions = Set<AnyCancellable>()
    private var timer: Timer?
    private var occupied = MenuBarOccupancy()
    private var reading = false
    private var revision = 0
    private var nextRead: TimeInterval = 0
    private var lastRead: TimeInterval = 0
    private let reader = DispatchQueue(label: "notchbeat.menu-layout", qos: .utility)
    private var panels: [TrailSide: NSPanel] = [:]

    init(audio: AudioMonitor) {
        self.audio = audio
        audio.$frame.map(\.isActive).removeDuplicates().sink { [weak self] hasSignal in
            self?.hasSignal = hasSignal
            self?.updateActivity()
        }.store(in: &subscriptions)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .merge(with: NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification))
            .merge(with: NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification))
            .sink { [weak self] _ in self?.invalidateLayout() }
            .store(in: &subscriptions)
    }

    func refreshLayoutAccess() {
        let trusted = AXIsProcessTrusted()
        if layoutAccess != trusted {
            layoutAccess = trusted
            invalidateLayout()
        }
    }

    func requestLayoutAccess() {
        layoutSetupStarted = true
        let prompt = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        layoutAccess = AXIsProcessTrustedWithOptions(prompt)
        invalidateLayout()
    }

    func openLayoutSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
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
        panel.contentView = NSHostingView(rootView: TrailView(audio: audio, settings: settings, side: side))
        return panel
    }

    private func updateActivity() {
        if hasSignal {
            if timer == nil {
                let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refresh() }
                }
                timer.tolerance = 0.012
                RunLoop.main.add(timer, forMode: .common)
                self.timer = timer
            }
            refresh()
        } else {
            timer?.invalidate()
            timer = nil
            setFit(.idle)
            invalidateLayout()
        }
    }

    private func invalidateLayout() {
        revision += 1
        nextRead = 0
        occupied = MenuBarOccupancy()
        hide()
    }

    private func refresh() {
        refreshLayoutAccess()
        guard NSMenu.menuBarVisible(),
              let primary = NSScreen.screens.first,
              let screen = NSScreen.screens.first(where: { IslandFootprint.hasPROLEDDisplay && isBuiltIn($0) })
                ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else {
            setFit(.idle)
            hide()
            return
        }
        let hasSystemIsland = IslandFootprint.hasPROLEDDisplay && isBuiltIn(screen)
        let top = screen.frame.maxY
        let barHeight = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)
        let bottom = top - barHeight
        let leftEnd: CGFloat
        let rightStart: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
           left.maxX >= screen.frame.minX, right.minX <= screen.frame.maxX, right.minX > left.maxX {
            leftEnd = left.maxX
            rightStart = right.minX
        } else {
            leftEnd = screen.frame.midX
            rightStart = screen.frame.midX
        }
        let center = (leftEnd + rightStart) / 2
        let reservedHalfWidth = hasSystemIsland ? IslandFootprint.compactSystemWidth / 2 : 0
        let protectedLeft = min(leftEnd, center - reservedHalfWidth)
        let protectedRight = max(rightStart, center + reservedHalfWidth)
        let space = MenuBarSpace(
            leftArea: CGRect(x: screen.frame.minX, y: bottom, width: protectedLeft - screen.frame.minX, height: barHeight),
            rightArea: CGRect(x: protectedRight, y: bottom, width: screen.frame.maxX - protectedRight, height: barHeight),
            axOriginY: primary.frame.maxY,
            hasSystemIsland: hasSystemIsland
        )

        let workspace = NSWorkspace.shared
        let now = ProcessInfo.processInfo.systemUptime
        if layoutAccess, !reading, now >= nextRead, let front = workspace.frontmostApplication {
            reading = true
            nextRead = now + 1.2
            let systemApps = ["com.apple.controlcenter", "com.apple.systemuiserver", "com.apple.MenuBarAgent"]
            let pids = workspace.runningApplications.filter {
                !$0.isTerminated && ($0.activationPolicy != .prohibited || systemApps.contains($0.bundleIdentifier ?? ""))
            }.map(\.processIdentifier)
            let revision = revision
            let frontPID = front.processIdentifier
            reader.async { [weak self] in
                let frames = MenuBarReader.occupiedFrames(frontPID: frontPID, statusPIDs: pids, space: space)
                Task { @MainActor in
                    guard let self else { return }
                    self.reading = false
                    guard self.revision == revision else { return }
                    self.occupied = frames
                    self.lastRead = ProcessInfo.processInfo.systemUptime
                }
            }
        }

        let recent = now - lastRead < 2.4 ? occupied : MenuBarOccupancy()
        let window = IslandFootprint.current(in: space)
        let island = window.map { recent.island?.union($0) ?? $0 } ?? recent.island
        guard let pair = space.balancedLanes(occupied: recent, island: island, scale: screen.backingScaleFactor,
                                             requestedSize: sizing.requestedSize) else {
            setFit(.crowded)
            hide()
            return
        }
        setFit(recent.left != nil && recent.right != nil ? .adaptive : .compact)
        if fittedSize != pair.left.size { fittedSize = pair.left.size }
        place(.left, frame: pair.left)
        place(.right, frame: pair.right)
    }

    private func isBuiltIn(_ screen: NSScreen) -> Bool {
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
        return CGDisplayIsBuiltin(id.uint32Value) != 0
    }

    private func setFit(_ next: Fit) {
        if fit != next { fit = next }
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
    @ObservedObject var settings: VisualizerSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let side: TrailSide

    var body: some View {
        let channel = side == .left ? audio.frame.left : audio.frame.right
        ClassicTrail(channel: channel, time: reduceMotion ? 0 : audio.frame.animationTime,
                     palette: settings.palette(for: audio.frame), side: side, mirrored: audio.frame.mode == .mono)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
