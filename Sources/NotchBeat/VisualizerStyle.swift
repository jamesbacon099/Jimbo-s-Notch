import SwiftUI

enum RelaxedDance: String, CaseIterable {
    case standing = "Default"
    case martialArts = "Martial arts"
    case headbang = "Tweakers"
    case slowdance = "Slowdancing"
}

enum VisualizerStyle: String, CaseIterable, Identifiable {
    case classic = "Default"
    case dancers = "Dancers"
    case fire = "Fire"
    case splash = "Splash"
    case equalizer = "Equalizer"
    case arcade = "Arcade"
    case pulse = "Pulse"

    var id: String { rawValue }

    var summary: String {
        switch self {
        case .classic: return "Flowing waveforms, ribbons, and sparkling trails."
        case .dancers: return "Stickmen sway to softer music and break into bigger moves as the drums pick up."
        case .splash: return "Water jets and droplets splash with the beat."
        case .equalizer: return "Bars show the energy in each frequency band."
        case .arcade: return "A chunky pixel waveform and bursts react to the beat."
        case .pulse: return "Bright waves roll outward from the notch."
        case .fire: return "Dancing flames and rising sparks react to the beat."
        }
    }
}

struct VisualizerTrail: View {
    let style: VisualizerStyle
    var flowFromNotch = false
    var dancersPerSide = 1
    var relaxedDance = RelaxedDance.martialArts
    let channel: ChannelFrame
    let time: TimeInterval
    let palette: TrailPalette
    let side: TrailSide
    var mirrored = false
    var lowPower = false
    var innerInset: CGFloat = 4
    var glassFade = false
    var splashDensity = 1.0
    var dancerSparks = false

