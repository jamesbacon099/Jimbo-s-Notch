import SwiftUI

enum RelaxedDance: String, CaseIterable {
    case standing = "Default"
    case idle = "Standing"
    case martialArts = "Martial arts"
    case headbang = "Tweakers"
    case raveHeadbang = "Rave headbang"
    case slowdance = "Slowdancing"
    case random = "Random"

    private static let shuffledRoutines = allCases.filter { $0 != .random }.shuffled()

    func routine(for index: Int, side: TrailSide) -> Self {
        guard self == .random else { return self }
        // Alternate sides so the first pair already gets two different styles.
        let slot = index * 2 + (side == .right ? 1 : 0)
        return Self.shuffledRoutines[slot % Self.shuffledRoutines.count]
    }
}

struct PlasmaSparks {
    var size = 1.0
    var density = 1.0
}

struct EffectMotion {
    var speed = 1.0
    var density = 1.0
    var reversed = false
    var waveDepth = 1.0
    var silkDetail = 0.8
}

enum VisualizerMode: String, CaseIterable {
    case single = "Single"
    case randomizer = "Randomizer"
    case combine = "Combine"
}

enum VisualizerStyle: String, CaseIterable, Identifiable {
    case classic = "Default"
    case silk = "Silk Ribbons"
    case electricMesh = "Electric Mesh"
    case dancers = "Dancers"
    case fire = "Fire"
    case splash = "Splash"
    case equalizer = "Equalizer"
    case arcade = "Arcade"
    case pulse = "Pulse"
    case laser = "Laser"
    case rainfall = "Rainfall"
    case ripple = "Ripple"
    case meteor = "Meteor"
    case vortex = "Vortex"
    case circuit = "Circuit"
    case synthGrid = "Synth Grid"
    case cityLights = "City Lights"

    var id: String { rawValue }
    var displayName: String { self == .fire ? "Plasma" : rawValue }

    var hasDensityAndDirection: Bool {
        [.meteor, .vortex, .circuit, .synthGrid, .cityLights].contains(self)
    }

    var hasSpeed: Bool {
        shapeControls != nil || hasDensityAndDirection || [.fire, .splash, .pulse, .laser, .rainfall, .ripple].contains(self)
    }

    var shapeControls: (spacing: String, depth: String)? {
        switch self {
        case .silk: return ("Twist spacing", "Ribbon spread")
        case .electricMesh: return ("Mesh density", "Peak height")
        default: return nil
        }
    }

