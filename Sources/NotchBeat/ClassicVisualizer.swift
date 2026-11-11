import SwiftUI

struct ClassicTrail: View {
    let channel: ChannelFrame
    let time: TimeInterval
    let palette: TrailPalette
    let side: TrailSide
    var mirrored = false
    var lowPower = false
    var innerInset: CGFloat = 4

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            ClassicVisualizer(channel: channel, time: time, palette: palette, side: side,
                              mirrored: mirrored, lowPower: lowPower, innerInset: innerInset).draw(in: context, size: size)
        }
        .mask {
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .white, location: 0.18),
                .init(color: .white, location: 0.82),
                .init(color: .clear, location: 1)
            ], startPoint: .top, endPoint: .bottom)
        }
    }
}

private struct ClassicVisualizer {
    let channel: ChannelFrame
    let time: TimeInterval
    let palette: TrailPalette
    let side: TrailSide
    let mirrored: Bool
    let lowPower: Bool
    let innerInset: CGFloat

    private var tint: Color { palette.primary }
    private var level: Double { Double(channel.level) }
    private var bass: Double { Double(channel.bass) }
    private var hit: Double { Double(channel.impact) }
    private var cycleTime: Double { time.truncatingRemainder(dividingBy: 24) }
    private var phase: Double { cycleTime * .pi / 12 + (mirrored || side == .left ? 0 : .pi / 2) }

    func draw(in context: GraphicsContext, size: CGSize) {
        guard channel.isActive else { return }

        drawWaveform(in: context, size: size)
        if lowPower {
            drawRibbon(in: context, size: size, strand: 0, color: tint)
            return
        }
        for (strand, color) in palette.colors.enumerated() {
            drawRibbon(in: context, size: size, strand: strand, color: color)
            drawComet(in: context, size: size, strand: strand, color: color)
        }
        drawStars(in: context, size: size)
        drawBeatPulse(in: context, size: size)
    }

    private func drawWaveform(in context: GraphicsContext, size: CGSize) {
        let scale = detailScale(size: size)
        let middle = size.height / 2
        let gain = 2.4 + level * 1.4
        let height = middle * 0.96
        func point(_ index: Int, sample: Float) -> CGPoint {
            let progress = Double(index) / 31
            let taper = sqrt(sin(progress * .pi))
            let normalized = tanh(Double(sample) * gain)
            return CGPoint(x: x(progress, width: size.width), y: middle - normalized * height * taper)
        }

        var envelope = Path()
        for index in 0..<32 {
            let point = point(index, sample: channel.waveform.high[index])
            if index == 0 { envelope.move(to: point) } else { envelope.addLine(to: point) }
        }
        for index in (0..<32).reversed() {
            envelope.addLine(to: point(index, sample: channel.waveform.low[index]))
        }
        envelope.closeSubpath()
        let strength = min(1, level * 0.8 + hit * 0.4)
        let colors = Gradient(colors: [palette.secondary.opacity(strength * 0.25), tint.opacity(strength * 0.20),
                                       palette.highlight.opacity(strength * 0.17)])
        context.fill(envelope, with: .linearGradient(colors, startPoint: CGPoint(x: x(0, width: size.width), y: 0),
                                                     endPoint: CGPoint(x: x(1, width: size.width), y: size.height)))
        context.stroke(envelope, with: .color(palette.highlight.opacity(strength * 0.48)),
                       style: StrokeStyle(lineWidth: 1.0 * scale, lineCap: .round, lineJoin: .round))
    }

    private func drawRibbon(in context: GraphicsContext, size: CGSize, strand: Int, color: Color) {
        var ribbon = Path()
        let segments = lowPower ? 20 : 32
        for index in 0...segments {
            let progress = Double(index) / Double(segments)
            let point = ribbonPoint(progress, strand: strand, size: size)
            if index == 0 { ribbon.move(to: point) } else { ribbon.addLine(to: point) }
        }

        let band = Double(channel.bands[2 + strand * 5])
        let light = min(1, 0.12 + level * 0.68 + band * 0.27 + hit * 0.32)
        let scale = detailScale(size: size)
        let glow = light * (0.20 + hit * 0.10)
        let halo = Gradient(colors: [.clear, color.opacity(glow), tint.opacity(glow * 1.2), .clear])
        let core = Gradient(colors: [.clear, color.opacity(light), tint.opacity(light * 0.92), .clear])
        let start = CGPoint(x: x(0, width: size.width), y: size.height / 2)
        let end = CGPoint(x: x(1, width: size.width), y: size.height / 2)
        context.stroke(ribbon, with: .linearGradient(halo, startPoint: start, endPoint: end),
                       style: StrokeStyle(lineWidth: (4 + band * 4) * scale, lineCap: .round, lineJoin: .round))
        context.stroke(ribbon, with: .linearGradient(core, startPoint: start, endPoint: end),
                       style: StrokeStyle(lineWidth: (0.75 + band * 1.25) * scale, lineCap: .round, lineJoin: .round))
    }