    var body: some View {
        if glassFade {
            artwork.mask {
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.85),
                    .init(color: .clear, location: 1)
                ], startPoint: side == .left ? .trailing : .leading,
                   endPoint: side == .left ? .leading : .trailing)
            }
        } else {
            artwork
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if style == .classic {
            ClassicTrail(channel: channel, time: time, palette: palette, side: side,
                         mirrored: mirrored, lowPower: lowPower, innerInset: innerInset)
        } else {
            Canvas(rendersAsynchronously: style != .dancers) { context, size in
                guard channel.isActive || style == .dancers || (style == .equalizer && channel.hasSpectrum) else { return }
                let phase = time.truncatingRemainder(dividingBy: 120)
                    + (mirrored || side == .left ? 0 : 7.3)
                if style == .dancers {
                    let count = min(5, max(1, dancersPerSide))
                    for index in 0..<count {
                        drawDancer(in: context, size: size, index: index, count: count)
                    }
                } else if style == .equalizer || style == .arcade || style == .pulse {
                    drawMusicEffect(in: context, size: size, phase: phase)
                } else if style == .splash || flowFromNotch {
                    drawFromNotch(in: context, size: size, phase: phase)
                } else {
                    drawFire(in: context, size: size, phase: phase)
                }
            }
            .mask {
                Rectangle().fill(LinearGradient(colors: style == .dancers ? [.white, .white] : [.clear, .white, .white, .clear],
                                                startPoint: .top, endPoint: .bottom))
            }
            .clipped()
        }
    }

    private func x(_ progress: Double, size: CGSize) -> CGFloat {
        let distance = innerInset + progress * max(0, size.width - innerInset - 4)
        return side == .left ? size.width - distance : distance
    }

    private func drawDancer(in context: GraphicsContext, size: CGSize, index: Int, count: Int) {
        let beat = time > 0 ? channel.danceBeat : 0
        let offset = count == 1 ? 0 : Double((index * 3 + (side == .right ? 2 : 0)) % 8) / 8
        let stepBeat = beat + offset
        let phase = (stepBeat - floor(stepBeat)) * 2 * .pi
        let variation = time > 0 ? sin(beat * .pi / 4 + Double(index) * 1.7) : 0
        let emote = relaxedDance == .standing
        let slowdance = relaxedDance == .slowdance
        let activity = time > 0 ? min(1, Double(channel.level) * 4 + channel.danceEnergy * 0.45) : 0
        let routine = index + (side == .right ? 5 : 0)
        let groove = time > 0 ? beat * 2 * .pi + Double(routine) * 0.72 : 0
        let slowPhase = beat * .pi + offset * .pi
        let slowRock = sin(slowPhase)
        let slowStep = cos(slowPhase)
        let rock = sin(groove)
        let bounce = pow(sin(groove), 2)
        let headbang = relaxedDance == .headbang && time > 0
        let energy = emote || slowdance ? 0 : headbang ? 0.10 + channel.danceEnergy * 0.27 : channel.danceEnergy
        let martial: Double = relaxedDance == .martialArts ? 1 : 0
        func quietPose(_ standing: Double, _ guardPose: Double) -> Double {
            standing + (guardPose - standing) * martial
        }
        let breath = sin(time * 1.65 + Double(index) * 0.7)
        let formPhase = time * 0.93 + offset * 2 * .pi
        let slowSway = sin(formPhase)
        func blend(_ relaxed: Double, _ party: Double) -> Double {
            relaxed + (party - relaxed) * energy
        }
        let sway = sin(phase) * (0.82 + variation * 0.18)
        let step = sin(phase - 0.65 - Double(index % 3) * 0.55)
        let dip = 0.5 + 0.5 * cos(phase * 2)
        let slotWidth = max(1, size.width - innerInset - 4) / Double(count)
        let unit = min(size.height * 0.94, slotWidth / 1.25)
        let centerX = x((Double(index) + 0.5) / Double(count), size: size)
        let top = (size.height - unit) / 2
        let direction: Double = side == .left ? -1 : 1
        func point(_ px: Double, _ py: Double) -> CGPoint {
            CGPoint(x: centerX + px * unit * direction, y: top + py * unit)
        }

        func danceMix(_ idle: Double, _ move: Double) -> Double {
            idle + (move - idle) * activity
        }

        // Shift weight over each bent knee while the forearms sweep across the chest.
        let hipX = emote ? danceMix(breath * 0.018, rock * 0.15) : slowdance ? danceMix(breath * 0.018, slowRock * 0.09) : blend(quietPose(breath * 0.018, slowSway * 0.12), sway * 0.19)
        let shoulderX = emote ? danceMix(breath * 0.026, -rock * 0.16) : slowdance ? danceMix(breath * 0.026, slowRock * 0.12) : blend(quietPose(breath * 0.026, slowSway * 0.09), sway * 0.12)
        let crouch = emote ? danceMix(breath * 0.018, 0.025 - bounce * 0.11) : slowdance ? danceMix(breath * 0.018, slowStep * 0.028) : blend(quietPose(breath * 0.018, 0.075 + abs(slowSway) * 0.075), dip * 0.13)
        let headbangEnergy = min(1, Double(channel.level) * 8)
        let idleNod = (0.5 - 0.5 * cos(time * 3.7 + offset * 2 * .pi)) * 0.13
        let liveNod = (0.5 - 0.5 * cos(phase * 2)) * (0.31 + channel.danceEnergy * 0.10)
        let nod = headbang ? idleNod + (liveNod - idleNod) * headbangEnergy * 0.20 : 0
        let lean = headbang ? 0.025 + nod * 0.72 : 0
        let neck = point(shoulderX + lean, 0.29 + crouch + nod * 0.54)
        let hip = point(hipX, 0.60 + crouch + nod * 0.26)
        var skeleton = Path()
        skeleton.move(to: neck)
        skeleton.addLine(to: hip)
        for sign in [-1.0, 1.0] {
            let reach = max(0, sign * sway)
            let cross = max(0, -sign * sway)
            let shoulder = point(shoulderX + sign * 0.07, 0.32 + crouch)
            skeleton.move(to: neck)
            skeleton.addLine(to: shoulder)
            let armSweep = sin(formPhase + sign * 0.9)
            let armAngle = -0.45 - armSweep * 1.30
            let forearmAngle = armAngle - 0.68 + cos(formPhase + sign) * 0.53
            let formElbowX = sign * (0.07 + cos(armAngle) * 0.21)
            let formElbowY = 0.32 + sin(armAngle) * 0.21
            let formHandX = formElbowX + sign * cos(forearmAngle) * 0.20
            let formHandY = max(0.035 - crouch, formElbowY + sin(forearmAngle) * 0.20)
            let arm = sign * rock
            let liftBeat = max(0, sign * sin(groove + Double(routine) * 0.31))
            let pose: (Double, Double, Double, Double, Double, Double)
            switch routine {
            case 0: pose = (0.34, 0.39 + arm * 0.10, sign * 0.12, 0.24 - arm * 0.12, 0.22, liftBeat * 0.15)
            case 1: pose = (0.21, 0.43, sign * 0.10 + rock * 0.28, 0.50 - arm * 0.12, 0.28, bounce * 0.05)
            case 2: pose = (0.24, 0.33 - arm * 0.14, sign * 0.28, 0.23 - arm * 0.19, 0.21, liftBeat * 0.11)
            case 3: pose = (0.27, 0.46, sign * 0.35, 0.43 + arm * 0.08, 0.30, liftBeat * 0.23)
            case 4: pose = (0.16, 0.39, rock * 0.28, 0.32 + arm * 0.14, 0.33, liftBeat * 0.06)
            case 5: pose = (0.30, 0.30 + arm * 0.13, sign * 0.31 + rock * 0.06, 0.39 - arm * 0.17, 0.26, bounce * 0.09)
            case 6: pose = (0.20, 0.49 - arm * 0.12, sign * 0.36, 0.30 + arm * 0.19, 0.19, liftBeat * 0.19)
            case 7: pose = (0.28, 0.34, sign * 0.08 + rock * 0.19, 0.20 + arm * 0.15, 0.29, liftBeat * 0.08)
            case 8: pose = (0.17, 0.46 + arm * 0.10, sign * 0.19, 0.59 - arm * 0.19, 0.34, liftBeat * 0.16)
            default: pose = (0.32, 0.41 - arm * 0.09, sign * 0.26 + rock * 0.11, 0.42 - bounce * 0.25, 0.24, liftBeat * 0.10)
            }
            let elbowX = emote ? danceMix(sign * 0.12, sign * pose.0) : slowdance ? danceMix(sign * 0.12, sign * 0.20 + slowRock * 0.05) : blend(quietPose(sign * 0.12, formElbowX), sign * (0.23 + reach * 0.09))
            let elbowY = emote ? danceMix(0.49, pose.1) : slowdance ? danceMix(0.49, 0.40 - sign * slowRock * 0.04) : blend(quietPose(0.49, formElbowY), 0.47 - reach * 0.16)
            let pump = headbang ? (0.5 + 0.5 * cos(phase + sign * .pi / 2)) * headbangEnergy * 0.40 : 0
            skeleton.addLine(to: point(shoulderX + elbowX + sign * pump * 0.08,
                                       elbowY + crouch - pump * 0.12))
            let handX = emote ? danceMix(sign * 0.13, pose.2) : slowdance ? danceMix(sign * 0.13, sign * 0.16 + slowRock * 0.12) : blend(quietPose(sign * 0.13, formHandX), sign * (0.09 + reach * 0.37 - cross * 0.27))
            let handY = emote ? danceMix(0.64, pose.3) : slowdance ? danceMix(0.64, 0.33 + sign * slowStep * 0.065) : blend(quietPose(0.64, formHandY), 0.35 - reach * (0.28 + variation * 0.10) + dip * 0.16)
            skeleton.addLine(to: point(shoulderX + handX + sign * pump * 0.08, handY + crouch - pump * 0.24))
            skeleton.move(to: hip)
            let kneeSpread = emote ? danceMix(0.13, pose.4 * 0.72) : slowdance ? danceMix(0.13, 0.18) : blend(quietPose(0.13, 0.27), 0.25 + dip * 0.04)
            let kneeY = blend(0.77, 0.76 + reach * 0.10) + (headbang ? nod * 0.08 : 0)
            skeleton.addLine(to: point(sign * kneeSpread + hipX * 0.45, kneeY))
            let lift = emote ? pose.5 * activity : slowdance ? max(0, sign * slowRock) * activity * 0.055 : max(0, sign * step) * (0.11 + variation * 0.06) * energy
            let stance = emote ? danceMix(0.15, pose.4) : slowdance ? danceMix(0.15, 0.21 + sign * slowRock * 0.045) : blend(quietPose(0.15, 0.34), 0.31)
            let foot = point(sign * (stance - lift * 0.5), 0.94 - lift)
            skeleton.addLine(to: foot)
            skeleton.addLine(to: point(sign * (stance + 0.06 - lift * 0.5), 0.94 - lift))
        }
        let headCenter = point(shoulderX - sway * 0.04 + lean * 1.55, 0.16 + crouch + nod)
        let radius = unit * 0.095
        let head = Path(ellipseIn: CGRect(x: headCenter.x - radius, y: headCenter.y - radius,
                                         width: radius * 2, height: radius * 2))
        let stroke = StrokeStyle(lineWidth: max(0.8, unit * 0.045), lineCap: .round, lineJoin: .round)
        context.stroke(skeleton, with: .linearGradient(Gradient(colors: palette.colors),
                       startPoint: point(0, 0.25), endPoint: point(0, 0.94)), style: stroke)
        context.stroke(head, with: .color(palette.highlight), style: stroke)
        if dancerSparks && time > 0 && (!(emote || slowdance) || activity > 0.02) {
            let beatsPerSecond = 1 / max(0.25, channel.beatDuration)
            let speed = headbang ? (0.32 + headbangEnergy * beatsPerSecond * 0.28)
                                 : 0.16 + (emote ? activity * 0.65 : slowdance ? activity * 0.20 : energy) * beatsPerSecond * 0.25
            let intensity = min(1, speed)
            let sparkleCount = 2 + Int(intensity * (lowPower ? 3 : 6))
            for spark in 0..<sparkleCount {
                let seed = Double(spark) * 0.618 + offset
                let cycle = time * (0.9 + intensity * 1.9) + seed
                let age = cycle - floor(cycle)
                let angle = seed * 2 * .pi
                let center = point(cos(angle) * (0.31 + age * 0.22),
                                   0.52 + sin(angle) * (0.16 + age * 0.21))
                let radius = max(0.45, unit * (0.018 + intensity * 0.022))
                let fade = sin(age * .pi) * (0.30 + intensity * 0.65)
                var glint = Path()
                glint.move(to: CGPoint(x: center.x - radius, y: center.y))
                glint.addLine(to: CGPoint(x: center.x + radius, y: center.y))
                glint.move(to: CGPoint(x: center.x, y: center.y - radius))
                glint.addLine(to: CGPoint(x: center.x, y: center.y + radius))
                context.stroke(glint, with: .color(palette.highlight.opacity(fade)),
                               style: StrokeStyle(lineWidth: max(0.55, radius * 0.45), lineCap: .round))
            }
        }
    }

    private func drawMusicEffect(in context: GraphicsContext, size: CGSize, phase: Double) {
        let colors = palette.colors
        let level = Double(channel.level)
        let height = size.height
        switch style {
        case .equalizer:
            let barWidth = max(0.7, (size.width - innerInset - 4) / 24)
            for index in 0..<16 {
                let band = sqrt(Double(channel.spectrum[index]))
                let barHeight = height * (0.09 + band * 0.76)
                let center = x((Double(index) + 0.5) / 16, size: size)
                let rect = CGRect(x: center - barWidth / 2, y: (height - barHeight) / 2,
                                  width: barWidth, height: barHeight)
                context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2),
                             with: .color(colors[index % colors.count].opacity(0.48 + band * 0.52)))
            }
        case .arcade:
            let columns = lowPower ? 24 : 36
            let rows = 7
            let cellWidth = max(1, size.width - innerInset - 4) / Double(columns)
            let cellHeight = height / Double(rows)
            let impact = Double(channel.impact)
            let beatFlash = impact > 0.28
            let travel = Int(floor(phase * 12))
            for column in 0..<columns {
                let progress = (Double(column) + 0.5) / Double(columns)
                let center = x(progress, size: size)
                let sample = min(31, column * 32 / columns)
                let band = Double(channel.bands[column * 16 / columns])
                let waveform = Double(channel.waveform.high[sample] + channel.waveform.low[sample])
                let motion = sin(progress * 4 * .pi - phase * 5)
                let step = waveform * 4 + motion * (0.6 + band * 1.7)
                let row = min(5, max(1, 3 + Int(step.rounded())))
                let tint = colors[(column / 4) % colors.count]
                func pixel(_ row: Int, _ color: Color) {
                    let rect = CGRect(x: center - cellWidth * 0.43,
                                      y: (Double(row) + 0.09) * cellHeight,
                                      width: cellWidth * 0.86, height: cellHeight * 0.82)
                    context.fill(Path(rect), with: .color(color))
                }
                for connector in min(row, 3)...max(row, 3) {
                    pixel(connector, tint.opacity(0.22 + band * 0.46))
                }
                pixel(row, tint.opacity(min(1, 0.70 + level * 0.3 + impact * 0.25)))
                if (column - travel).isMultiple(of: 9) {
                    pixel(row, palette.highlight)
                    if beatFlash {
                        pixel(max(0, row - 2), palette.highlight.opacity(0.74))
                        pixel(min(6, row + 2), tint.opacity(0.75))
                    }
                }
            }
        case .pulse:
            let bass = Double(channel.bass)
            let impact = Double(channel.impact)
            let count = lowPower ? 5 : 9
            for index in 0..<count {
                let cycle = phase * 0.35 + Double(index) / Double(count)
                let u = cycle - floor(cycle)
                let fade = sin(u * .pi)
                let band = Double(channel.bands[index % 16])
                let extent = height * min(0.48, 0.20 + bass * 0.23 + band * 0.12 + impact * 0.13)
                let middle = height / 2
                let curve = min(0.11, u * 0.8)
                var wave = Path()
                wave.move(to: CGPoint(x: x(u - curve, size: size), y: middle - extent))
                wave.addQuadCurve(to: CGPoint(x: x(u - curve, size: size), y: middle + extent),
                                  control: CGPoint(x: x(min(1, u + curve), size: size), y: middle))
                let color = colors[index % colors.count]
                let strength = fade * min(1, 0.65 + level * 0.45 + impact * 0.30)
                context.stroke(wave, with: .color(color.opacity(strength * 0.25)),
                               style: StrokeStyle(lineWidth: height * 0.28, lineCap: .round))
                context.stroke(wave, with: .color(color.opacity(strength)),
                               style: StrokeStyle(lineWidth: max(1, height * 0.09), lineCap: .round))
                context.stroke(wave, with: .color(palette.highlight.opacity(strength * 0.72)),
                               style: StrokeStyle(lineWidth: max(0.65, height * 0.034), lineCap: .round))
            }
        default:
            break
        }
    }

    private func drawSplash(in context: GraphicsContext, size: CGSize, phase: Double) {
        let count = Int(Double(lowPower ? 8 : 17) * splashDensity)
        let level = Double(channel.level)
        let impact = Double(channel.impact)
        let base = size.height * 0.86
        let span = max(1, size.width - innerInset - 4)
        let colors = palette.colors
        for index in 0..<count {
            let seed = Double(index) * 0.61803398875
            let cycle = phase * (1.1 + Double(index % 4) * 0.18) + seed
            let age = cycle - floor(cycle)
            let spread = sin(seed * 13)
            let origin = x((Double(index) + 0.5) / Double(count), size: size)
            let peak = size.height * min(0.79, 0.20 + level * 0.37 + impact * 0.24
                                        + Double(channel.bands[index % 16]) * 0.16)
            func point(_ t: Double) -> CGPoint {
                CGPoint(x: origin + spread * span * 0.13 * t,
                        y: base - peak * 4 * t * (1 - t))
            }

            let head = point(age)
            let tailAge = max(0, age - 0.25)
            let tail = point(tailAge)
            let midpoint = point((age + tailAge) * 0.5)
            let control = CGPoint(x: 2 * midpoint.x - (tail.x + head.x) / 2,
                                  y: 2 * midpoint.y - (tail.y + head.y) / 2)
            var jet = Path()
            jet.move(to: tail)
            jet.addQuadCurve(to: head, control: control)
            let fade = sin(age * .pi)
            let tint = colors[index % colors.count]
            let radius = max(0.5, min(size.height, size.width) * (0.023 + level * 0.012))
            if age > 0.001 {
                context.stroke(jet, with: .linearGradient(
                    Gradient(colors: [tint.opacity(0.06), tint.opacity(fade * 0.85)]),
                    startPoint: tail, endPoint: head),
                    style: StrokeStyle(lineWidth: radius * 1.6, lineCap: .round))
            }
            for spray in 0..<(lowPower ? 1 : 3) {
                let offset = Double(spray)
                let drop = CGRect(x: head.x + offset * spread * radius * 2.8 - radius,
                                  y: head.y + offset * radius * 2 - radius,
                                  width: radius * (2 - offset * 0.4),
                                  height: radius * (2 - offset * 0.4))
                context.fill(Path(ellipseIn: drop),
                             with: .color(palette.highlight.opacity(fade * (0.95 - offset * 0.21))))
            }
        }
    }

    private func drawFromNotch(in context: GraphicsContext, size: CGSize, phase: Double) {
        let availableWidth = max(1, size.width - innerInset - 4)
        let renderer = VisualizerTrail(style: style, channel: channel, time: time, palette: palette,
                                      side: .right, mirrored: mirrored, lowPower: lowPower, innerInset: 0, splashDensity: splashDensity)
        if style == .splash {
            var rotated = context
            if side == .left {
                rotated.translateBy(x: size.width - innerInset, y: 0)
                rotated.scaleBy(x: -1, y: 1)
            } else {
                rotated.translateBy(x: innerInset, y: 0)
            }
            rotated.concatenate(CGAffineTransform(a: 0, b: 1, c: -1, d: 0,
                                                  tx: availableWidth * 0.86, ty: 0))
            renderer.drawSplash(in: rotated, size: CGSize(width: size.height, height: availableWidth),
                                phase: phase)
        } else {
            // Mirror the same flame field around one shared base so both halves
            // remain visible in the available lane beside the physical cutout.
            let halfWidth = availableWidth / 2
            let baseX = size.width / 2
            let field = CGSize(width: size.height, height: halfWidth)
            for direction in [-1.0, 1.0] {
                var flame = context
                flame.translateBy(x: baseX, y: 0)
                flame.scaleBy(x: direction, y: 1)
                let root = CGRect(x: 0, y: size.height * 0.20,
                                  width: min(6, halfWidth * 0.12), height: size.height * 0.60)
                flame.fill(Path(root), with: .linearGradient(
                    Gradient(colors: [palette.primary.opacity(0.58), .clear]),
                    startPoint: .zero, endPoint: CGPoint(x: root.width, y: 0)))
                flame.concatenate(CGAffineTransform(a: 0, b: 1, c: -1, d: 0,
                                                     tx: halfWidth * 0.86, ty: 0))
                renderer.drawFire(in: flame, size: field, phase: phase)
            }
        }
    }

    private func drawFire(in context: GraphicsContext, size: CGSize, phase: Double) {
        let level = Double(channel.level)
        let impact = Double(channel.impact)
        let count = lowPower ? 14 : 32
        let baseline = size.height * 0.86
        for index in 0..<count {
            let progress = (Double(index) + 0.5) / Double(count)
            let seed = Double(index) * 2.39996
            let band = Double(channel.bands[index % 16])
            let flicker = 0.65 + 0.22 * sin(phase * 8 + seed) + 0.13 * sin(phase * 13 + seed * 2)
            let taper = pow(sin(progress * .pi), 0.45)
            let height = size.height * min(0.85, (0.18 + level * 0.46 + band * 0.23 + impact * 0.22) * flicker * taper)
            let centerX = x(progress, size: size)
            let halfWidth = max(1, size.width / Double(count) * 1.15)
            let lean = sin(phase * 4 + seed) * halfWidth * 0.8
            var flame = Path()
            flame.move(to: CGPoint(x: centerX - halfWidth, y: baseline))
            flame.addQuadCurve(to: CGPoint(x: centerX + lean, y: baseline - height),
                               control: CGPoint(x: centerX - halfWidth * 0.8, y: baseline - height * 0.55))
            flame.addQuadCurve(to: CGPoint(x: centerX + halfWidth, y: baseline),
                               control: CGPoint(x: centerX + halfWidth * 0.6 + lean, y: baseline - height * 0.35))
            flame.closeSubpath()
            context.fill(flame, with: .linearGradient(
                Gradient(colors: [palette.highlight.opacity(0.75), palette.primary.opacity(0.65),
                                  palette.secondary.opacity(0.05)]),
                startPoint: CGPoint(x: centerX, y: baseline),
                endPoint: CGPoint(x: centerX + lean, y: baseline - height)))
            if !lowPower && index.isMultiple(of: 3) {
                let cycle = phase * 0.65 + seed
                let age = cycle - floor(cycle)
                let radius = max(0.5, size.height * 0.022)
                let spark = CGRect(x: centerX + sin(seed + age * 4) * halfWidth,
                                   y: baseline - age * size.height * 0.8,
                                   width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: spark),
                             with: .color(palette.colors[index % 3].opacity(sin(age * .pi) * (level + impact) * 0.6)))
            }
        }
    }
}
