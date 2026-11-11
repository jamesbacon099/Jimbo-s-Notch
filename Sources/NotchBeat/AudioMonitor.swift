import AppKit
import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

@MainActor
final class AudioFrames: ObservableObject {
    @Published var current = AudioFrame()
}

@MainActor
final class AudioMonitor: ObservableObject {
    let frames = AudioFrames()
    private let ignoresOutputVolume: Bool
    private let allowsFrequencyFocus: Bool

    init(ignoresOutputVolume: Bool = false, allowsFrequencyFocus: Bool = true) {
        self.ignoresOutputVolume = ignoresOutputVolume
        self.allowsFrequencyFocus = allowsFrequencyFocus
    }
    @Published private(set) var status = "Stopped"
    @Published private(set) var running = false
    @Published private(set) var source = AudioSource.system
    @Published var sensitivity: Double = 2.4
    @Published var frequencyFocus = UserDefaults.standard.string(forKey: "frequencyFocus")
        .flatMap(FrequencyFocus.init(rawValue:)) ?? .fullMix {
        didSet { UserDefaults.standard.set(frequencyFocus.rawValue, forKey: "frequencyFocus") }
    }
    enum PlaybackVolume: String, CaseIterable {
        case followOutput = "Follow Mac volume"
        case ignoreOutput = "Even when muted"
    }

    @Published var playbackVolume = UserDefaults.standard.string(forKey: "playbackVolume")
        .flatMap(PlaybackVolume.init(rawValue:)) ?? .followOutput {
        didSet { UserDefaults.standard.set(playbackVolume.rawValue, forKey: "playbackVolume") }
    }

    @Published var lowPower = UserDefaults.standard.bool(forKey: "lowPower") {
        didSet {
            guard lowPower != oldValue else { return }
            UserDefaults.standard.set(lowPower, forKey: "lowPower")
            analysis?.setLowPower(lowPower)
            if timer != nil { startTimer(animated: animated) }
        }
    }
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
    private var danceBeat = 0.0
    private var danceEnergy = 0.0
    private var kickActivity = 0.0
    private var danceBeatDuration = 0.5
    private var colorMotion = MusicColorMotion()
    private var appTimer: Timer?
    private var appProcessIDs: [AudioObjectID] = []
    private var startTask: Task<Void, Never>?
    private var outputListener: AudioObjectPropertyListenerBlock?
    private var lastAudible: TimeInterval?
    private var nextVolumeRead: TimeInterval = 0
    private var cachedOutputGain: Float = 1

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
        analyzer.setLowPower(lowPower)
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
        danceBeat = 0
        danceEnergy = 0
        kickActivity = 0
        danceBeatDuration = 0.5
        colorMotion = MusicColorMotion()
        systemTap?.stop()
        systemTap = nil
        analysis = nil
        lastAudible = nil
        nextVolumeRead = 0
        if frames.current != AudioFrame() { frames.current = AudioFrame() }
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
        analyzer.setLowPower(lowPower)
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