    private func drawComet(in context: GraphicsContext, size: CGSize, strand: Int, color: Color) {
        let cycle = cycleTime * Double(strand + 7) / 24 + Double(strand) * 0.29 + (!mirrored && side == .left ? 0.17 : 0)
        let age = cycle - floor(cycle)
        let brightness = sin(age * .pi) * min(1, 0.22 + level * 0.7 + hit * 0.52)
        let head = 0.11 + age * 0.78
        let scale = detailScale(size: size)
        let tailSpacing = 0.027 + hit * 0.0105
        for tail in (0..<7).reversed() {
            let fade = 1 - Double(tail) / 7
            let progress = max(0, head - Double(tail) * tailSpacing)
            let point = ribbonPoint(progress, strand: strand, size: size)
            let radius = (1.2 + level * 1.0 + hit * 1.0) * fade * scale
            dot(in: context, at: point, radius: radius * 2, color: color.opacity(brightness * fade * 0.18))
            dot(in: context, at: point, radius: radius, color: color.opacity(brightness * fade))
            if tail == 0 { dot(in: context, at: point, radius: radius * 0.46, color: palette.sparkleHighlight.opacity(brightness)) }
        }
    }

    private func ribbonPoint(_ progress: Double, strand: Int, size: CGSize) -> CGPoint {
        let offset = Double(strand) * .pi * 2 / 3
        let band = Double(channel.bands[2 + strand * 5])
        let envelope = sin(progress * .pi)
        let first = sin(progress * .pi * 3 - phase * 7 + offset)
        let second = sin(progress * .pi * 6 + phase * 11 + offset)
        let amplitude = min(6.8, 1.9 + bass * 3.7 + band * 2.3 + hit * 1.6)
        let y = size.height / 2 + (first + second * 0.28) * envelope * amplitude * (size.height / 21)
        return CGPoint(x: x(progress, width: size.width), y: y)
    }

    private func drawStars(in context: GraphicsContext, size: CGSize) {
        let scale = detailScale(size: size)
        for index in 0..<Int(20 * scale) {
            let seed = Double(index) * 0.618
            let cycle = cycleTime * Double(index % 4 + 9) / 24 + seed
            let age = cycle - floor(cycle)
            let brightness = min(1, sin(age * .pi) * (level * 0.43 + hit * 0.78))
            let progress = 0.08 + age * 0.84
            let rise = (1.5 + age * 6) * sin(seed * 17) * (0.6 + hit * 0.4) * (size.height / 21)
            let point = CGPoint(x: x(progress, width: size.width), y: size.height / 2 + rise)
            let color = index.isMultiple(of: 3) ? palette.sparkleHighlight : tint
            dot(in: context, at: point, radius: (0.45 + brightness * 0.85) * scale, color: color.opacity(brightness))
        }
    }

    private func drawBeatPulse(in context: GraphicsContext, size: CGSize) {
        guard let lastHit = channel.lastHit else { return }
        let age = (time - lastHit) / 0.42
        guard (0..<1).contains(age) else { return }

        let light = (1 - age) * min(1, hit * 0.75 + level * 0.45)
        let scale = detailScale(size: size)
        for strand in 0..<3 {
            let head = 0.06 + age * 0.88
            let point = ribbonPoint(head, strand: strand, size: size)
            dot(in: context, at: point, radius: 5 * scale, color: tint.opacity(light * 0.28))
            dot(in: context, at: point, radius: 1.7 * scale, color: palette.sparkleHighlight.opacity(light))
        }
    }

    private func detailScale(size: CGSize) -> CGFloat {
        min(1, 0.4 + size.width / 150, 0.35 + size.height / 26)
    }

    private func x(_ progress: Double, width: CGFloat) -> CGFloat {
        let distance = innerInset + progress * (width - innerInset - 4)
        return side == .left ? width - distance : distance
    }

    private func dot(in context: GraphicsContext, at point: CGPoint, radius: CGFloat, color: Color) {
        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: rect), with: .color(color))
    }
}
