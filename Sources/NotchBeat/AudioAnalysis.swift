import Accelerate
import CoreAudio
import Foundation

enum ChannelMode: String, CaseIterable {
    case stereo = "Stereo"
    case mono = "Mono"
}

struct Waveform: Equatable {
    var low = SIMD32<Float>(repeating: 0)
    var high = SIMD32<Float>(repeating: 0)
}

struct ChannelFrame: Equatable {
    var level: Float = 0
    var bass: Float = 0
    var impact: Float = 0
    var bands = SIMD16<Float>(repeating: 0)
    var lastHit: TimeInterval?
    var waveform = Waveform()

    var isActive: Bool { max(level, bass, impact) > 0.002 }
}

struct AudioFrame: Equatable {
    var left = ChannelFrame()
    var right = ChannelFrame()
    var animationTime: TimeInterval = 0
    var musicHue: Double?
    var mode = ChannelMode.stereo

    var level: Float { max(left.level, right.level) }
    var isActive: Bool { left.isActive || right.isActive }

    var targetMusicHue: Double? {
        var total: Double = 0
        var weighted: Double = 0
        for band in 0..<16 {
            let l = Double(left.bands[band])
            let r = Double(right.bands[band])
            let energy = l * l + r * r
            total += energy
            weighted += energy * Double(band)
        }
        guard total > 0.0001 else { return nil }
        let centroid = weighted / (total * 15)
        let beat = Double(max(left.impact, right.impact))
        return min(0.98, 0.04 + 0.80 * pow(centroid, 0.72) + beat * 0.12)
    }
}

struct MusicColorMotion {
    private var target: Double?
    private var hue: Double?
    private var lastBeat = -Double.infinity
    private var lastSpectrum: Double?

    mutating func update(with frame: AudioFrame, elapsed: TimeInterval) -> Double? {
        guard frame.isActive else {
            self = MusicColorMotion()
            return nil
        }
        guard let spectrum = frame.targetMusicHue else { return hue.map(wrapped) }

        let beat = max(frame.left.lastHit ?? -.infinity, frame.right.lastHit ?? -.infinity)
        let impact = Double(max(frame.left.impact, frame.right.impact))
        let beatStep = lastBeat.isFinite && beat > lastBeat ? 0.055 + impact * 0.075 : 0
        let rate = 0.026 + Double(frame.level) * 0.10 + spectrum * 0.045
        let tonalShift = (spectrum - (lastSpectrum ?? spectrum)) * 0.32
        let target = (target ?? spectrum) + elapsed * rate + beatStep + tonalShift
        let previous = hue ?? spectrum
        let smooth = previous + (target - previous) * (1 - exp(-elapsed / 0.16))

        self.target = target
        hue = smooth
        lastBeat = max(lastBeat, beat)
        lastSpectrum = spectrum
        return wrapped(smooth)
    }

    private func wrapped(_ hue: Double) -> Double { hue - floor(hue) }
}

// The audio callback owns the analyzer. The UI only reads its latest result.
final class AudioAnalysis {
    private static let size = 2048
    private static let hop = 1024
    private let setup: FFTSetup
    private let window: [Float]
    private let bandBins: [ClosedRange<Int>]
    private let bassBins: ClosedRange<Int>
    private var real = [Float](repeating: 0, count: size)
    private var imaginary = [Float](repeating: 0, count: size)
    private var leftSamples = [Float](repeating: 0, count: size)
    private var rightSamples = [Float](repeating: 0, count: size)
    private var writeIndex = 0
    private var untilNextFrame = size
    private let impactDecay: Float
    private var leftOnsets = OnsetDetector()
    private var rightOnsets = OnsetDetector()
    private let lock = NSLock()
    private var latest: (frame: AudioFrame, timestamp: TimeInterval)?
    private var requestedMode = ChannelMode.stereo
    private var captureMode = ChannelMode.stereo

    init(sampleRate: Double) {
        impactDecay = exp(-Float(Double(Self.hop) / sampleRate) / 0.105)
        setup = vDSP_create_fftsetup(11, FFTRadix(kFFTRadix2))!
        var window = [Float](repeating: 0, count: Self.size)
        vDSP_hann_window(&window, vDSP_Length(Self.size), Int32(vDSP_HANN_DENORM))
        self.window = window

        func bins(_ low: Double, _ high: Double) -> ClosedRange<Int> {
            let scale = Double(Self.size) / sampleRate
            let lower = min(Self.size / 2 - 1, max(1, Int(ceil(low * scale))))
            let upper = min(Self.size / 2 - 1, max(lower, Int(ceil(high * scale)) - 1))
            return lower...upper
        }
        bandBins = (0..<16).map { band in
            bins(45 * pow(300, Double(band) / 16), 45 * pow(300, Double(band + 1) / 16))
        }
        bassBins = bins(40, 170)
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    func append(_ buffers: UnsafePointer<AudioBufferList>) {
        let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffers))
        guard let first = list.first, let data = first.mData, first.mNumberChannels > 0 else { return }

