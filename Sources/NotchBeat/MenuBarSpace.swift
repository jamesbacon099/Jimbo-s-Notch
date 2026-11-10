import AppKit
import ApplicationServices

enum TrailSide: CaseIterable {
    case left, right
}

struct TrailSizing: Equatable {
    enum Mode: String, CaseIterable {
        case automatic = "Auto Fit"
        case manual = "Manual"
    }

    static let lengthRange = 38.0...720.0
    static let heightRange = 5.0...42.0
    var mode: Mode
    var length: Double
    var height: Double

    init(defaults: UserDefaults = .standard) {
        mode = defaults.string(forKey: "trailSizingMode").flatMap(Mode.init(rawValue:)) ?? .automatic
        length = min(Self.lengthRange.upperBound,
                     max(Self.lengthRange.lowerBound, defaults.object(forKey: "trailLength") as? Double ?? 178))
        height = min(Self.heightRange.upperBound,
                     max(Self.heightRange.lowerBound, defaults.object(forKey: "trailHeight") as? Double ?? 26))
    }

    var requestedSize: CGSize? {
        mode == .manual ? CGSize(width: length, height: height) : nil
    }

    func saveChanges(from previous: TrailSizing, to defaults: UserDefaults = .standard) {
        if mode != previous.mode { defaults.set(mode.rawValue, forKey: "trailSizingMode") }
        if length != previous.length { defaults.set(length, forKey: "trailLength") }
        if height != previous.height { defaults.set(height, forKey: "trailHeight") }
    }
}

struct MenuBarSpace {
    static let minimumWidth: CGFloat = 38
    let leftArea: CGRect
    let rightArea: CGRect
    let axOriginY: CGFloat
    var hasSystemIsland = false

    func balancedLanes(occupied: MenuBarOccupancy, island: CGRect?, scale: CGFloat,
                       requestedSize: CGSize? = nil) -> (left: CGRect, right: CGRect)? {
        let left = lane(.left, occupied: occupied.left, island: island,
                        requestedHeight: requestedSize?.height, observed: occupied.observed)
        let right = lane(.right, occupied: occupied.right, island: island,
                         requestedHeight: requestedSize?.height, observed: occupied.observed)
        guard let left, let right else { return nil }

        let scale = max(1, scale)
        let originX = leftArea.minX
        let leftAnchor = originX + floor((left.maxX - originX) * scale) / scale
        let rightAnchor = originX + ceil((right.minX - originX) * scale) / scale
        let availableWidth = min(leftAnchor - left.minX, right.maxX - rightAnchor)
        let width = floor(min(availableWidth, requestedSize?.width ?? availableWidth) * scale) / scale
        let height = floor(min(left.height, right.height) * scale) / scale
        guard width >= Self.minimumWidth else { return nil }

        // Match the shorter lane's vertical placement and align to physical pixels.
        let center = left.height <= right.height ? left.midY : right.midY
        let top = leftArea.maxY
        let y = top + ((center - height / 2 - top) * scale).rounded() / scale
        let pair = (
            left: CGRect(x: leftAnchor - width, y: y, width: width, height: height),
            right: CGRect(x: rightAnchor, y: y, width: width, height: height)
        )
        guard leftArea.contains(pair.left), rightArea.contains(pair.right) else { return nil }
        return pair
    }

