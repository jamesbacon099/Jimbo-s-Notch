import SwiftUI

extension VisualizerTrail {
    func drawSilk(in context: GraphicsContext, size: CGSize, time: TimeInterval) {
        let samples = lowPower ? 56 : 112
        let layers = lowPower ? 4 : 7
        let level = Double(channel.level)
        let bass = Double(channel.bass)
        let midline = size.height * 0.5
        let colors = palette.colors
        let detail = effectMotion.silkDetail
        let spacing = effectMotion.density.squareRoot()

        for layer in 0..<layers {
            let position = Double(layer) / Double(layers - 1)
            let offset = position * 2 - 1
            var ridge = Path()
            var thread = Path()
            var hem = Path()
            var edge: [CGPoint] = []
            edge.reserveCapacity(samples + 1)

            for sample in 0...samples {
                let progress = Double(sample) / Double(samples)
                let bin = progress * 15
                let lower = Int(bin)
                let blend = bin - Double(lower)
                let band = Double(channel.bands[lower]) * (1 - blend)
                    + Double(channel.bands[min(15, lower + 1)]) * blend
                let taper = 0.20 + 0.80 * sin(progress * .pi)
                let amplitude = taper * min(0.45, (0.20 + level * 0.17 + band * 0.12) * effectMotion.waveDepth)
                let positionAngle = progress * spacing * 2 * .pi
                let twist = positionAngle * 1.5 - time * 2.1 + offset * 1.55
                let drift = sin(progress * 5 - time * 1.15) * 0.30
                let weave = sin(positionAngle * 3.4 - time * 4.8 + offset * 2.7)
                let center = drift + 0.59 * sin(twist) + 0.12 * sin(2 * twist + time * 0.5)
                    + detail * (0.032 + band * 0.06) * weave
                let width = 0.035 + 0.23 * abs(cos(twist)) * (0.65 + bass * 0.35)

                let horizontal = x(progress, size: size)
                let y = midline + size.height * amplitude * center
                let point = CGPoint(x: horizontal, y: y)
                if sample == 0 {
                    ridge.move(to: point)
                } else {
                    ridge.addLine(to: point)
                }
                let ribbonWidth = size.height * amplitude * width
                let edgePoint = CGPoint(x: horizontal, y: y + ribbonWidth)
                edge.append(edgePoint)
                if detail > 0 {
                    let threadPoint = CGPoint(x: horizontal, y: y + ribbonWidth * (0.5 + 0.37 * weave))
                    if sample == 0 {
                        thread.move(to: threadPoint)
                        hem.move(to: edgePoint)
                    } else {
                        thread.addLine(to: threadPoint)
                        hem.addLine(to: edgePoint)
                    }
                }
            }

            var ribbon = ridge
            for point in edge.reversed() {
                ribbon.addLine(to: point)
            }
            ribbon.closeSubpath()
            let color = colors[layer % colors.count]
            let tint = Gradient(stops: [
                .init(color: color.opacity(0.30), location: 0),
                .init(color: palette.highlight.opacity(0.44 + level * 0.18), location: 0.46),
                .init(color: color.opacity(0.08), location: 1)
            ])
            let start = CGPoint(x: x(0, size: size), y: midline)
            let end = CGPoint(x: x(1, size: size), y: midline)
            context.fill(ribbon, with: .linearGradient(tint, startPoint: start, endPoint: end))
            if detail > 0 {
                let glint = 0.5 + 0.34 * sin(time * 2.7 - position * .pi)
                let threadTint = Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: color.opacity(detail * 0.28), location: glint - 0.14),
                    .init(color: palette.highlight.opacity(detail * 0.58), location: glint),
                    .init(color: color.opacity(detail * 0.25), location: glint + 0.14),
                    .init(color: .clear, location: 1)
                ])
                context.stroke(thread, with: .linearGradient(threadTint, startPoint: start, endPoint: end),
                               lineWidth: max(0.55, size.height * 0.016))
                context.stroke(hem, with: .color(color.opacity(detail * 0.28)), lineWidth: 0.55)
            }
            context.stroke(ridge, with: .linearGradient(
                Gradient(colors: [color.opacity(0.76), palette.highlight.opacity(0.92), color.opacity(0.22)]),
                startPoint: start, endPoint: end),
                style: StrokeStyle(lineWidth: max(0.6, size.height * (0.014 + level * 0.012)), lineJoin: .round))
        }
    }
}
