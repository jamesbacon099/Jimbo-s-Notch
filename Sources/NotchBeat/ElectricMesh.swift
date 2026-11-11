import SwiftUI

extension VisualizerTrail {
    func drawElectricMesh(in context: GraphicsContext, size: CGSize, time: TimeInterval) {
        let span = size.width - innerInset - 4
        guard span > 0, size.height > 0 else { return }

        let height = size.height
        let bass = Double(channel.bass)
        let impact = Double(channel.impact)
        let rotation = time * 1.25
        let ringCount = Int((lowPower ? 4.0 : 6.0) * effectMotion.density).clamped(to: 3...14)
        let sectors = lowPower ? 24 : 48
        let center = CGPoint(x: x(0.5, size: size), y: height * 0.58)
        let ovalHeight = 0.17 + 0.045 * sin(time * 0.92) + 0.035 * bass

        let grid: [[CGPoint]] = (0..<ringCount).map { ring in
            let depth = Double(ring) / Double(ringCount - 1)
            let radius = 0.39 + depth * 0.56
            let rim = exp(-pow((depth - 0.73) * 3.9, 2))
            return (0..<sectors).map { sector in
                let progress = Double(sector) / Double(sectors)
                let angle = progress * 2 * .pi + rotation - depth * 0.48
                let bin = abs(2 * progress - 1) * 15
                let lower = Int(bin)
                let mix = bin - Double(lower)
                let energy = Double(channel.bands[lower]) * (1 - mix)
                    + Double(channel.bands[min(15, lower + 1)]) * mix
                let crest = pow(0.5 + 0.5 * cos(angle * 5 - time * 3.9 + depth * 5), 3)
                let peak = rim * effectMotion.waveDepth * (0.12 * crest + 0.30 * sqrt(max(0, energy))
                    + 0.08 * impact)
                let reach = radius * (0.95 + 0.045 * sin(angle * 3 - time * 2 + depth * 3))
                let horizontal = 0.5 + cos(angle) * reach * 0.49
                let vertical = 0.59 + sin(angle) * reach * ovalHeight
                    + cos(angle) * reach * 0.085 - min(0.44, peak)
                return CGPoint(x: x(horizontal, size: size), y: height * vertical)
            }
        }

        let colors: [Color]
        if let hue = palette.rainbowHue {
            colors = (0...6).map { index in
                Color(hue: (hue + Double(index) / 6).truncatingRemainder(dividingBy: 1),
                      saturation: 0.85, brightness: 1)
            }
        } else {
            colors = [palette.secondary, palette.primary, palette.highlight, palette.primary]
        }
        let start = CGPoint(x: x(0, size: size), y: height * 0.76)
        let end = CGPoint(x: x(1, size: size), y: height * 0.30)
        let meshTint = GraphicsContext.Shading.linearGradient(Gradient(colors: colors), startPoint: start, endPoint: end)
        let lineWidth = max(0.6, min(1.4, height * 0.024))

        var crossbars = Path()
        for sector in stride(from: 0, to: sectors, by: 2) {
            crossbars.move(to: grid[0][sector])
            for ring in grid.dropFirst() {
                crossbars.addLine(to: ring[sector])
            }
        }
        var lattice = context
        lattice.opacity = 0.56
        lattice.stroke(crossbars, with: meshTint, lineWidth: lineWidth * 0.77)

        var rings = Path()
        for loop in grid {
            rings.move(to: loop[0])
            rings.addLines(Array(loop.dropFirst()))
            rings.closeSubpath()
        }
        var halo = context
        halo.opacity = 0.24
        halo.stroke(rings, with: meshTint, lineWidth: lineWidth * 3.1)
        context.stroke(rings, with: meshTint,
                       style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))

        let rays = lowPower ? 5 : 9
        let reach = 0.54 + 0.20 * bass + 0.16 * impact
        for ray in 0..<rays {
            let angle = Double(ray) / Double(rays) * 2 * .pi - time * 1.7
            let pulse = 0.69 + 0.31 * sin(time * 4.1 + Double(ray) * 1.73)
            var bolt = Path()
            bolt.move(to: center)
            for segment in 1...11 {
                let step = Double(segment) / 11
                let bend = sin(step * 17 - time * 6 + Double(ray)) * 0.21 * step
                let jag = (segment.isMultiple(of: 2) ? 1.0 : -1.0) * 0.10 * step
                let heading = angle + bend + jag
                let radius = step * reach * pulse
                bolt.addLine(to: CGPoint(x: x(0.5 + cos(heading) * radius * 0.50, size: size),
                                         y: center.y + sin(heading) * radius * height * 0.55))
            }
            let tint = colors[ray % colors.count]
            let glow = Gradient(colors: [palette.sparkleHighlight.opacity(0.96),
                                         tint.opacity(0.85), tint.opacity(0.04)])
            context.stroke(bolt, with: .radialGradient(glow, center: center,
                                                        startRadius: 0, endRadius: max(1, span * reach * 0.40)),
                           style: StrokeStyle(lineWidth: lineWidth * (0.85 + impact * 0.55), lineJoin: .round))
        }
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