        let left = data.assumingMemoryBound(to: Float.self)
        let leftStride = Int(first.mNumberChannels)
        var right = left
        var rightStride = leftStride
        var frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.stride * leftStride)
        if leftStride > 1 {
            right = left.advanced(by: 1)
        } else if list.count > 1, let data = list[1].mData, list[1].mNumberChannels > 0 {
            right = data.assumingMemoryBound(to: Float.self)
            rightStride = Int(list[1].mNumberChannels)
            frames = min(frames, Int(list[1].mDataByteSize) / (MemoryLayout<Float>.stride * rightStride))
        }

        for frame in 0..<frames {
            leftSamples[writeIndex] = left[frame * leftStride]
            rightSamples[writeIndex] = right[frame * rightStride]
            writeIndex = (writeIndex + 1) & (Self.size - 1)
            untilNextFrame -= 1
            if untilNextFrame == 0 {
                finishFrame()
                untilNextFrame = Self.hop
            }
        }
    }

    func read() -> (frame: AudioFrame, timestamp: TimeInterval)? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    func selectMode(_ mode: ChannelMode) {
        lock.lock()
        if requestedMode != mode {
            requestedMode = mode
            latest = nil
        }
        lock.unlock()
    }

    private func finishFrame() {
        if lock.try() {
            let mode = requestedMode
            lock.unlock()
            if captureMode != mode {
                captureMode = mode
                leftOnsets = OnsetDetector()
                rightOnsets = OnsetDetector()
            }
        }
        let mono = captureMode == .mono
        var frame = AudioFrame(mode: captureMode)
        var leftPower: Float = 0
        var rightPower: Float = 0
        let bucketSize = Self.size / 32
        for bucket in 0..<32 {
            var leftLow: Float = 0
            var leftHigh: Float = 0
            var rightLow: Float = 0
            var rightHigh: Float = 0
            for index in (bucket * bucketSize)..<((bucket + 1) * bucketSize) {
                let sampleIndex = (writeIndex + index) & (Self.size - 1)
                let l = leftSamples[sampleIndex]
                let r = rightSamples[sampleIndex]
                let left = mono ? (l + r) * 0.5 : l
                let right = mono ? left : r
                real[index] = left * window[index]
                imaginary[index] = right * window[index]
                leftPower += left * left
                rightPower += right * right
                leftLow = min(leftLow, left)
                leftHigh = max(leftHigh, left)
                rightLow = min(rightLow, right)
                rightHigh = max(rightHigh, right)
            }
            frame.left.waveform.low[bucket] = leftLow
            frame.left.waveform.high[bucket] = leftHigh
            frame.right.waveform.low[bucket] = rightLow
            frame.right.waveform.high[bucket] = rightHigh
        }

        frame.left.level = sqrt(leftPower / Float(Self.size))
        frame.right.level = sqrt(rightPower / Float(Self.size))
        if leftPower > 0 || rightPower > 0 {
            analyzeSpectrum(into: &frame)
        }

        let now = ProcessInfo.processInfo.systemUptime
        leftOnsets.apply(to: &frame.left, at: now, decay: impactDecay)
        if mono {
            frame.right = frame.left
        } else {
            rightOnsets.apply(to: &frame.right, at: now, decay: impactDecay)
        }
        if lock.try() {
            if requestedMode == captureMode { latest = (frame, now) }
            lock.unlock()
        }
    }

    private func analyzeSpectrum(into frame: inout AudioFrame) {
        real.withUnsafeMutableBufferPointer { real in
            imaginary.withUnsafeMutableBufferPointer { imaginary in
                var split = DSPSplitComplex(realp: real.baseAddress!, imagp: imaginary.baseAddress!)
                vDSP_fft_zip(setup, &split, 1, 11, FFTDirection(FFT_FORWARD))
            }
        }
        let bass = peak(in: bassBins)
        frame.left.bass = bass.x
        frame.right.bass = bass.y
        for band in 0..<16 {
            let peak = peak(in: bandBins[band])
            frame.left.bands[band] = peak.x
            frame.right.bands[band] = peak.y
        }
    }

    private func peak(in bins: ClosedRange<Int>) -> SIMD2<Float> {
        var leftPeak: Float = 0
        var rightPeak: Float = 0
        for bin in bins {
            let mirror = Self.size - bin
            // Unpack the FFT of L + iR using its positive and negative bins.
            // These components are twice the channel FFT values.
            let leftReal = real[bin] + real[mirror]
            let leftImag = imaginary[bin] - imaginary[mirror]
            let rightReal = imaginary[bin] + imaginary[mirror]
            let rightImag = real[mirror] - real[bin]
            leftPeak = max(leftPeak, leftReal * leftReal + leftImag * leftImag)
            rightPeak = max(rightPeak, rightReal * rightReal + rightImag * rightImag)
        }
        let scale = 2 / Float(Self.size)
        return SIMD2(sqrt(leftPeak) * scale, sqrt(rightPeak) * scale)
    }
}

private struct OnsetDetector {
    private var previousSpectrum = SIMD16<Float>(repeating: 0)
    private var previousLevel: Float = 0
    private var previousBass: Float = 0
    private var averageFlux: Float = 0
    private var impact: Float = 0
    private var lastHit: TimeInterval?

    mutating func apply(to channel: inout ChannelFrame, at time: TimeInterval, decay: Float) {
        var spectralFlux: Float = 0
        for band in 0..<16 {
            let value = sqrt(channel.bands[band])
            spectralFlux += max(0, value - previousSpectrum[band])
            previousSpectrum[band] = value
        }

        let level = sqrt(channel.level)
        let bass = sqrt(channel.bass)
        let flux = spectralFlux / 16 * 1.7 + max(0, level - previousLevel) * 0.7 + max(0, bass - previousBass) * 0.4
        let onset = max(0, flux - averageFlux * 1.65 - 0.015)
        averageFlux += (flux - averageFlux) * 0.065
        previousLevel = level
        previousBass = bass
        let attack = 1 - exp(-onset * 7)
        if attack > 0.40, lastHit.map({ time - $0 >= 0.11 }) ?? true {
            lastHit = time
        }
        impact = max(attack, impact * decay)
        channel.impact = impact
        channel.lastHit = lastHit
    }
}
