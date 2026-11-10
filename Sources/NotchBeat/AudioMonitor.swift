import AppKit
import AVFoundation
import CoreAudio
import Foundation

@MainActor
final class AudioMonitor: ObservableObject {
    @Published private(set) var frame = AudioFrame()
    @Published private(set) var status = "Stopped"
    @Published private(set) var running = false
    @Published private(set) var source = AudioSource.system
    @Published var sensitivity: Double = 2.4
    @Published private(set) var channelMode =
        UserDefaults.standard.string(forKey: "channelMode").flatMap(ChannelMode.init(rawValue:)) ?? .stereo

    func selectMode(_ mode: ChannelMode) {
        guard channelMode != mode else { return }
        channelMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "channelMode")
        analysis?.selectMode(mode)
    }

    enum AudioSource: Hashable {
        case system
        case application(AudioApplication)
        case microphone

        var audioLabel: String {
            switch self {
            case .system: return "system audio"
            case .application(let app): return "audio from \(app.name)"
            case .microphone: return "microphone audio"
            }
        }
    }

    private var systemTap: SystemAudioTap?
    private var microphone: AVAudioEngine?
    private var analysis: AudioAnalysis?
    private var timer: Timer?
    private var animated = false
    private var lastFrameTime: TimeInterval?
    private var colorMotion = MusicColorMotion()
    private var appTimer: Timer?
    private var appProcessIDs: [AudioObjectID] = []
    private var startTask: Task<Void, Never>?
    private var outputListener: AudioObjectPropertyListenerBlock?
    private var lastAudible: TimeInterval?

    func select(_ newSource: AudioSource) {
        guard source != newSource else { return }
        let restart = running
        source = newSource
        if restart { start() }
    }

    func start() {
        stop()
        running = true
        status = "Connecting to \(source.audioLabel)…"
        startTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            do {
                switch source {
                case .system:
                    try startTap()
                    watchOutput()
                case .application(let app):
                    watchOutput()
                    startAppTimer(for: app)
                    return
                case .microphone:
                    let allowed = await AVCaptureDevice.requestAccess(for: .audio)
                    guard !Task.isCancelled else { return }
                    guard allowed else { throw CaptureError(message: "Microphone access was denied") }
                    try startMicrophone()
                }
                status = "Waiting for \(source.audioLabel)…"
                startTimer()
            } catch {
                stop()
                status = error.localizedDescription
            }
        }
    }

    private func startTap(processIDs: [AudioObjectID]? = nil) throws {
        let tap = SystemAudioTap()
        let analyzer = try tap.start(processIDs: processIDs)
        analyzer.selectMode(channelMode)
        analysis = analyzer
        systemTap = tap
    }

    private func startAppTimer(for app: AudioApplication) {
        refreshAppTap(for: app)
        let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAppTap(for: app) }
        }
        RunLoop.main.add(timer, forMode: .common)
        appTimer = timer
    }

    private func refreshAppTap(for app: AudioApplication) {
        let processes: (isRunning: Bool, ids: [AudioObjectID])
        do {
            processes = try app.audioProcesses()
        } catch {
            resetTap()
            appProcessIDs = []
            if status != error.localizedDescription { status = error.localizedDescription }
            return
        }

        if processes.ids.isEmpty {
            if !appProcessIDs.isEmpty {
                resetTap()
                appProcessIDs = []
            }
            let waiting = processes.isRunning ? "Play audio in \(app.name) to start" : "Open \(app.name) to listen"
            if status != waiting { status = waiting }
        } else if processes.ids != appProcessIDs {
            resetTap()
            appProcessIDs = processes.ids
            do {
                try startTap(processIDs: processes.ids)
                startTimer()
                status = "Waiting for audio from \(app.name)…"
            } catch {
                status = error.localizedDescription
            }
        }
    }

    private func resetTap() {
        timer?.invalidate()
        timer = nil
        animated = false
        lastFrameTime = nil
        colorMotion = MusicColorMotion()
        systemTap?.stop()
        systemTap = nil
        analysis = nil
        lastAudible = nil
        if frame != AudioFrame() { frame = AudioFrame() }
    }

    private func startMicrophone() throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0, format.commonFormat == .pcmFormatFloat32 else {
            throw CaptureError(message: "No compatible microphone input")
        }
        let analyzer = AudioAnalysis(sampleRate: format.sampleRate)
        analyzer.selectMode(channelMode)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            analyzer.append(buffer.audioBufferList)
        }
        microphone = engine
        try engine.start()
        analysis = analyzer
    }

    func stop() {
        startTask?.cancel()
        startTask = nil
        appTimer?.invalidate()
        appTimer = nil
        appProcessIDs = []
        if let outputListener {
            var address = Self.outputAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, outputListener)
            self.outputListener = nil
        }
        resetTap()
        if let microphone {
            microphone.stop()
            microphone.inputNode.removeTap(onBus: 0)
            self.microphone = nil
        }
        running = false
        status = "Stopped"
    }

    private static var outputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func watchOutput() {
        var address = Self.outputAddress
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.running, self.source != .microphone else { return }
                self.start()
            }
        }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener) == noErr {
            outputListener = listener
        }
    }

    private func startTimer(animated: Bool = false) {
        timer?.invalidate()
        self.animated = animated
        let interval = 1.0 / (animated ? 30 : 15)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateFrame() }
        }
        timer.tolerance = animated ? 0.003 : 0.008
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func updateFrame() {
        guard let analysis else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = min(now - (lastFrameTime ?? now - 1.0 / 30), 0.16)
        lastFrameTime = now
        let decay = pow(0.83, Float(elapsed * 60))
        let input: AudioFrame
        if let latest = analysis.read(), latest.frame.mode == channelMode, now - latest.timestamp < 0.25 {
            input = latest.frame
            if input.level > 0.001 { lastAudible = now }
        } else {
            input = AudioFrame(mode: channelMode)
        }

        func smooth(_ previous: Float, _ sample: Float) -> Float {
            let gain = max(0, sample - 0.0003) * Float(sensitivity) * 1.4
            let target = 1 - exp(-pow(gain, 0.68))
            if target >= previous { return target }
            let released = previous * decay + target * (1 - decay)
            return released < 0.002 ? 0 : released
        }
        func smoothChannel(_ previous: ChannelFrame, _ sample: ChannelFrame) -> ChannelFrame {
            var next = ChannelFrame()
            next.level = smooth(previous.level, sample.level)
            next.bass = smooth(previous.bass, sample.bass)
            next.impact = smooth(previous.impact, sample.impact * 0.70)
            next.lastHit = sample.lastHit
            next.waveform = next.isActive ? sample.waveform : Waveform()
            for band in 0..<16 { next.bands[band] = smooth(previous.bands[band], sample.bands[band]) }
            return next
        }

        let previous = frame.mode == input.mode ? frame : AudioFrame(mode: input.mode)
        let left = smoothChannel(previous.left, input.left)
        let right = input.mode == .mono ? left : smoothChannel(previous.right, input.right)
        var next = AudioFrame(left: left, right: right, mode: input.mode)
        next.animationTime = next.isActive ? now : 0
        next.musicHue = colorMotion.update(with: next, elapsed: elapsed)
        if frame != next { frame = next }
        if next.isActive != animated { startTimer(animated: next.isActive) }

        let label = source.audioLabel
        let nextStatus = now - (lastAudible ?? -.infinity) < 1.2 ? "Receiving \(label)" : "Waiting for \(label)…"
        if status != nextStatus { status = nextStatus }
    }
}