    private func outputGain(at time: TimeInterval) -> Float {
        guard !ignoresOutputVolume, source != .microphone, playbackVolume == .followOutput else { return 1 }
        guard time >= nextVolumeRead else { return cachedOutputGain }
        nextVolumeRead = time + 0.25

        var device = AudioObjectID(kAudioObjectUnknown)
        var address = Self.outputAddress
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                         0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else {
            cachedOutputGain = 1
            return 1
        }

        func read<T>(_ selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement,
                     initial: T) -> T? {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput,
                                                     mElement: element)
            var value = initial
            var size = UInt32(MemoryLayout<T>.size)
            guard AudioObjectHasProperty(device, &address) else { return nil }
            let result = withUnsafeMutableBytes(of: &value) { bytes in
                AudioObjectGetPropertyData(device, &address, 0, nil, &size, bytes.baseAddress!)
            }
            return result == noErr ? value : nil
        }
        let main = kAudioObjectPropertyElementMain
        if read(kAudioDevicePropertyMute, element: main, initial: UInt32(0)) == 1 {
            cachedOutputGain = 0
        } else {
            let scalar = read(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, element: main, initial: Float(1))
                ?? read(kAudioDevicePropertyVolumeScalar, element: main, initial: Float(1))
            let channelVolumes = [UInt32(1), UInt32(2)].compactMap { element -> Float? in
                if read(kAudioDevicePropertyMute, element: element, initial: UInt32(0)) == 1 { return 0 }
                return read(kAudioDevicePropertyVolumeScalar, element: element, initial: Float(1))
            }
            cachedOutputGain = min(1, max(0, scalar ?? channelVolumes.max() ?? 1))
        }
        return cachedOutputGain
    }

    private func startTimer(animated: Bool = false) {
        timer?.invalidate()
        self.animated = animated
        let rate = lowPower ? (animated ? 30.0 : 8.0) : (animated ? 60.0 : 15.0)
        let interval = 1.0 / rate
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateFrame() }
        }
        timer.tolerance = animated ? 0 : interval * 0.10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func updateFrame() {
        guard let analysis else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = min(now - (lastFrameTime ?? now - 1.0 / 30), 0.16)
        lastFrameTime = now
        let decay = pow(0.83, Float(elapsed * 60))
        let gain = outputGain(at: now)
        let input: AudioFrame
        if let latest = analysis.read(), latest.frame.mode == channelMode, now - latest.timestamp < 0.25 {
            var adjusted = latest.frame
            if gain < 1 {
                func scale(_ channel: inout ChannelFrame) {
                    channel.level *= gain
                    channel.bass *= gain
                    channel.impact *= gain
                    channel.bands *= gain
                    channel.waveform.high *= gain
                    channel.waveform.low *= gain
                    if gain == 0 { channel.lastHit = nil }
                }
                scale(&adjusted.left)
                scale(&adjusted.right)
            }
            if adjusted.level > 0.001 { lastAudible = now }
            if allowsFrequencyFocus {
                frequencyFocus.apply(to: &adjusted.left)
                frequencyFocus.apply(to: &adjusted.right)
            }
            input = adjusted
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
            next.beatDuration = danceBeatDuration
            next.danceBeat = danceBeat
            next.danceEnergy = danceEnergy
            next.waveform = next.isActive ? sample.waveform : Waveform()
            for band in 0..<16 {
                let magnitude = sample.bands[band]
                next.bands[band] = smooth(previous.bands[band], magnitude)
                // Display a fixed 60 dB range so quiet harmonics remain visible.
                let decibels = 20 * log10(max(0.001, magnitude))
                let spectrum = min(1, max(0, (decibels + 60) / 60))
                next.spectrum[band] = max(spectrum, previous.spectrum[band] * decay)
            }
            return next
        }

        // Integrate tempo into a continuous phase. New onsets never reset the pose.
        if input.isActive {
            danceBeatDuration += (input.left.beatDuration - danceBeatDuration) * (1 - exp(-elapsed / 3.0))
        }
        danceBeat += elapsed / danceBeatDuration

        // Bass alone can be sustained ambience. Repeated attacks in the low end
        // contribute most of the energy for the party choreography.
        let bass = Double(max(input.left.bass, input.right.bass))
        let level = Double(input.level)
        let bassPresence = min(1, bass / max(0.004, level) * 1.7)
        let impact = Double(max(input.left.impact, input.right.impact))
        let kick = min(1, impact * 2.6) * bassPresence
        kickActivity += (kick - kickActivity) * (1 - exp(-elapsed / 1.1))
        let energyTarget = min(1, max(0, kickActivity * 3.8 - 0.08) + bassPresence * 0.18)
        let energyResponse = energyTarget > danceEnergy ? 1.8 : 2.8
        danceEnergy += (energyTarget - danceEnergy) * (1 - exp(-elapsed / energyResponse))

        let frame = frames.current
        let previous = frame.mode == input.mode ? frame : AudioFrame(mode: input.mode)
        let left = smoothChannel(previous.left, input.left)
        let right = input.mode == .mono ? left : smoothChannel(previous.right, input.right)
        var next = AudioFrame(left: left, right: right, mode: input.mode)
        next.animationTime = now
        next.musicHue = colorMotion.update(with: next, elapsed: elapsed)
        if frame != next { frames.current = next }
        if next.isActive != animated { startTimer(animated: next.isActive) }

        let label = source.audioLabel
        let nextStatus = now - (lastAudible ?? -.infinity) < 1.2 ? "Receiving \(label)" : "Waiting for \(label)…"
        if status != nextStatus { status = nextStatus }
    }
}
