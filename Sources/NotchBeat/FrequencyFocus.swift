import Foundation

enum FrequencyFocus: String, CaseIterable {
    case fullMix = "Full mix"
    case bass = "Bass"
    case vocals = "Vocals"

    // Same logarithmic band centers as AudioAnalysis.
    private static let centers = (0..<16).map { 45 * pow(300, (Double($0) + 0.5) / 16) }

    private static func weights(from low: Double, through high: Double) -> SIMD16<Float> {
        var result = SIMD16<Float>(repeating: 0)
        for (index, frequency) in centers.enumerated() {
            let distance = max(0, log2(low / frequency), log2(frequency / high))
            result[index] = Float(max(0, 1 - distance / 0.7))
        }
        return result
    }

    private static let bassWeights = weights(from: 45, through: 170)
    private static let vocalWeights = weights(from: 240, through: 4200)

    func apply(to channel: inout ChannelFrame) {
        guard self != .fullMix else { return }
        let weights = self == .bass ? Self.bassWeights : Self.vocalWeights
        let broadbandPeak = channel.bands.max()
        channel.bands *= weights
        let focusedPeak = self == .bass ? max(channel.bands.max(), channel.bass) : channel.bands.max()
        let share = min(1, focusedPeak / max(0.0001, broadbandPeak))
        channel.level = min(channel.level, focusedPeak * 2.4)
        channel.bass = self == .bass ? focusedPeak : focusedPeak * 0.30
        channel.impact *= share * share
        channel.waveform.high *= share
        channel.waveform.low *= share
        if share < 0.2 { channel.lastHit = nil }
    }
}
