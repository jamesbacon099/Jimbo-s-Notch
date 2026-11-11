import AppKit

enum TrailSide: CaseIterable {
    case left, right
}

struct TrailSizing: Equatable {
    static let lengthRange = 38.0...720.0
    static let heightRange = 5.0...42.0
    static let gapRange = -12.0...100.0
    static let defaultGap = 15.0
    var length: Double
    var height: Double
    var gap: Double

    init(defaults: UserDefaults = .standard) {
        length = min(Self.lengthRange.upperBound,
                     max(Self.lengthRange.lowerBound, defaults.object(forKey: "trailLength") as? Double ?? 178))
        height = min(Self.heightRange.upperBound,
                     max(Self.heightRange.lowerBound, defaults.object(forKey: "trailHeight") as? Double ?? 26))
        let savedGap = defaults.object(forKey: "trailGap") as? Double ?? Self.defaultGap
        gap = min(Self.gapRange.upperBound, max(Self.gapRange.lowerBound, savedGap))
    }

    var requestedSize: CGSize {
        CGSize(width: length, height: height)
    }

    func saveChanges(from previous: TrailSizing, to defaults: UserDefaults = .standard) {
        if length != previous.length { defaults.set(length, forKey: "trailLength") }
        if height != previous.height { defaults.set(height, forKey: "trailHeight") }
        if gap != previous.gap { defaults.set(gap, forKey: "trailGap") }
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

    func balancedLanes(island: CGRect?, scale: CGFloat,
                       requestedSize: CGSize, gap: CGFloat) -> (left: CGRect, right: CGRect)? {
        let scale = max(1, scale)
        let originX = leftArea.minX
        // Mirror around the display midpoint while clearing both the window and hardware bounds.
        let centerInPixels = ((rightArea.maxX - originX) * scale).rounded() / 2
        let notchCenter = (leftArea.maxX + rightArea.minX) / 2
        let compactHalfWidth = hasSystemIsland ? IslandFootprint.compactSystemWidth / 2 : 0
        let leftBoundary = min(leftArea.maxX, notchCenter - compactHalfWidth, island?.minX ?? leftArea.maxX)
        let rightBoundary = max(rightArea.minX, notchCenter + compactHalfWidth, island?.maxX ?? rightArea.minX)
        // Negative gaps can tuck into the reported island frame, up to the physical notch.
        let leftNear = min(leftArea.maxX, leftBoundary - gap)
        let rightNear = max(rightArea.minX, rightBoundary + gap)
        let leftLimit = (leftNear - originX) * scale
        let rightLimit = (rightNear - originX) * scale
        let leftPixel = floor(min(leftLimit, 2 * centerInPixels - rightLimit))
        let leftAnchor = originX + leftPixel / scale
        let rightAnchor = originX + (2 * centerInPixels - leftPixel) / scale
        let availableWidth = min(leftAnchor - leftArea.minX, rightArea.maxX - rightAnchor) - 8
        let width = floor(min(availableWidth, requestedSize.width) * scale) / scale
        let height = floor(min(requestedSize.height, leftArea.height - 2) * scale) / scale
        guard width >= Self.minimumWidth, height >= 5 else { return nil }

        let top = leftArea.maxY
        let bottom = leftArea.minY
        let visibleCenter = island.map { (max(bottom, $0.minY) + min(top, $0.maxY)) / 2 } ?? leftArea.midY
        let idealY = visibleCenter - height / 2
        let boundedY = min(top - height - 1, max(bottom + 1, idealY))
        let y = top + ((boundedY - top) * scale).rounded() / scale
        let pair = (
            left: CGRect(x: leftAnchor - width, y: y, width: width, height: height),
            right: CGRect(x: rightAnchor, y: y, width: width, height: height)
        )
        guard leftArea.contains(pair.left), rightArea.contains(pair.right) else { return nil }
        return pair
    }
}