    var summary: String {
        switch self {
        case .classic: return "Flowing waveforms, ribbons, and sparkling trails."
        case .silk: return "Translucent ribbons twist around a shared centerline."
        case .electricMesh: return "A tilted wireframe spins around an electric burst, with peaks driven by the spectrum."
        case .dancers: return "Stickmen sway to softer music and break into bigger moves as the drums pick up."
        case .splash: return "Water jets and droplets splash with the beat."
        case .equalizer: return "Bars show the energy in each frequency band."
        case .arcade: return "A chunky pixel waveform and bursts react to the beat."
        case .laser: return "Neon beams sweep and fan out with the beat."
        case .rainfall: return "Digital rain falls in colored streaks."
        case .ripple: return "Glowing rings spread from the notch."
        case .pulse: return "Bright waves roll outward from the notch."
        case .meteor: return "Bright meteor heads pull long streaks across the trail."
        case .vortex: return "Two neon strands twist around each other."
        case .circuit: return "Layered circuit traces light up as signals run along them."
        case .synthGrid: return "Audio lifts the lines of a scrolling neon grid."
        case .cityLights: return "A scrolling skyline lights up with the music."
        case .fire: return "Plasma streams and sparks react to the beat."
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
    var dancerThickness = 1.0
    var rainfallFromNotch = false
    var rainfallDensity = 1.0
    var laserThickness = 1.0
    var effectMotion = EffectMotion()
    var plasmaSparks = PlasmaSparks()

    var body: some View {
        if glassFade {
            coloredArtwork.mask {
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.85),
                    .init(color: .clear, location: 1)
                ], startPoint: side == .left ? .trailing : .leading,
                   endPoint: side == .left ? .leading : .trailing)
            }
        } else {
            coloredArtwork
        }
    }

    @ViewBuilder
    private var coloredArtwork: some View {
        if let gradient = palette.coverGradient {
            LinearGradient(gradient: gradient,
                           startPoint: side == .left ? .trailing : .leading,
                           endPoint: side == .left ? .leading : .trailing)
                .mask { artwork }
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
                let phase = (time * effectMotion.speed).truncatingRemainder(dividingBy: 120)
                    + (mirrored || side == .left ? 0 : 7.3)
                if style == .dancers {
                    let count = min(5, max(1, dancersPerSide))
                    for index in 0..<count {
                        drawDancer(in: context, size: size, index: index, count: count)
                    }
                } else if style.shapeControls != nil {
                    let waveTime = time * effectMotion.speed + (mirrored || side == .left ? 0 : 1.1)
                    switch style {
                    case .silk: drawSilk(in: context, size: size, time: waveTime)
                    case .electricMesh: drawElectricMesh(in: context, size: size, time: waveTime)
                    default: break
                    }
                } else if style.hasDensityAndDirection {
                    let travel = effectMotion.reversed ? -phase : phase
                    drawMotionEffect(in: context, size: size, phase: travel)
                } else if [.equalizer, .arcade, .pulse, .laser, .rainfall, .ripple].contains(style) {
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

    func x(_ progress: Double, size: CGSize) -> CGFloat {
        let distance = innerInset + progress * max(0, size.width - innerInset - 4)
        return side == .left ? size.width - distance : distance
    }

    private func drawDancer(in context: GraphicsContext, size: CGSize, index: Int, count: Int) {
        let beat = time > 0 ? channel.danceBeat : 0
        let offset = count == 1 ? 0 : Double((index * 3 + (side == .right ? 2 : 0)) % 8) / 8
        let stepBeat = beat + offset
        let phase = (stepBeat - floor(stepBeat)) * 2 * .pi
        let variation = time > 0 ? sin(beat * .pi / 4 + Double(index) * 1.7) : 0
        let dance = relaxedDance.routine(for: index, side: side)
        let emote = dance == .standing
        let slowdance = dance == .slowdance
        let activity = time > 0 ? min(1, Double(channel.level) * 4 + channel.danceEnergy * 0.45) : 0
        let routine = index + (side == .right ? 5 : 0)
        let groove = time > 0 ? beat * 2 * .pi + Double(routine) * 0.72 : 0
        let slowPhase = beat * .pi + offset * .pi
        let slowRock = sin(slowPhase)
        let slowStep = cos(slowPhase)
        let rock = sin(groove)
        let bounce = pow(sin(groove), 2)
        let standing = dance == .idle
        let classicRave = dance == .raveHeadbang
        let headbang = (dance == .headbang || classicRave) && time > 0
        let energy = emote || slowdance ? 0
            : headbang ? (classicRave ? channel.danceEnergy * 0.16 : 0.10 + channel.danceEnergy * 0.27)
            : channel.danceEnergy
        let martial: Double = dance == .martialArts ? 1 : 0
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
        let idleNod = (0.5 - 0.5 * cos(time * (classicRave ? 2.1 : 3.7) + offset * 2 * .pi))
            * (classicRave ? 0.08 : 0.13)
        let liveNod = (0.5 - 0.5 * cos(phase * (classicRave ? 1 : 2)))
            * (classicRave ? 0.24 : 0.31 + channel.danceEnergy * 0.10)
        let nod = headbang ? idleNod + (liveNod - idleNod) * headbangEnergy * (classicRave ? 0.7 : 0.20) : 0
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
            let pump = headbang ? (0.5 + 0.5 * cos(phase + sign * .pi / 2)) * headbangEnergy * (classicRave ? 0.18 : 0.40) : 0
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
        let stroke = StrokeStyle(lineWidth: max(0.55, max(0.8, unit * 0.045) * dancerThickness), lineCap: .round, lineJoin: .round)
        context.stroke(skeleton, with: .linearGradient(Gradient(colors: palette.colors),
                       startPoint: point(0, 0.25), endPoint: point(0, 0.94)), style: stroke)
        context.fill(head, with: .color(palette.highlight))
        if dancerSparks && time > 0 && !standing && (!(emote || slowdance) || activity > 0.02) {
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
        case .laser:
            let thickness = laserThickness
            let impact = Double(channel.impact)
            let extra = Int(max(0, 1 - thickness) * 9)
            let count = lowPower ? 4 + extra / 2 : 8 + extra
            let origin = CGPoint(x: x(0, size: size), y: height / 2)
            for beam in 0..<count {
                let band = Double(channel.bands[beam * 16 / count])
                let spread = sin(phase * 3 + Double(beam) * 0.85)
                let end = CGPoint(x: x(0.64 + band * 0.32, size: size),
                                  y: height * (0.5 + spread * (0.17 + impact * 0.24)))
                let color = colors[beam % colors.count]
                var ray = Path()
                ray.move(to: origin)
                ray.addLine(to: end)
                context.stroke(ray, with: .color(color.opacity(0.18 + band * 0.24)),
                               style: StrokeStyle(lineWidth: height * 0.18 * thickness, lineCap: .round))
                context.stroke(ray, with: .linearGradient(
                    Gradient(colors: [palette.highlight, color.opacity(0.12)]),
                    startPoint: origin, endPoint: end),
                    style: StrokeStyle(lineWidth: max(0.45, height * 0.055 * thickness), lineCap: .round))
            }
        case .rainfall:
            if rainfallFromNotch {
                var outward = context
                outward.translateBy(x: x(0, size: size), y: 0)
                outward.concatenate(CGAffineTransform(a: 0, b: 1, c: side == .left ? -1 : 1,
                                                       d: 0, tx: 0, ty: 0))
                drawRain(in: outward, size: CGSize(width: height, height: max(1, size.width - innerInset)),
                         phase: phase, orientedOutward: true)
            } else {
                drawRain(in: context, size: size, phase: phase, orientedOutward: false)
            }
        case .ripple:
            let count = lowPower ? 5 : 9
            let impact = Double(channel.impact)
            for ring in 0..<count {
                let cycle = phase * 0.60 + Double(ring) / Double(count)
                let age = cycle - floor(cycle)
                let center = x(0.04 + age * 0.86, size: size)
                let radius = height * (0.05 + age * (0.30 + impact * 0.12))
                let rect = CGRect(x: center - radius * 1.8, y: height / 2 - radius,
                                  width: radius * 3.6, height: radius * 2)
                let opacity = sin(age * .pi) * (0.60 + level * 0.40)
                let color = colors[ring % colors.count]
                let ringPath = Path(ellipseIn: rect)
                context.stroke(ringPath, with: .color(color.opacity(opacity * 0.24)),
                               style: StrokeStyle(lineWidth: max(2, height * 0.19)))
                context.stroke(ringPath, with: .color(color.opacity(opacity)),
                               style: StrokeStyle(lineWidth: max(0.8, height * 0.065)))
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

    private func drawMotionEffect(in context: GraphicsContext, size: CGSize, phase: Double) {
        let colors = palette.colors
        let height = size.height
        let level = Double(channel.level)
        let impact = Double(channel.impact)
        let count = Int(Double(lowPower ? 9 : 17) * effectMotion.density)
        if style == .vortex {
            let segments = count * 4
            for strand in [-1.0, 1.0] {
                var ribbon = Path()
                for index in 0...segments {
                    let u = Double(index) / Double(segments)
                    let wave = sin(u * (4 + effectMotion.density * 2) * .pi - phase * 4)
                    let amplitude = sin(u * .pi) * (0.20 + level * 0.21)
                    let point = CGPoint(x: x(u, size: size), y: height * (0.5 + strand * wave * amplitude))
                    if index == 0 { ribbon.move(to: point) } else { ribbon.addLine(to: point) }
                }
                let tint = strand < 0 ? palette.primary : palette.secondary
                context.stroke(ribbon, with: .color(tint.opacity(0.24)),
                               style: StrokeStyle(lineWidth: height * 0.18, lineCap: .round, lineJoin: .round))
                context.stroke(ribbon, with: .linearGradient(
                    Gradient(colors: [tint.opacity(0.35), tint, palette.highlight, tint.opacity(0.45)]),
                    startPoint: CGPoint(x: x(0, size: size), y: 0),
                    endPoint: CGPoint(x: x(1, size: size), y: 0)),
                    style: StrokeStyle(lineWidth: max(1, height * 0.045), lineCap: .round, lineJoin: .round))
            }
            return
        }
        for index in 0..<count {
            let offset = Double(index) / Double(count)
            let band = Double(channel.bands[index * 16 / count])
            let cycle = phase * (style == .synthGrid ? 0.45 : 0.75) + offset
            let age = cycle - floor(cycle)
            let fade = sin(age * .pi)
            let color = colors[index % colors.count]
            let middle = height / 2
            let center = CGPoint(x: x(age, size: size), y: middle)
            switch style {
            case .meteor:
                let y = middle + sin(Double(index) * 2.4) * height * 0.29
                let tail = CGPoint(x: x(max(0, age - 0.11 - band * 0.14), size: size), y: y + height * 0.09)
                let tip = CGPoint(x: center.x, y: y)
                var streak = Path()
                streak.move(to: tail)
                streak.addLine(to: tip)
                context.stroke(streak, with: .linearGradient(
                    Gradient(colors: [.clear, color.opacity(fade), palette.highlight.opacity(fade)]),
                    startPoint: tail, endPoint: tip),
                    style: StrokeStyle(lineWidth: max(0.9, height * (0.045 + impact * 0.07)), lineCap: .round))
            case .circuit:
                let row = Double(index % 7) - 3
                let start = Double(index / 7) / ceil(Double(count) / 7)
                let end = min(1, start + 0.30)
                let y = middle + row * height * 0.106
                let turnY = y + (row < 0 ? -1 : 1) * height * 0.065
                var trace = Path()
                trace.move(to: CGPoint(x: x(start, size: size), y: middle))
                trace.addLine(to: CGPoint(x: x(min(end, start + 0.035), size: size), y: y))
                trace.addLine(to: CGPoint(x: x(max(start, end - 0.07), size: size), y: y))
                trace.addLine(to: CGPoint(x: x(end, size: size), y: turnY))
                let width = max(0.65, height * (0.025 + band * 0.024))
                context.stroke(trace, with: .color(color.opacity(0.52 + band * 0.32)),
                               style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                let signal = start + age * (end - start)
                let traceY: CGFloat
                if signal < start + 0.035 {
                    traceY = middle + (y - middle) * (signal - start) / 0.035
                } else if signal > end - 0.07 {
                    traceY = y + (turnY - y) * (signal - (end - 0.07)) / 0.07
                } else {
                    traceY = y
                }
                let sx = x(signal, size: size)
                let pad = CGRect(x: sx - width * 2, y: traceY - width, width: width * 4, height: width * 2)
                context.fill(Path(roundedRect: pad, cornerRadius: width),
                             with: .color(palette.highlight.opacity(fade * (0.65 + impact * 0.35))))
            case .synthGrid:
                let depth = 0.11 + band * 0.28
                var cell = Path()
                cell.move(to: CGPoint(x: center.x, y: middle - height * depth))
                cell.addLine(to: CGPoint(x: center.x, y: middle + height * depth))
                for sign in [-1.0, 1.0] {
                    let y = middle + sign * height * depth
                    cell.move(to: CGPoint(x: center.x, y: y))
                    cell.addLine(to: CGPoint(x: x(min(1, age + 1.0 / Double(count)), size: size),
                                             y: y + sign * height * 0.07))
                }
                context.stroke(cell, with: .color(color.opacity(fade * (0.53 + band * 0.47))),
                               style: StrokeStyle(lineWidth: max(0.8, height * 0.045), lineCap: .round))
            case .cityLights:
                let street = height * 0.82
                let shape = 0.5 + 0.5 * sin(Double(index) * 2.39)
                let buildingHeight = height * (0.18 + shape * 0.28 + band * 0.24 + impact * 0.10)
                let width = max(1.5, (size.width - innerInset - 4) / Double(count) * 0.83)
                let tower = CGRect(x: center.x - width / 2, y: street - buildingHeight,
                                   width: width, height: buildingHeight)
                var building = Path()
                building.addRect(tower)
                if index.isMultiple(of: 3) {
                    building.addRect(CGRect(x: tower.midX - width * 0.21, y: tower.minY - height * 0.07,
                                            width: width * 0.42, height: height * 0.07))
                }
                context.fill(building, with: .linearGradient(
                    Gradient(colors: [color.opacity(fade * 0.8), color.opacity(fade * 0.20)]),
                    startPoint: CGPoint(x: center.x, y: tower.minY),
                    endPoint: CGPoint(x: center.x, y: street)))
                context.stroke(building, with: .color(color.opacity(fade * 0.65)),
                               style: StrokeStyle(lineWidth: max(0.5, height * 0.017)))
                for row in 0..<(lowPower ? 3 : 5) {
                    let flicker = 0.5 + 0.5 * sin(phase * 3 + Double(row * 7 + index))
                    let lit = flicker + band + impact > 0.56
                    let y = tower.minY + buildingHeight * (0.14 + Double(row) * 0.15)
                    let pane = CGRect(x: tower.midX - width * 0.29, y: y,
                                      width: width * 0.58, height: max(0.5, buildingHeight * 0.065))
                    context.fill(Path(pane), with: .color(palette.highlight.opacity(fade * (lit ? 0.82 : 0.14))))
                }
            default:
                break
            }
        }
    }

    private func drawRain(in context: GraphicsContext, size: CGSize, phase: Double, orientedOutward: Bool) {
        let count = Int(Double(lowPower ? 15 : 29) * rainfallDensity)
        let colors = palette.colors
        for column in 0..<count {
            let band = Double(channel.bands[column * 16 / count])
            let seed = Double(column) * 0.618
            let cycle = phase * (0.65 + Double(column % 5) * 0.14) + seed
            let age = cycle - floor(cycle)
            let position = (Double(column) + 0.5) / Double(count)
            let length = size.height * (0.18 + band * 0.50)
            let tip = age * (size.height + length)
            let width = max(0.6, min(3, size.width / Double(count) * 0.55))
            let center = orientedOutward ? size.width * (0.14 + position * 0.72) : x(position, size: size)
            let rect = CGRect(x: center - width / 2, y: tip - length, width: width, height: length)
            let color = colors[column % colors.count]
            context.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .linearGradient(
                Gradient(colors: [.clear, color.opacity(0.48), palette.highlight.opacity(0.66 + band * 0.34)]),
                startPoint: CGPoint(x: rect.midX, y: rect.minY),
                endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
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
                                      side: .right, mirrored: mirrored, lowPower: lowPower, innerInset: 0, splashDensity: splashDensity, plasmaSparks: plasmaSparks)
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
        }

        let sparkCount = Int((Double(lowPower ? 5 : 11) * plasmaSparks.density).rounded())
        guard sparkCount > 0 else { return }
        for index in 0..<sparkCount {
            let seed = Double(index) * 2.39996
            let progress = (Double(index) + 0.5) / Double(sparkCount)
            let cycle = phase * 0.65 + seed
            let age = cycle - floor(cycle)
            let radius = max(0.5, min(size.height, size.width) * 0.026) * plasmaSparks.size
            let center = x(progress, size: size)
            let dx = sin(seed + age * 4) * size.width * 0.025
            let spark = CGRect(x: center + dx - radius,
                               y: baseline - age * size.height * 0.8 - radius,
                               width: radius * 2, height: radius * 2)
            let opacity = sin(age * .pi) * min(1, 0.20 + (level + impact) * 0.60)
            context.fill(Path(ellipseIn: spark),
                         with: .color(palette.colors[index % 3].opacity(opacity)))
        }
    }
}
