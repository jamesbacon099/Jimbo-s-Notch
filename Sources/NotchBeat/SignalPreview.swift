import SwiftUI

struct LiveSignalPreview: View {
    let frames: AudioFrames
    let equalizerFrames: AudioFrames
    @ObservedObject var settings: VisualizerSettings
    let mode: ChannelMode
    let lowPower: Bool
    @State private var frame = AudioFrame()
    @State private var equalizerFrame = AudioFrame()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func signal(for style: VisualizerStyle) -> AudioFrame {
        style == .equalizer && equalizerFrames !== frames ? equalizerFrame : frame
    }

    private func hasSignal(_ frame: AudioFrame, for style: VisualizerStyle) -> Bool {
        style == .equalizer ? frame.left.hasSpectrum || frame.right.hasSpectrum : frame.isActive
    }

    private func previewTrail(on side: TrailSide) -> some View {
        ZStack {
            ForEach(settings.displayedStyles) { style in
                let frame = signal(for: style)
                let active = hasSignal(frame, for: style)
                let channel = active
                    ? (side == .left ? frame.left : frame.right)
                    : (side == .left || mode == .mono ? Self.previewLeft : Self.previewRight)
                settings.makeTrail(style: style, frame: frame, channel: channel,
                                   time: reduceMotion || !active ? 3.4 : frame.animationTime,
                                   side: side, mirrored: mode == .mono, lowPower: lowPower,
                                   innerInset: 4, flowFromNotch: settings.flowFromNotch)
                    .opacity(style == settings.selectedStyle ? 1 : settings.secondOpacity)
            }
        }
    }

    var body: some View {
        let frame = signal(for: settings.selectedStyle)
        let palette = settings.palette(for: frame)
        let hasLiveSignal = settings.displayedStyles.contains { hasSignal(signal(for: $0), for: $0) }
        VStack(spacing: 6) {
            HStack {
                Text(mode == .mono ? "MONO FIELD" : "STEREO FIELD").tracking(1.5)
                Spacer()
                Label(hasLiveSignal ? "LIVE" : "PALETTE PREVIEW", systemImage: "circle.fill")
                    .labelStyle(PreviewBadge())
            }
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.70))

            HStack(spacing: 5) {
                previewTrail(on: .left)
                Capsule()
                    .fill(.black.opacity(0.68))
                    .overlay { Capsule().strokeBorder(.white.opacity(0.13), lineWidth: 1) }
                    .frame(width: 31, height: 12)
                previewTrail(on: .right)
            }
            .frame(height: 43)
            .accessibilityHidden(true)

            HStack(spacing: 13) {
                meter("L", value: frame.left.level, color: palette.primary)
                meter("R", value: frame.right.level, color: palette.highlight)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            let shape = RoundedRectangle(cornerRadius: 16)
            shape.fill(Color(red: 0.043, green: 0.054, blue: 0.080))
                .overlay {
                    shape.fill(LinearGradient(colors: [palette.primary.opacity(0.19), .clear, palette.secondary.opacity(0.20)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .overlay { shape.strokeBorder(.white.opacity(0.14), lineWidth: 1) }
        }
        .accessibilityLabel(hasLiveSignal ? "Live audio levels" : "Palette preview")
        .accessibilityElement(children: .contain)
        .onReceive(frames.$current.throttle(for: .milliseconds(50), scheduler: RunLoop.main, latest: true)) {
            self.frame = $0
        }
        .onReceive(equalizerFrames.$current.throttle(for: .milliseconds(50), scheduler: RunLoop.main, latest: true)) {
            if equalizerFrames !== frames { equalizerFrame = $0 }
        }
    }

    private func meter(_ side: String, value: Float, color: Color) -> some View {
        HStack(spacing: 5) {
            Text(side)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.69))
                .accessibilityHidden(true)
            GeometryReader { geometry in
                Capsule().fill(.white.opacity(0.13))
                    .overlay(alignment: .leading) {
                        Capsule().fill(color)
                            .frame(width: geometry.size.width * CGFloat(value))
                    }
            }
            .frame(height: 3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(side == "L" ? "Left input" : "Right input")
        .accessibilityValue(Double(value).formatted(.percent.precision(.fractionLength(0))))
    }

    private static let previewLeft = demo(level: 0.56, phase: 0)
    private static let previewRight = demo(level: 0.44, phase: 1.8)

    private static func demo(level: Float, phase: Double) -> ChannelFrame {
        var channel = ChannelFrame(level: level, bass: level * 0.8, impact: level * 0.65,
                                   bands: SIMD16<Float>(repeating: level * 0.55))
        for band in 0..<16 {
            channel.spectrum[band] = level * (0.25 + 0.75 * abs(sin(Float(band) * 0.47)))
        }
        for index in 0..<32 {
            let progress = Double(index) / 31
            let pulse = Float(abs(sin(progress * .pi * 3 + phase))) * level
            channel.waveform.high[index] = pulse * 0.9
            channel.waveform.low[index] = -pulse * 0.65
        }
        return channel
    }
}

private struct PreviewBadge: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
                .font(.system(size: 5))
            configuration.title
                .tracking(0.5)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.white.opacity(0.09), in: .capsule)
    }
}
