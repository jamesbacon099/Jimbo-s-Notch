import AppKit

enum TrailSide: CaseIterable {
    case left, right
}

struct TrailSizing: Equatable {
    static let lengthRange = 38.0...720.0
    static let heightRange = 5.0...72.0
    static let verticalOffsetRange = -18.0...100.0
    static let gapRange = -10000.0...10000.0
    static let defaultGap = 15.0
    var length: Double
    var height: Double
    var gap: Double
    var verticalOffset: Double

    init(defaults: UserDefaults = .standard, prefix: String = "") {
        func saved(_ key: String) -> Double? {
            (defaults.object(forKey: prefix + key) ?? defaults.object(forKey: key)) as? Double
        }
        length = min(Self.lengthRange.upperBound,
                     max(Self.lengthRange.lowerBound, saved("trailLength") ?? 178))
        height = min(Self.heightRange.upperBound,
                     max(Self.heightRange.lowerBound, saved("trailHeight") ?? 26))
        verticalOffset = min(Self.verticalOffsetRange.upperBound,
                             max(Self.verticalOffsetRange.lowerBound, saved("trailVerticalOffset") ?? 0))
        let savedGap = saved("trailGap") ?? Self.defaultGap
        gap = min(Self.gapRange.upperBound, max(Self.gapRange.lowerBound, savedGap))
    }

    var requestedSize: CGSize {
        CGSize(width: length, height: height)
    }

    func saveChanges(from previous: TrailSizing, to defaults: UserDefaults, prefix: String) {
        if length != previous.length { defaults.set(length, forKey: prefix + "trailLength") }
        if height != previous.height { defaults.set(height, forKey: prefix + "trailHeight") }
        if verticalOffset != previous.verticalOffset { defaults.set(verticalOffset, forKey: prefix + "trailVerticalOffset") }
        if gap != previous.gap { defaults.set(gap, forKey: prefix + "trailGap") }
    }
}

struct MenuBarSpace: Equatable, Sendable {
    static let minimumWidth: CGFloat = 38
    let leftArea: CGRect
    let rightArea: CGRect
    let windowOriginY: CGFloat
    var hasSystemIsland = false

    var hasNotch: Bool { hasSystemIsland || leftArea.maxX < rightArea.minX }

    static func forDisplay(frame: CGRect, auxiliaryLeft: CGRect?, auxiliaryRight: CGRect?,
                           barHeight: CGFloat, originY: CGFloat, systemIsland: Bool) -> MenuBarSpace {
        var leftEdge = frame.midX
        var rightEdge = frame.midX
        if let left = auxiliaryLeft, let right = auxiliaryRight,
           left.maxX >= frame.minX, right.minX <= frame.maxX, right.minX > left.maxX {
            leftEdge = left.maxX
            rightEdge = right.minX
        }
        let bottom = frame.maxY - barHeight
        return MenuBarSpace(
            leftArea: CGRect(x: frame.minX, y: bottom, width: leftEdge - frame.minX, height: barHeight),
            rightArea: CGRect(x: rightEdge, y: bottom, width: frame.maxX - rightEdge, height: barHeight),
            windowOriginY: originY,
            hasSystemIsland: systemIsland
        )
    }

    private func anchorGeometry(island: CGRect?) -> (center: CGFloat, halfWidth: CGFloat, distance: CGFloat) {
        let center = (leftArea.minX + rightArea.maxX) / 2
        let notchCenter = (leftArea.maxX + rightArea.minX) / 2
        let compactHalfWidth = hasSystemIsland ? IslandFootprint.compactSystemWidth / 2 : 0
        let leftBoundary = min(leftArea.maxX, notchCenter - compactHalfWidth, island?.minX ?? leftArea.maxX)
        let rightBoundary = max(rightArea.minX, notchCenter + compactHalfWidth, island?.maxX ?? rightArea.minX)
        let distance = max(center - leftBoundary, rightBoundary - center)
        return (center, (rightArea.maxX - leftArea.minX) / 2, distance)
    }

    func gapRange(island: CGRect?) -> ClosedRange<Double> {
        let geometry = anchorGeometry(island: island)
        return -Double(geometry.distance)...Double(max(0, geometry.halfWidth - geometry.distance))
    }

    func balancedLanes(island: CGRect?, scale: CGFloat,
                       requestedSize: CGSize, gap: CGFloat, verticalOffset: CGFloat = 0,
                       centeredOnAnchor: Bool = false, fillToEdges: Bool = false) -> (left: CGRect, right: CGRect)? {
        let scale = max(1, scale)
        let geometry = anchorGeometry(island: island)
        let distance = min(geometry.halfWidth, max(0, geometry.distance + gap))
        let leftAnchor = (geometry.center - distance) * scale
        let rightAnchor = (geometry.center + distance) * scale
        let availableWidth = geometry.halfWidth - distance
        let widthLimit = fillToEdges
            ? max(Self.minimumWidth, availableWidth * (centeredOnAnchor ? 2 : 1))
            : min(geometry.halfWidth, requestedSize.width)
        let width = floor(widthLimit * scale) / scale
        let height = floor(requestedSize.height * scale) / scale
        guard width >= Self.minimumWidth, height >= 5 else { return nil }

        let top = leftArea.maxY
        let bottom = leftArea.minY
        let visibleCenter = island.map { (max(bottom, $0.minY) + min(top, $0.maxY)) / 2 } ?? leftArea.midY
        // Anchor the top at the reference trail height. Height adds room below it.
        let anchorTop = min(top - 1, visibleCenter + 13)
        let y = top + ((anchorTop - verticalOffset - height - top) * scale).rounded() / scale

        // Length changes the extent around a fixed anchor. Screen edges clip the
        // overflow, so changing length never pushes the anchor back into view.
        return (
            CGRect(x: leftAnchor.rounded() / scale - (centeredOnAnchor ? width / 2 : width),
                   y: y, width: width, height: height),
            CGRect(x: rightAnchor.rounded() / scale - (centeredOnAnchor ? width / 2 : 0),
                   y: y, width: width, height: height)
        )
    }
}
