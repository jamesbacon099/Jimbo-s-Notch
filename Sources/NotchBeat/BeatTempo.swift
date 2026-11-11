import Foundation

/// A bounded onset-interval estimate; it does not assume every transient is a beat.
struct BeatTempo {
    private(set) var duration: TimeInterval = 0.5
    private(set) var anchor: TimeInterval?
    private var intervals: [TimeInterval] = []

    mutating func update(hit: TimeInterval) {
        guard hit > 0, hit.isFinite, hit > (anchor ?? 0) else { return }
        guard let previous = anchor else {
            anchor = hit
            return
        }
        var interval = hit - previous
        guard interval >= 0.22 else { return }
        anchor = hit
        guard interval <= 2 else {
            intervals.removeAll(keepingCapacity: true)
            duration = 0.5
            return
        }
        while interval < 1.0 / 3 { interval *= 2 }
        while interval > 1 { interval /= 2 }
        intervals.append(interval)
        if intervals.count > 12 { intervals.removeFirst() }
        let sorted = intervals.sorted()
        let median = sorted[sorted.count / 2]
        duration = intervals.count < 3 ? median : duration * 0.8 + median * 0.2
    }
}