    func lane(_ side: TrailSide, occupied: [CGRect]?, island: CGRect? = nil,
              requestedHeight: CGFloat? = nil, observed: [CGRect] = []) -> CGRect? {
        let area = side == .left ? leftArea : rightArea
        let clearance: CGFloat = 15
        let near: CGFloat
        switch side {
        case .left: near = min(area.maxX, island?.minX ?? area.maxX) - clearance
        case .right: near = max(area.minX, island?.maxX ?? area.minX) + clearance
        }
        let compact = occupied == nil && requestedHeight == nil
        let items = (occupied ?? observed).filter { $0.intersects(area) }
        let far: CGFloat
        switch side {
        case .left:
            let limit = items.map(\.maxX).max() ?? area.minX
            far = compact ? max(near - 104, limit + 8) : limit + 8
        case .right:
            let limit = items.map(\.minX).min() ?? area.maxX
            far = compact ? min(near + 104, limit - 8) : limit - 8
        }

        let width = side == .left ? near - far : far - near
        guard width >= Self.minimumWidth else { return nil }
        let compactHeight: CGFloat = hasSystemIsland ? 12 : 8
        let desiredHeight = requestedHeight ?? (compact ? compactHeight : 26)
        let height = min(desiredHeight, area.height - 2)
        guard height >= 5 else { return nil }
        // A pill-shaped system island sits in the middle of the menu bar.
        let y: CGFloat
        if hasSystemIsland {
            let visibleCenter = island.map { (max(area.minY, $0.minY) + min(area.maxY, $0.maxY)) / 2 }
                ?? area.midY
            y = min(area.maxY - height - 1, max(area.minY + 1, visibleCenter - height / 2))
        } else {
            y = compact ? area.minY + 1 : area.midY - height / 2
        }
        let lane = CGRect(x: min(near, far), y: y, width: width, height: height)
        return area.contains(lane) ? lane : nil
    }
}

struct MenuBarOccupancy {
    var left: [CGRect]?
    var right: [CGRect]?
    var island: CGRect?
    var observed: [CGRect] = []
}

enum MenuBarReader {
    private enum Menu {
        case items([CGRect])
        case unavailable
    }

    static func occupiedFrames(frontPID: pid_t, statusPIDs: [pid_t], space: MenuBarSpace) -> MenuBarOccupancy {
        guard AXIsProcessTrusted() else { return MenuBarOccupancy() }

        func convert(_ frame: CGRect) -> CGRect {
            CGRect(x: frame.minX, y: space.axOriginY - frame.maxY, width: frame.width, height: frame.height)
        }

        var menus: [CGRect] = []
        if case let .items(appMenus) = frames(pid: frontPID, attribute: kAXMenuBarAttribute as String) {
            menus = appMenus.map(convert)
        }
        var statusItems: [CGRect] = []
        var completeStatus = true
        for pid in statusPIDs {
            if case let .items(items) = frames(pid: pid, attribute: "AXExtrasMenuBar") {
                statusItems.append(contentsOf: items.map(convert))
            } else {
                completeStatus = false
            }
        }
        let occupied = menus + statusItems
        return MenuBarOccupancy(
            left: menus.contains(where: { $0.intersects(space.leftArea) }) ? occupied : nil,
            right: completeStatus && statusItems.contains(where: { $0.intersects(space.rightArea) }) ? occupied : nil,
            island: space.hasSystemIsland ? IslandFootprint.accessible(in: space) : nil,
            observed: occupied
        )
    }

    private static func frames(pid: pid_t, attribute: String) -> Menu {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.045)
        var menu: CFTypeRef?
        switch AXUIElementCopyAttributeValue(app, attribute as CFString, &menu) {
        case .attributeUnsupported, .noValue, .invalidUIElement: return .items([])
        case .success: break
        default: return .unavailable
        }
        guard let menu, CFGetTypeID(menu) == AXUIElementGetTypeID() else { return .unavailable }
        var children: CFTypeRef?
        let element = menu as! AXUIElement
        var result = AXUIElementCopyAttributeValue(element, kAXVisibleChildrenAttribute as CFString, &children)
        if result != .success {
            result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        }
        if result == .noValue { return .items([]) }
        guard result == .success, let items = children as? [AXUIElement] else { return .unavailable }

        var rects: [CGRect] = []
        for item in items {
            guard let position = value(item, attribute: kAXPositionAttribute),
                  let size = value(item, attribute: kAXSizeAttribute) else { return .unavailable }
            var point = CGPoint.zero
            var dimensions = CGSize.zero
            if AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &dimensions),
               dimensions.width > 0, dimensions.height > 0 {
                rects.append(CGRect(origin: point, size: dimensions))
            }
        }
        return .items(rects)
    }

    private static func value(_ element: AXUIElement, attribute: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }
}
